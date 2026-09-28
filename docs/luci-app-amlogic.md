# 晶晨宝盒 (luci-app-amlogic / Amlogic Service) 调研记录

> 主题：LubanCat-1 (rockchip) 平台接入晶晨宝盒的机制、依赖、升级路径与分区真相。
> 状态：调研完成，依赖已补充并提交 (`77eb53d`)；双槽 OTA 可用性待重刷 TF 卡实机验证。
> 日期：2026-09-27

---

## 1. 晶晨宝盒是什么

`ophub/luci-app-amlogic` 是 ophub 为「Arm 电视盒子 / 开发板」打造的 LuCI 插件（Amlogic Service），用于在线管理在盒子/板卡上运行的 OpenWrt。功能六项：

- Install OpenWrt（安装到 eMMC）
- Manual Upload Update（手动上传更新固件/内核）
- Online Download Update（在线下载更新固件/内核）
- Firmware Configuration Backup（配置备份/恢复）
- Snapshot management（快照管理）
- Plugin Settings / CPU Settings（定制固件/内核下载源、CPU 调频）

**版本形态**：有 **Lua 版（lua 分支）** 和 **JavaScript 版（main 分支）**。ImmortalWrt 25.12 / 新版 LuCI 为 JS 架构，**必须用 JS 版**。release tag 带 `-js` 后缀（如 `3.1.321-js`），仓库 main 分支即 JS 版（当前 `3.1.321-r2`，commit `8fe2b60`）。

---

## 2. 如何引入（选择「加 feed 编译」方案）

### 背景：两个候选方案
参考仓库 `amlogic-s9xxx-openwrt` 有两种引入方式：
- **ImageBuilder 方式**（`config/imagebuilder/imagebuilder.sh` 124-158 / 220 行）：下载 ophub release 的 `.ipk/.apk` 成品塞进 ImageBuilder `packages/`，`make image PACKAGES="... luci-app-amlogic luci-i18n-amlogic-zh-cn ..."`。**仅适用于 ImageBuilder**，我们是完整源码编译，不用。
- **加 feed 编译**（`documents/README.md` §8.1）：把源码作为 feed 引入，编译进固件。

**本项目采用「加 feed 编译」**（用户拍板），与完整源码编译架构匹配。

### 落地改动
**`feeds.conf`**（提交 `77eb53d`）新增第三方源，锁 commit 防漂移：
```
src-git amlogic https://github.com/ophub/luci-app-amlogic.git^8fe2b60b4d63e2d83fbe5eb12c37c77a892c0117
```
- `8fe2b60` = ophub main 最新（JS 版 3.1.321-r2）
- workflow 用 `feeds update/install -a` 全量，5 平台都拉该源；但只有 **lubancat1.conf** 里 `+CONFIG_PACKAGE_luci-app-amlogic=y`，其他平台不编入

**`config/platform/lubancat1.conf`**（提交 `77eb53d`）：
```
+CONFIG_PACKAGE_luci-app-amlogic=y
+CONFIG_PACKAGE_luci-i18n-amlogic-zh-cn=y
```

### 关键确认点
- 仓库是标准 LuCI **JS 包**（`luci.mk` 模板，controller 用 ucode，view 用 `resources/view/amlogic/*.js`），与 ImmortalWrt 25.12 兼容
- 包在仓库 `luci-app-amlogic/` 子目录，OpenWrt feeds `SCAN_DEPTH=5`（`scripts/feeds` 136 行）能识别
- `LUCI_DEPENDS` 声明的依赖（fdisk/lsblk/uuidgen/losetup/parted/dosfstools/jq/pv/perl/blkid）与本项目补的依赖闭环

---

## 3. 依赖补齐（ophub amlogic 工具链运行期）

登录 LubanCat-1 实机 `command -v` 逐项实测 + 交叉核对 luci-app-amlogic 脚本（install/update/backup/ddbr 共 2849 行）源码调用，得出缺失清单（每个都有脚本行号依据）。已全部补入 `lubancat1.conf`（见下），作用是让 ophub 安装/更新脚本能跑起来。

