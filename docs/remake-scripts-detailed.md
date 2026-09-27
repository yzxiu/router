# remake 注入脚本源码详解（执行时间顺序 + 双区分布）

> 目标：把 LubanCat-1 (rockchip) 固件中 remake 封装**注入的每个脚本**逐一展开，说明其功能与**源码级执行步骤**，严格按**执行时间顺序**组织。
> 重点：**双根分区（双槽）机制**——建槽、判槽、写槽、切槽的完整闭环。
> 日期：2026-09-27 ・ 版本：基于 luci-app-amlogic main @ `8fe2b60`（3.1.321-r2）

---

## 0. 注入清单总览

remake 封装时注入 rootfs 的脚本分**两批来源**：

### A. 来自 luci-app-amlogic 仓库（remake 551-565：clone 该仓库 main 后复制）
- `root/usr/sbin/` → `common-files/usr/sbin/`（**9 个脚本**）：
  `fixcpufreq.pl`、`openwrt-backup`、`openwrt-ddbr`、`openwrt-install-amlogic`、`openwrt-kernel`、`openwrt-update-allwinner`、`openwrt-update-amlogic`、`openwrt-update-kvm`、`openwrt-update-rockchip`
- `root/usr/share/amlogic/` → `common-files/usr/share/amlogic/`（**3 个检查脚本**）：
  `amlogic_check_firmware.sh`、`amlogic_check_kernel.sh`、`amlogic_check_plugin.sh`

### B. 来自仓库自身 `ophub/make-openwrt/openwrt-files/common-files/`（remake 913 行整体拷进 rootfs）
- `usr/sbin/`：`openwrt-install-allwinner`、`openwrt-openvfd`、`openwrt-swap`、`openwrt-tf`
- `etc/custom_service/start_service.sh`（首启总控）
- `etc/config/amlogic`（晶晨宝盒配置模板）
- 辅助：`bin/getcpu`、`usr/bin/7z`、`usr/bin/cpustat`、`usr/sbin/kmod`、`sbin/firstboot`、`lib/firmware/*`、`etc/banner`、`etc/fstab`、`etc/config/fstab`、`etc/model_database.conf`、`etc/profile.d/30-sysinfo.sh`、`etc/modprobe.d/brcmfmac.conf`

> **不注入**（来自 luar 仓库但 remake 只 copy sbin+share/amlogic）：`usr/share/luci/`、`usr/share/rpcd/`、`etc/uci-defaults/`、`etc/init.d/amlogic` —— 这些 Web UI / RPC 由 feed 编译 luci-app-amlogic 时自带。**所以仅 remake 注入=有脚本无 UI；编入 luci-app-amlogic 才补上 UI。**

### 执行时间点分三阶段
```
打包(一次性)  →  首启(开机一次)  →  运行(用户触发)
remake 收尾       start_service      openwrt-update*/install*/kernel/backup/ddbr/check_*
                  └─ openwrt-tf
```

---

## 1. 打包阶段（remake 一次性收尾，1080-1210 行）

打包时对 rootfs 做静态注入/改写（不发生运行，属"固件预置"）：

| remake 行 | 动作 | 说明 |
|-----------|------|------|
| 1081-1082 | fstab `LABEL=ROOTFS`→`UUID=<随机>` | 根分区改按 UUID 挂载（为双槽切 UUID 打基础）|
| 1085-1092 | 填充 `etc/config/amlogic` 的 `amlogic_firmware_tag`/`amlogic_kernel_tags`/`amlogic_kernel_branch` | 晶晨宝盒在线源指向本固件源 |
| 1095-1098 | 默认 shell ash→bash |（若编入 bash）|
| 1101-1104 | turboacc 关 hw_flow/sw_flow | 防硬件加速搞乱网络 |
| **1107-1110** | rc.local 插 `bash /etc/custom_service/start_service.sh &` | **首启入口** |
| 1113 | cpufreq ondemand→schedutil | |
| 1121-1175 | 写一堆 `etc/modules.d/*` 驱动模块 | USB 网卡/WiFi/GPU/PWM/看门狗等 |
| 1178-1184 | modprobe.d blacklist + alias | |
| 1187-1194 | `etc/init.d/boot` 加 `ulimit -n 51200`、建 `/tmp/update` | 系统收尾 |
| **1201** | `echo yes > root/.todo_rootfs_resize` | **双槽扩容标记**（首启触发 openwrt-tf）|
| 1203-1210 | kmod 命令软链（depmod/insmod/...→kmod）| |

