#!/usr/bin/env bash
# 在 openwrt 源码根目录执行：把 Xiaomi Mi Router 4 (mir4) 加进 19.07
# 做法：以 mir3g 的定义为模板复制一份，DTS 用 files/MIR4.dts
set -euo pipefail

WS="${GITHUB_WORKSPACE:-$(cd .. && pwd)}"
DTS_DIR=target/linux/ramips/dts
MK=target/linux/ramips/image/mt7621.mk

[ -f "$DTS_DIR/MIR3G.dts" ] || { echo "::error::找不到 $DTS_DIR/MIR3G.dts，分支不对？"; exit 1; }

# 1) DTS
cp "$WS/files/MIR4.dts" "$DTS_DIR/MIR4.dts"

# 2) image/mt7621.mk：精确匹配官方 19.07 里的 Device/xiaomi_mir3g 块，改名为 mir4
python3 - "$MK" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()

# 检查是否已经注入过
if re.search(r'^define Device/mir4$', s, re.M):
    print("mir4 已存在，跳过"); sys.exit(0)

# 在 19.07 中，官方名称是大写的 Device/xiaomi_mir3g 并且末尾是 TARGET_DEVICES += xiaomi_mir3g
m = re.search(r'^define Device/xiaomi_mir3g\n.*?^TARGET_DEVICES \+= xiaomi_mir3g\n', s, re.S | re.M)
if not m:
    sys.exit("::error::在 %s 里没找到 Device/xiaomi_mir3g 块" % p)

blk = m.group(0)

# 将模板复制并替换为你的配置需要的 mir4 名字
new = (blk.replace('xiaomi_mir3g', 'mir4')
          .replace('MIR3G', 'MIR4')
          .replace('Mi Router 3G', 'Mi Router 4'))

# 小米路由 4 (R4) 硬件上砍掉了 USB 接口，用正则剔除 USB 相关驱动模块
new = re.sub(r'[ \t]*kmod-usb3|[ \t]*kmod-usb-ledtrig-usbport', '', new)

# 拼接到原块后面
s = s.replace(blk, blk + '\n' + new)
open(p, 'w').write(s)
print("已成功修正并生成 Device/mir4：\n" + new)
PY

# 3) 板级 case 分支：凡是 xiaomi,mir3g 的地方都加上 xiaomi,mir4
for f in \
  target/linux/ramips/mt7621/base-files/etc/board.d/02_network \
  target/linux/ramips/mt7621/base-files/lib/upgrade/platform.sh \
  package/boot/uboot-envtools/files/ramips
do
  [ -f "$f" ] || { echo "::error::缺少文件 $f"; exit 1; }
  sed -i -E 's/^([[:space:]]*)(xiaomi,)?mir3g(\||\))/\1\2mir3g|\2mir4\3/' "$f"
  grep -q 'mir4' "$f" || { echo "::error::$f 里没有匹配到 mir3g 分支，需要手动检查"; exit 1; }
  echo "== $f"; grep -n 'mir4' "$f"
done

# 4) （可选）zram 用 zstd：给内核加 zstd 支持
CFG=target/linux/ramips/mt7621/config-4.14
grep -q '^CONFIG_CRYPTO_ZSTD=y' "$CFG" || echo 'CONFIG_CRYPTO_ZSTD=y' >> "$CFG"