| 类别 | 包 | 脚本调用点 | 说明 |
|------|-----|-----------|------|
| A 磁盘/分区 | `fdisk` | install 275-403 | 重写 eMMC 分区表 |
| | `lsblk` | 23 处 (87-103 等) | 定位 eMMC/根分区 |
| | `uuidgen` | install 488-495 | 生成 btrfs 双槽 UUID |
| | `losetup` | update 955-1018 | 挂载固件镜像到 loop |
| | `parted` | update 1156-1160 | 在线增删 OTA 分区 |
| | `dosfstools` | 482 `mkfs.fat` | 建 FAT32 BOOT 分区 |
| | `xfs-mkfs` | 709 `mkfs.xfs` | 共享分区选 xfs 时 |
| B 压缩 | `bsdtar` | 852 | 解 `.img.gz` |
| | `unzip` | 858 | 解 zip 固件 |
| | `xz-utils` | 842 `xz -d` | 解 `.img.xz`（meta 包提供 xz 命令） |
| | `zstd`/`pigz` | 10.11 钦定 | 解压/多线程 gzip |
| C 工具 | `perl`+`perlbase-*` | sysinfo | 修复登录 `can't execute perl` |
| | `jq` | 1041-1047 | 读 docker daemon.json（可选） |
| | `gawk`/`pv` | awk 管道 / ddbr 2308-2317 | awk 增强 / 进度条 |
| | `coreutils`+`coreutils-nohup` | 10.11 System 区 | 标准工具补全 |

**设备已有无需补**：blkid、partx、hexdump、mkfs.ext4/btrfs/f2fs、btrfs、7z、tar、gzip、fatlabel。

**冗余剔除**（脚本 0 处调用）：sfdisk、partx-utils、getopt、blkid、mksquashfs、findmnt。

> 依据来源：`amlogic-s9xxx-openwrt documents/README.md` §10.11 Required Options + luci-app-amlogic 脚本源码 + 实机 `command -v` 三方交叉（2026-09-27）。

---

## 4. 晶晨宝盒升级机制（手动/在线）

### 平台脚本分发（`luci.amlogic` ucode 106-116 行）
```
rockchip   → install: null,  update: openwrt-update-rockchip,  kernel: openwrt-kernel
amlogic    → install: openwrt-install-amlogic, ...
allwinner  → install: openwrt-install-allwinner, ...
```
**LubanCat 是 rockchip → 无「Install to eMMC」功能，但 update/kernel 脚本存在**。

> 注意：rockchip 的 `install` 为空，即晶晨宝盒没有「安装到 eMMC」按钮（对 rockchip 板，直接整卡刷 .img 即可）。但 update（rootfs）和 kernel（内核）是有的。

### 更新文件如何分类（`luci.amlogic` 595-617 行）
- **固件包（rootfs）**：后缀 `.img.gz`/`.img.xz`/`.7z`/`.img` → 走 `openwrt-update-rockchip`
- **内核包**：boot + dtb + modules 三个文件同时存在 → 走 `openwrt-kernel`

### 在线更新的下载源与文件匹配（`amlogic_check_firmware.sh`）
- 读 `/etc/config/amlogic` 的 `amlogic_firmware_repo`（当前模板 = `ophub/amlogic-s9xxx-openwrt`）
- 抓该仓库 release 前 5 页 tag，用 `amlogic_firmware_tag`（`_openwrt_main_`）过滤
- 按文件名正则匹配（185 行）：
  ```
  .*_${BOARD}_.*k${main_line_version}\.[0-9]+.*.img.gz
  ```
- 下载 + sha256 校验（249-269 行），再调用 update 脚本

**结论**：默认 `amlogic_firmware_repo` 指向 ophub 官方仓库，**在线更新会去 ophub 找固件，不会要自己 CI 发布的固件**。要让在线更新指向自己的发布，需改该配置 + 固件命名匹配 ophub 模式（命名已基本匹配 `openwrt_rockchip_lubancat-1_k*.img.gz`）。**手动上传更新不受此影响**（用本地文件）。

---

## 5. 分区真相：为什么「单槽」→ 首启自动扩成「多槽」