> **双槽关键**：此刻固件 = p1(boot) + p2(rootfs) **单根**（remake 801-826 行 parted 只建 p2）。「第二槽」要等首启 openwrt-tf 才建出来。

---

## 2. 首启阶段（rc.local → start_service.sh → openwrt-tf）

### 2.1 start_service.sh（首启总控，233 行）
remake 1109 行注入的 rc.local 调用，`&` 后台跑，日志 `/tmp/ophub_start_service.log`。按序执行：

| 行 | 动作 | 与双槽关系 |
|----|------|-----------|
| 30 | 写起始日志 | |
| 33-34 | `dmesg -n 1` 静音内核 console | |
| 36-51 | 探测 FDT/dtbfile（4 路：ophub-release / uEnv.txt / extlinux.conf / armbianEnv.txt）| |
| 53-92 | 由 `/boot` 分区推 `DISK_NAME` + **数据分区路径** `/mnt/<disk>p4` | 预置 p4 路径（首启后才有）|
| 94-101 | 禁 OpenSSL engine + 重启 uhttpd | |
| 103-107 | 启 `balethirq.pl`（网络 IRQ 均衡）| |
| 109-122 | 网卡开 `rx-udp-gro-forwarding` | |
| 124-152 | OpenVFD/RGB/风扇/...（按 FDT 存在性，LubanCat 多不触发）| |
| **160-165** | 若 `.todo_rootfs_resize == yes` → 后台 `openwrt-tf` | **双槽建槽** |
| 167-192 | 特定板子网络优化（nsy-g16 等，非 LubanCat）| |
| 194-228 | 等 p4 就绪 → 有 `.swap/swapfile` 则 losetup+swapon 启用 swap | 依赖 p4 |

### 2.2 openwrt-tf（首启建双槽，169 行）★双槽核心
`do_checkdisk` + `create_new_partition` 两段。

**do_checkdisk（39-82）**
1. `df /boot` → root 分区名；DUMP 磁盘 `DISK_NAME` 与前缀：
   - `mmcblk?p*` → `PT_PRE=mmcblkNp`、`LB_PRE=MMC_`
   - `[hsv]d?*` → `USB_`；`nvme?n?p*` → `NVME_`
2. 若**已存在 p4** → `rm -f .todo_rootfs_resize` 并 exit（防重复建）
3. 否则 `sync && sleep 3` 继续建

**create_new_partition（85-163）**
```
1. UUID: ROOTFS_UUID + SHARED_UUID（/proc/sys/kernel/random/uuid，备选 uuidgen）
2. parted 修复磁盘几何（printf 'f'|parted print）
3. 算 p3 起点: END_P2(fdisk) → MiB
4. 建分区(108-109):
     parted mkpart primary btrfs <p3_start>MiB  <p3_start+1023>MiB   # p3=1GB
     parted mkpart primary btrfs <p3_start+1024>MiB 100%            # p4=剩余
5. 格式化(115/121):
     p3 → mkfs.btrfs -L MMC_ROOTFS2   # 双槽备用 rootfs
     p4 → mkfs.btrfs -L MMC_SHARED    # 共享数据分区
   (均 -m single；挂到 /mnt/mmcblk0p{3,4})
6. docker 迁移(124-158, 仅当有 /etc/init.d/dockerd):
     停 dockerd → rm -rf /opt/docker → ln -sf /mnt/mmcblk0p4/docker/ /opt/docker
     uci set dockerd.data_root=/mnt/mmcblk0p4/docker/
     写 /etc/docker/daemon.json(bip/data-root/镜像源)
     启 dockerd
7. rm -f .todo_rootfs_resize(完成标记)
```

> **结果：首启后四分区** p1(boot) + p2(rootfs 当前) + **p3(ROOTFS2 空闲待写)** + **p4(SHARED 数据/docker)**。
> **依赖**：parted/fdisk/uuidgen/losetup（缺 parted → 建分区失败 → 保持单槽；这也是设备当前旧固件的实况）。

