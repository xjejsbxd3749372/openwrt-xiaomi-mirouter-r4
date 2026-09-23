#!/usr/bin/env bash
# 在 openwrt 源码根目录执行：把 Xiaomi Mi Router 4 (mir4) 完美加进 19.07 编译体系
set -euo pipefail

WS="${GITHUB_WORKSPACE:-$(cd .. && pwd)}"
DTS_DIR=target/linux/ramips/dts
MK=target/linux/ramips/image/mt7621.mk

# 1) 注入本地 DTS 文件
if [ -f "$WS/files/MIR4.dts" ]; then
    echo "==> 正在注入小米路由 4 的 DTS 设备树..."
    cp "$WS/files/MIR4.dts" "$DTS_DIR/MIR4.dts"
else
    echo "::error::在本地仓库中未找到 files/MIR4.dts 文件！"
    exit 1
fi

# 2) 注入 image/mt7621.mk 的设备定义块 (精准匹配 19.07 官方的 Device/xiaomi_mir3g)
python3 - "$MK" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
if re.search(r'^define Device/mir4$', s, re.M):
    print("mir4 设备定义已存在，安全跳过"); sys.exit(0)

# 在 19.07 分支中，官方原始命名是大写的 xiaomi_mir3g
m = re.search(r'^define Device/xiaomi_mir3g\n.*?^TARGET_DEVICES \+= xiaomi_mir3g\n', s, re.S | re.M)
if not m:
    sys.exit("::error::在 %s 编译配置里没找到 Device/xiaomi_mir3g 模板模块" % p)

blk = m.group(0)
# 将模板整体克隆，并替换为你的 config.seed 识别的 mir4 纯净标识
new = (blk.replace('xiaomi_mir3g', 'mir4')
          .replace('MIR3G', 'MIR4')
          .replace('Mi Router 3G', 'Mi Router 4'))

# 小米路由器 4 没有 3G 的 USB 接口，在此安全剔除多余的 USB 驱动组件
new = re.sub(r'[ \t]*kmod-usb3|[ \t]*kmod-usb-ledtrig-usbport', '', new)
s = s.replace(blk, blk + '\n' + new)
open(p, 'w').write(s)
print("已成功修正并注入 Device/mir4 编译块")
PY

# 3) 19.07 板级网络与升级配置注入
echo "==> 正在配置 19.07 分支下 MIR4 网络与升级兼容..."

# -------------------------------------------------
# 1. 网络配置：单独添加 MIR4
# -------------------------------------------------

NETWORK_FILE="target/linux/ramips/base-files/etc/board.d/02_network"

if [ -f "$NETWORK_FILE" ]; then

    echo "==> 检查 $NETWORK_FILE"

    if grep -q "xiaomi,mir4" "$NETWORK_FILE"; then
        echo "MIR4 网络配置已经存在，跳过"
    else

        echo "==> 正在注入 MIR4 switch 配置"

        python3 - "$NETWORK_FILE" <<'PY'
import sys

file = sys.argv[1]

data = open(file).read()

# 找到 xiaomi,mir3g case
target = '''xiaomi,mir3g)'''

if target not in data:
    print("未找到 mir3g 网络配置，请检查文件结构")
    sys.exit(0)


insert = r'''
xiaomi,mir4)
	ucidef_add_switch "switch0" \
		"1:lan:2" "2:lan:1" "4:wan" "6t@eth0"
	;;

'''

data = data.replace(
    target,
    insert + target,
    1
)

open(file,"w").write(data)

print("MIR4 网络 switch 配置注入完成")

PY

    fi

else
    echo "::warning:: 未找到 $NETWORK_FILE"
fi



# -------------------------------------------------
# 2. 升级脚本 platform.sh 自动兼容 MIR4
# -------------------------------------------------

PLATFORM_FILE="target/linux/ramips/base-files/lib/upgrade/platform.sh"

if [ -f "$PLATFORM_FILE" ]; then

    echo "==> 处理 upgrade platform.sh"

    sed -i -E \
    's/(xiaomi,)?mir3g/\1mir3g|\1mir4/g' \
    "$PLATFORM_FILE"

    grep -q "mir4" "$PLATFORM_FILE" \
        && echo "platform.sh MIR4 注入成功" \
        || echo "::warning:: platform.sh 未发现 MIR4"

else
    echo "::warning:: 未找到 $PLATFORM_FILE"
fi



# -------------------------------------------------
# 3. uboot-envtools 自动兼容
# -------------------------------------------------

UBOOT_FILE="package/boot/uboot-envtools/files/ramips"

if [ -f "$UBOOT_FILE" ]; then

    echo "==> 处理 uboot-envtools"

    sed -i -E \
    's/(xiaomi,)?mir3g/\1mir3g|\1mir4/g' \
    "$UBOOT_FILE"

    grep -q "mir4" "$UBOOT_FILE" \
        && echo "uboot-envtools MIR4 注入成功" \
        || echo "::warning:: uboot-envtools 未发现 MIR4"

else
    echo "::warning:: 未找到 $UBOOT_FILE"
fi


echo "==> MIR4 板级兼容配置完成"

# 4) 给旧内核增加 zstd 支持
CFG=target/linux/ramips/mt7621/config-4.14
if [ -f "$CFG" ]; then
    grep -q '^CONFIG_CRYPTO_ZSTD=y' "$CFG" || echo 'CONFIG_CRYPTO_ZSTD=y' >> "$CFG"
    echo "内核已追加配置 ZSTD 支持。"
fi

echo "🎉 所有 19.07 适配补丁全部执行完毕！"
