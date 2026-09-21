# OpenWrt 19.07 for Xiaomi Mi Router 4 (MIR4) — GitHub Actions

用法：
1. 新建仓库，把这个目录的内容原样传上去（含 `.github/`）
2. Actions → `Build OpenWrt 19.07 (Xiaomi Mi Router 4)` → Run workflow
3. 约 1.5～2.5 小时后，在该次运行页面底部 Artifacts 下载
   `kernel1.bin` / `rootfs0.bin`（首次刷入）和 `sysupgrade.bin`（以后升级）

文件说明：
- `files/MIR4.dts`   R4 的设备树（由 MIR3G.dts 改）
- `diy-part2.sh`     把 mir4 加进 19.07 的补丁脚本
- `config.seed`      编译配置（diffconfig，`make defconfig` 会补全）