---

## 3. 运行阶段（晶晨宝盒 UI / 命令行触发）

### 3.0 平台分发：luci.amlogic `platform_scripts()`（rpcd/ucode 107-116）
```
platform   install                  update                     kernel
rockchip   ''(空)                   openwrt-update-rockchip     openwrt-kernel
allwinner  openwrt-install-allwinner openwrt-update-allwinner    openwrt-kernel
qemu       ''(空)                   openwrt-update-kvm          openwrt-kernel
amlogic    openwrt-install-amlogic  openwrt-update-amlogic      openwrt-kernel
```
**LubanCat=rockchip → 更新走 openwrt-update-rockchip + openwrt-kernel**。install 为空 =「安装到 eMMC」按钮无效（rockchip 直接整卡刷 .img）。

另 `root_on_internal_storage()`（92-104）：仅当 root 在 eMMC(device type=MMC) 才隐藏 install 菜单；TF/SD 仍显示。

### 3.1 openwrt-update-rockchip（固件 rootfs 更新，924 行）★双槽核心

**A. 准备与认设备（1-396）**
- 认设备：`cat /proc/device-tree/model` → case 推 `SOC` + `MYDTB_FDTFILE`（dtb）
- 解压固件（根据后缀）：
  - `.img.gz` → `gzip -d`；`.img.xz` → `xz -d`；`.7z` → `bsdtar`/`7z`；`.zip` → `unzip`
  - 得 `.img`（IMG_NAME）
- 认存储：`get_root_partition_name()`（查 `/`、`/overlay`、`/rom`）

**B. 双槽判定（408-460）**
```
BOOT_PART_MSG = lsblk 找挂 /boot 的磁盘分区   → BOOT_UUID
ROOT_PART_MSG = get_root_partition_msg()      → ROOT_NAME/UUID

case $ROOT_NAME in
  <disk>p2)  NEW_ROOT_NAME=<disk>p3;  NEW_ROOT_LABEL=<LB_PRE>ROOTFS2 ;;
  <disk>p3)  NEW_ROOT_NAME=<disk>p2;  NEW_ROOT_LABEL=<LB_PRE>ROOTFS1 ;;
  *)         error "root partition location is invalid" ;;
esac
再查 NEW_ROOT 分区存在否(LB=453):
  缺 → error "The new root partition is not exists"   ← 单槽时的失败点
LB_PRE 由存储类型定(341-356): mmcblk→EMMC_, nvme→NVME_, sd→USB_
```
> 注：`LB_PRE` 只在后面 `mkfs` 打标签用；**定位对侧槽靠分区名 p2/p3 而非 label**，故 openwrt-tf 建槽的 `MMC_` 前缀与这里的 `EMMC_` 不一致不影响功能（更新时会重新 mkfs 打成 EMMC_）。

**C. 挂载更新源（463-546）**
```
losetup -f -P <img>            → LOOP_DEV（loop 设备自动分 p1,p2）
fix_loopdev(5.19+ 补节点)
挂 loop p1 → $P1=boot  (ext4 ro)
挂 loop p2 → $P2=root  (btrfs ro, compress=zstd:6)
（可选读取当前 docker data-root 配置）
```

**D. 写对侧新槽（601-660）** ★
```
1. umount 目标新根挂载点
2. NEW_ROOT_UUID=$(uuidgen)
3. mkfs.btrfs -f -U <newuuid> -L <label> -m single <NEW_ROOT_PATH>   # 全新格式化
4. mount 到 NEW_ROOT_MP
5. 清空该槽旧内容(除 lost+found)
6. 建 btrfs 子卷:  btrfs subvolume create etc
   建目录 .snapshots .reserved bin boot dev lib opt mnt overlay proc rom root run sbin sys tmp usr www
   ln -sf lib/ lib64 ; ln -sf tmp/ var
7. 从 $P2(更新源 rootfs) tar 复制: root etc bin sbin lib opt usr www
```