### 5.1 官方 img 打包 = 单根（已验证）
实际下载官方固件 `openwrt_immortalwrt_rockchip_lubancat-1_k6.18.51_2026.09.14.img.gz`（immortalwrt_master 系，`OpenWrt_immortalwrt_master_save_2026.09` release），解压逐字节解析 GPT 分区表：
```
分区1: LBA 32768→817151   383MB  ext4   boot
分区2: LBA 819200→3438591  1279MB btrfs  rootfs
无分区3/4；GPT 无额外条目；尾部仅 ~1MB 未分配
```
remake 封装产物（`ophub/remake` 801-826 行）所有平台统一：`parted mkpart boot + mkpart btrfs 100%` → 单根。**官方包与我们的 remake 产物一致，都是单 rootfs。**

### 5.2 首启自动扩分区（关键机制，openwrt-tf）
单根是**打包时**的形态，但固件带**首启自动扩容**：
- remake 打包时写标记 `.todo_rootfs_resize=yes`（`ophub/remake` 1201 行）
- 首启 `start_service.sh`（161-165 行）检测标记 → 后台调用 `/usr/sbin/openwrt-tf`
- `openwrt-tf`（`common-files/usr/sbin/openwrt-tf` 84-163 行）在 p2 后用 parted 新建：
  ```
  parted mkpart primary btrfs <p3_start> <p3_start+1023>MiB   # p3 = 1GB btrfs ROOTFS2
  parted mkpart primary btrfs <p3_start+1024>MiB  100%         # p4 = 剩余 btrfs SHARED
  mkfs.btrfs -L MMC_ROOTFS2  p3     # OTA 备用 rootfs 槽
  mkfs.btrfs -L MMC_SHARED   p4     # 共享数据分区
  ```
- 然后把 `/opt/docker` 软链到 `p4/docker`，改写 docker `daemon.json` 的 `data-root`
- 完成后 `rm -f .todo_rootfs_resize`

**正常首启后卡 = p1(boot) + p2(rootfs 当前) + p3(ROOTFS2 备用) + p4(SHARED) 四分区** —— 这就是「TF 卡刷完空闲空间被自动挂载成多分区」的来源。

> 注：p4(SHARED) 未建成时（如缺 parted），openwrt-tf 的 docker 迁移不执行，`/opt/docker` 仍是 rootfs 里的**真实目录**，并会被 bind 挂载到同一 rootfs 分区（`df` 里表现为 `/dev/mmcblk0p2` 挂载 `/` 和 `/opt/docker` 两处）——这是退化回退形态，非异常；docker data 此时占 rootfs 分区。p4 建成后 `/opt/docker` 变为指向 p4 的软链，双挂载消失、docker data 迁到大分区。

### 5.3 为什么当前这台设备还是单槽（缺 parted）
设备实机实测分区（2026-09-27，`/sys/block` size 扇区 ÷ 2048 = MB）：
```
/dev/mmcblk0   29.7GB (TF 卡，62333952 扇区)
  p1  383MB  BOOT   (start 32768, size 784384 扇区 → df 342.7M ext4)
  p2  1279MB ROOTFS (start 819200, size 2619392 扇区 → df 1.2G btrfs)
  无 p3/p4
```
且 `.todo_rootfs_resize` 标记**仍在**（未删除=扩容未完成）。启动日志确认 openwrt-tf 已启动：
```
[2026.09.27.20:17:35] Automatic partition expansion (openwrt-tf) started.
```
**根因：设备当前跑的旧固件（v25.12.2，早于本次依赖补齐）没编入 parted/fdisk/losetup/uuidgen**，而 `openwrt-tf` 建分区用 `parted mkpart` → parted 缺失 → 建 p3/p4 失败 → 扩容未完成 → 保持单槽。（补依赖的 `77eb53d` 之后新固件会带上这些工具。）

### 5.4 依赖补齐后的意义（重要）
`openwrt-update-rockchip`（438-455 行）要求**双槽**：当前 root 在 p2 → 写 `p3`（ROOTFS2）；在 p3 → 写回 p2。设备单槽时（无 p3）会报 "new root partition is not exists" 失败。

- **补依赖前**：重刷 → openwrt-tf 因缺 parted 失败 → 保持单槽 → `openwrt-update-rockchip` 无 p3 可用 → **晶晨宝盒 rootfs 更新用不了**
- **补依赖后**（本次 `77eb53d` 已补 parted/fdisk/losetup/uuidgen）：重刷 → openwrt-tf 成功建出 p3(ROOTFS2)+p4(SHARED) → **双槽 OTA 就位 → `openwrt-update-rockchip` 可以正常更新 rootfs/内核**

