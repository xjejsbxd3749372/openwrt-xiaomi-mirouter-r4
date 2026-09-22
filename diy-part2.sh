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

# 3) 19.07 板级网络与升级配置注入 (兼容性高防错处理)
echo "==> 正在配置 19.07 分支下的网络与固件升级兼容性..."

# 19.07 的网口定义文件在 ramips 根目录下的 01_network 中，而不是 mt7621 子目录下
FILES_TO_PATCH=(
  "target/linux/ramips/base-files/etc/board.d/01_network"
  "target/linux/ramips/mt7621/base-files/lib/upgrade/platform.sh"
  "package/boot/uboot-envtools/files/ramips"
)

for f in "${FILES_TO_PATCH[@]}"; do
  if [ -f "$f" ]; then
    echo "正在处理文件: $f"
    # 将包含 mir3g 的地方兼容扩展支持 mir4
    sed -i -E 's/^([[:space:]]*)(xiaomi,)?mir3g(\||\))/\1\2mir3g|\2mir4\3/' "$f"
    if grep -q 'mir4' "$f"; then
      echo "成功在 $f 中为 mir4 注入兼容逻辑！"
    else
      echo "::warning:: 文件 $f 未能成功匹配注入，可能格式有变"
    fi
  else
    echo "::warning:: 19.07 分支中未检测到文件 $f，已安全跳过此路径"
  fi
done

# 4) 给旧内核增加 zstd 支持
CFG=target/linux/ramips/mt7621/config-4.14
if [ -f "$CFG" ]; then
    grep -q '^CONFIG_CRYPTO_ZSTD=y' "$CFG" || echo 'CONFIG_CRYPTO_ZSTD=y' >> "$CFG"
    echo "内核已追加配置 ZSTD 支持。"
fi

echo "🎉 所有 19.07 适配补丁全部执行完毕！"
