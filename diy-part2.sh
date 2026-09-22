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

# 2) image/mt7621.mk：复制 Device/xiaomi_mi-router-3g 整块，改名为 mir4
python3 - "$MK" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
if re.search(r'^define Device/xiaomi_mir4$', s, re.M):
    print("mir4 已存在，跳过"); sys.exit(0)

# 正确匹配 OpenWrt 19.07 中的 xiaomi_mi-router-3g 块
m = re.search(r'^define Device/xiaomi_mi-router-3g\n.*?^TARGET_DEVICES \+= xiaomi_mi-router-3g\n', s, re.S | re.M)
if not m:
    sys.exit("::error::在 %s 里没找到 Device/xiaomi_mi-router-3g 块" % p)

blk = m.group(0)
# 进行针对 Xiaomi Mi Router 4 的替换
new = (blk.replace('xiaomi_mi-router-3g', 'xiaomi_mir4')
          .replace('MIR3G', 'MIR4')
          .replace('Mi Router 3G', 'Mi Router 4'))

# R4 没有 USB，移除相关软件包定义
new = re.sub(r'[ \t]*kmod-usb3|[ \t]*kmod-usb-ledtrig-usbport', '', new)

s = s.replace(blk, blk + '\n' + new)
open(p, 'w').write(s)
print("已成功生成 Device/xiaomi_mir4：\n" + new)
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