**E. 配置收尾（670-800）**
```
- 写 ./etc/fstab:
    UUID=<NEW_ROOT_UUID> / btrfs compress=zstd:6 0 1
    UUID=<BOOT_UUID>     /boot ext4 defaults 0 2
- 写 ./etc/config/fstab (全局 + /rom btrfs + /boot ext4 条目)
- 首次快照: btrfs subvolume snapshot -r etc .snapshots/etc-000
- 软链共享分区: ln -sf /mnt/<disk>p4/docker/ opt/docker
- (可选) 备份并还原用户配置 openwrt-backup
  - tar czf .reserved/openwrt_config.tar.gz <备份列表>
  - 还原 fstab/config/luci/rpcd
```

**F. 引导切换（852-924）★关键：下次从新槽启动**
```
1. 备份 armbianEnv.txt → /tmp；备份当前 dtb → /tmp
2. 清空 /boot，从 $P1(更新源 boot) tar 复制新 boot 文件(Image/vmlinuz/uInitrd/dtb/...)
3. 重写 armbianEnv.txt:
     fdtfile=rockchip/<MYDTB_FDTFILE>
     rootdev=UUID=<NEW_ROOT_UUID>        ← 指向新槽
     rootfstype=btrfs
     rootflags=compress=zstd:6
4. 若 extlinux/extlinux.conf 存在 → sed 替换其 UUID 为新槽
5. 新 dtb 缺失用旧 dtb 兜底
6. umount + losetup -D + 清理临时
7. echo "Successfully updated..." → sleep 3 → reboot
```

**双槽更新闭环总结**：当前 p2 → 写 p3 并引导到 p3；下次 root 在 p3 → 写回 p2。**滚动更新，对侧槽永远保留上一版 = 内置回滚点**；docker 数据在 p4 SHARED 不随切槽丢。

### 3.2 openwrt-kernel（内核更新，516 行）
`check_kernel` → `update_kernel` → `update_uboot`。**不走双槽，直接换 /boot 引导文件**。

`update_kernel()`（242-345）三步：
```
(1) /boot 5 件:  备份当前 config/System.map/initrd.img/uInitrd/vmlinuz(带内核版本后缀)+Image/dtb*
                 删除 → 解新 boot-<kernel>.tar.gz 到 /boot
                 vfat: cp uInitrd-<k>→uInitrd, vmlinuz-<k>→vmlinuz
                 非 vfat: ln -sf uInitrd-<k> uInitrd, vmlinuz-<k>→<MYBOOT_VMLINUZ>
(2) /boot/dtb/<platform>: 解 dtb-<platform>-<kernel>.tar.gz → dtb 目录
(3) /lib/modules: 删旧 → 解 modules-<kernel>.tar.gz → 软链 *.ko 平铺
失败任一 → restore_kernel 回滚
```

### 3.3 openwrt-install-amlogic（eMMC 双槽安装，721 行，仅 amlogic，与 rockchip 无关但体现双槽模型）
```
备份旧 u-boot → umount 其它 → dd 清 eMMC 分区表
写 u-boot(mainline/android)
mkfs(482-499):
   p1 → mkfs.fat -n EMMC_BOOT -F 32          # boot
   p2 → mkfs.btrfs -L EMMC_ROOTFS1           # 双槽1
   p3 → mkfs.btrfs -L EMMC_ROOTFS2           # 双槽2
挂 p1 复制 boot → 挂 p2 复制当前 rootfs(建子卷/ln)
   → 重写 fstab 指向 EMMC_ROOTFS1
p4 → mkfs ishare file system(按 SHARED_FSTYPE: btrfs/f2fs/xfs/ext4) -L EMMC_SHARED
```
> 这是「双槽模型」在 eMMC 上的另一处建立（EMMC_ROOTFS1/2）。**LubanCat(rockchip) 不触发**（install 为空），但理解双槽很有价值。

### 3.4 其它 update/install 脚本（平台专属，简述）
| 脚本 | 行 | 功能 |
|------|----|------|
| `openwrt-update-amlogic` | 859 | amlogic eMMC 固件更新（类似 rockchip 但写 EMMC_ROOTFS1/2）|
| `openwrt-update-allwinner` | 662 | allwinner 更新 |
| `openwrt-update-kvm` | 674 | QEMU/KVM 虚拟机更新（work 目录挂载）|
| `openwrt-install-allwinner` | 375 | allwinner 装 eMMC |