> 即：**补依赖让晶晨宝盒手动更新（rootfs + 内核）在这台设备上真正可用**。

---

## 6. 当前状态与待验证

### 已落地
- 依赖补齐（A/B/C）已提交 `77eb53d`
- luci-app-amlogic 引入（feeds.conf + lubancat1.conf）已提交 `77eb53d`

### 待验证（双槽 OTA 可用性）
目前设备仍是单槽（缺 parted 的固件跑的旧结果）。要确证双槽 OTA 可用，需：
1. 拿**包含补依赖**的 LubanCat 固件（待 CI 构建）重刷 TF 卡
2. 首启后确认自动出现 `p3(ROOTFS2)+p4(SHARED)`（`.todo_rootfs_resize` 被删除）
3. 实测 `openwrt-update-rockchip` 能否跑通（rootfs 更新）
4. 内核更新路径（`openwrt-kernel`，走 /boot）确认

### 相关文件
- 引入：`feeds.conf`、`config/platform/lubancat1.conf`
- 上游参考：`/workspace/openwrt/amlogic-s9xxx-openwrt`（remake、imagebuilder.sh、documents/README.md §8.1/§10.11）
- 插件源码：`/tmp/luci-app-amlogic`（luci-app-amlogic 仓库，main @ `8fe2b60`）
- 设备脚本：`/usr/sbin/openwrt-install-*`、`/usr/sbin/openwrt-update-*`、`/usr/sbin/openwrt-tf`、`/usr/sbin/openwrt-kernel`、`/etc/config/amlogic`

---

## 7. remake 脚本：router 与 amlogic-s9xxx-openwrt 对比

> 对比对象：router `ophub/remake`（62,712B） vs 参考仓库 `remake`（61,847B）；逐字节 diff（SequenceMatcher）。

**总体流程完全一致**：两侧是同一份脚本，全文件仅一处差异。共享整套完整流程：参数解析 → 下载/检查 kernel → 解压并加载 u-boot 与内核 → `dd` 写镜像 → `parted` 分区（p1 boot + p2 rootfs 单根）→ 编内核模块 → 注入 luci-app-amlogic 脚本 → `refactor_rootfs()` 引导/rootfs 收尾 → 打包 `.img.gz`。

**唯一差异**（在 `refactor_rootfs()` 引导处理段，约 1026-1064 行）：

| 操作 | 参考仓库 | router（定制） |
|------|---------|---------------|
| 删除 | QuarkPi-CA2 / RK3588S 板子的 extlinux.conf 生成（U-Boot 只扫 `<dev>_extlinux/`） | 不编 QuarkPi 板，删去 |
| 新增 | —— | **LubanCat-1 板级 overlay 预置**（仅 `board==lubancat-1`）：把 `overlay-user/` 下的 `lubancat-msata.dtbo`（SSD→/dev/sda）与 `lubancat-fan-pwm.dtbo`（风扇 PWM）拷进 boot 分区 `overlay-user/`，并在 `armbianEnv.txt` 写/更新 `user_overlays=`，让 U-Boot 启动时逐个 fdt apply |

**本质差异一句话**：router 版**移除无关 QuarkPi 适配、加入 LubanCat-1 的 bootfs overlay 预置**；核心的**单根分区、内核封装、amlogic 脚本注入**逻辑与上游逐字一致。

> 说明：rootfs 侧的 LubanCat 定制不在 remake 里，由 `different-files/lubancat-1/rootfs/` 自动注入（remake 只处理 boot 侧 overlay）。

---

## 附：关键代码位置速查

| 机制 | 文件 | 行号 |
|------|------|------|
| 平台脚本分发 | `luci.amlogic` (ucode) | 106-116 |
| 固件/内核文件分类 | `luci.amlogic` | 595-617 |
| 在线更新下载匹配 | `amlogic_check_firmware.sh` | 125-269 |
| 单根打包 | `remake` | 801-826 |
| 首启扩分区标记 | `remake` | 1201 |
| 首启触发 openwrt-tf | `start_service.sh` | 161-165 |
| 建 p3/p4 + docker 迁移 | `openwrt-tf` | 84-163 |
| 双槽 update root 判断 | `openwrt-update-rockchip` | 438-455 |