### 3.5 备份/恢复
| 脚本 | 行 | 功能 |
|------|----|------|
| `openwrt-backup` | 598 | 备份/还原 `/etc` 配置：`BACKUP_DIR=/.reserved`、`BACKUP_NAME=openwrt_config.tar.gz`；列表可自定 `/etc/amlogic_backup_list.conf`；`-p` 打印列表、`-g` 修复挂载点 |
| `openwrt-ddbr` | 155 | eMMC 整盘镜像备份/恢复（ddbr 风格 dd 到 /mnt）|

### 3.6 在线检查/下载（usr/share/amlogic/*.sh）
共通：读 `/etc/flippy-openwrt-release` 得 `PLATFORM/BOARD` → 下载到 `/mnt/<disk>p4/.luci-app-amlogic/` → 并发互斥（RUNNING_LOG）→ 完成后交给对应 update 脚本。

**amlogic_check_firmware.sh（293 行）**：
```
01 查本地版本: uname -r → main_line_version(6.18)
   比/记 amlogic_kernel_branch (uci)
   读 repo=amlogic_firmware_repo(默认 ophub/amlogic-s9xxx-openwrt)
       tag关键词=amlogic_firmware_tag(默认 _openwrt_main_)
       suffix=amlogic_firmware_suffix(默认 .img.gz)
02 check_updated():
   抓前5页 release tags → 找含 tag关键词 的 → 取 expanded_assets HTML
   文件名正则: .*_${BOARD}_.*k${main_line_version}\.[0-9]+.*${suffix}
   得 latest_url + updated_at + sha256
   版本指纹 op_release_code = "${updated_at}.${main_line_version}" 比对防重复
03 download_firmware():
   下载 → openwrt_${BOARD}_k${main_line_version}_github${suffix}
   sha256 校验 → 提示 "Update" 交给 openwrt-update-rockchip
```

---

## 4. 一张图：双槽完整生命周期

```
[打包]  p1 boot + p2 rootfs(单根)        写 .todo_rootfs_resize=yes
   │  ┌───────────────────────────────────┘
[首启]  rc.local ─► start_service.sh ─► openwrt-tf
   │                                     │ parted+mkfs
   │                                     ▼
   │                 p1 + p2 ROOTFS1(用) + p3 ROOTFS2(空) + p4 SHARED(docker/数据)
   │                                     │ rm .todo_rootfs_resize
   ▼                                     ▼
[更新1]  openwrt-update-rockchip:  root=p2 → 写 p3(全新格式化+复制+引导rootdev=p3) → reboot
   │                                   root=p3 启动, p2 留旧版=回滚点
[更新2]  openwrt-update-rockchip:  root=p3 → 写 p2(...引导rootdev=p2) → reboot
   ▼                                   root=p2, p3 留上一版
  ……滚动往返, 永远有一槽为上一版可回退
```

---

## 5. 关键代码位置速查

| 机制 | 文件 | 行号 |
|------|------|------|
| 注入(luar sbin+share) | `remake` | 551-565 |
| 注入(common-files 整体) | `remake` | 913 |
| 首启入口 rc.local 注入 | `remake` | 1107-1110 |
| 双槽触发标记 | `remake` | 1201 |
| 首启建双槽(建分区/格式化/docker) | `openwrt-tf`(common) | 85-163 |
| start_service 调 openwrt-tf | `start_service.sh` | 160-165 |
| 平台分发(rockchip→update-rockchip) | `luci.amlogic`(rpcd) | 107-116 |
| root 是否在 eMMC | `luci.amlogic`(rpcd) | 90-104 |
| 更新双槽判定(p2↔p3) | `openwrt-update-rockchip` | 408-460 |
| 挂载更新源(losetup) | `openwrt-update-rockchip` | 463-546 |
| 写对侧新槽(格式化+复制+etc子卷) | `openwrt-update-rockchip` | 601-668 |
| 引导切换(armbianEnv rootdev) | `openwrt-update-rockchip` | 852-924 |
| 内核更新(换 /boot) | `openwrt-kernel` | 242-345 |
| eMMC 双槽建立(amlogic install) | `openwrt-install-amlogic` | 482-499 |
| 在线固件检查/下载 | `amlogic_check_firmware.sh` | 136-293 |
| 共享分区文件系统类型 | `etc/config/amlogic` | 13（amlogic_shared_fstype）|
