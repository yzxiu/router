# 双槽 OTA：升级时「配置」与「软件」是如何保留的

> 本文聚焦一个容易忽略的细节：用晶晨宝盒对 LubanCat-1 做**双槽 OTA 升级**时，用户改过的**配置文件**、以及**已安装的软件**到底怎么处理——哪些保留、哪些会被新固件覆盖或丢掉。
> 源码依据：`luci-app-amlogic` 的 `/usr/sbin/openwrt-update-rockchip`（924 行，rockchip 平台 OTA 主脚本）与 `/usr/sbin/openwrt-backup`（598 行）。

---

## 1. 先厘清「升级时的三个数据源」

一次双槽 OTA（`openwrt-update-rockchip`）涉及三方，搞清楚谁是"源"谁是"目的地"，后面的机制才不会搞混：

| 角色 | 是什么 | 脚本里的变量 | 状态 |
|------|--------|-------------|------|
| **新固件镜像** | 用户下载/上传的 `.img.gz`（解压成 `.img`） | `IMG_NAME` | losetup 挂成 loop 设备 |
| **新固件的 boot 分区** | 新镜像里的 `p1`（内含内核/dtb） | `P1`（loop p1，只读挂载） | `mount -o ro` |
| **新固件的 rootfs 分区** | 新镜像里的 `p2`（新系统本体） | `P2`（loop p2，只读挂载） | `mount -o ro` |
| **设备的当前运行槽** | 现在正跑的系统（emmc p2 或 p3） | `ROOT_*`（当前根） | 可写 |
| **设备的对侧空槽** | 要被写入的备用槽（emmc p2↔p3 轮换） | `NEW_ROOT_*` | 先 mkfs 清空，再可写 |

**核心区分（最容易理解错的一点）：**
- `P2` = **新固件镜像里的 rootfs**（这一版固件自带的完整系统）
- `NEW_ROOT_MP` = **设备上要被写入的对侧槽**（升级后的新系统落点）

⚠️ `P2` **不是**"当前正在运行的槽"。初次看代码极易把 `P2` 当成旧系统，会导致整条数据流理解反。

---

## 2. 整体数据流（时间顺序）

```
【准备】
  losetup -f -P .img             # 462: 挂载新固件镜像为 loop
  P1=/...boot ; P2=/...root      # 521-522
  mount loop p1 -> P1 (ro)       # 525: 新固件的 boot
  mount loop p2 -> P2 (ro)       # 536: 新固件的 rootfs
  判断当前 root 槽 p2/p3  →  定位对侧 NEW_ROOT (438-460)

【写入】
  mkfs.btrfs 对侧槽 NEW_ROOT_MP  (601-630)   # 清空备用槽
  cp  从 P2(新固件rootfs) 整体复制系统树 → NEW_ROOT_MP   (635-668)
  修改 fstab/系统级配置 → NEW_ROOT_MP                (681-723)
  配置迁移: 从旧系统打包 → 解到 NEW_ROOT_MP           (745-768)
  引导切换: 改 armbianEnv.txt rootdev → 新槽          (852-924)
  reboot
```

---

## 3. 关键步骤 1：整树复制 → 「新固件自带系统」刷进新槽（661-668）

```bash
COPY_SRC="root etc bin sbin lib opt usr www"
for src in ${COPY_SRC}; do
    (cd ${P2} && tar cf - ${src}) | tar xf -
done
```

- 把 **新固件镜像 rootfs（P2）** 里的整个系统树（root/etc/bin/sbin/lib/opt/usr/www）复制到设备的**对侧槽**。
- 这一步的本质是**"把这一版固件装上"**——新固件自带哪些软件，新槽就有哪些软件。
- **与旧系统的软件无关**：它不是"复制旧系统"，而是"装载新系统"。

---

## 4. 关键步骤 2：配置迁移 → 旧系统的配置打包还原到新槽（745-768）

```bash
BACKUP_LIST=$(${P2}/usr/sbin/openwrt-backup -p)      # 745: 用新固件里的 backup 列出清单
if [ ${BR_FLAG} -eq 1 ]; then                        # 是否还原配置(可 no-restore)
    (
        cd /                                          # 748-751: 切到"当前运行的旧系统根"
        eval tar czf ${NEW_ROOT_MP}/.reserved/openwrt_config.tar.gz "${BACKUP_LIST}"
    )
    tar xzf ${NEW_ROOT_MP}/.reserved/openwrt_config.tar.gz   # 752: 解到新槽根(cwd 已是新槽)
    # 强制还原关键配置(从升级时生成的 etc 只读快照)
    cp -f .snapshots/etc-000/fstab          ./etc/fstab           # 758
    cp -f .snapshots/etc-000/config/fstab   ./etc/config/fstab    # 759
    cp -f .snapshots/etc-000/config/luci    ./etc/config/luci     # 761
    cp -f .snapshots/etc-000/config/rpcd    ./etc/config/rpcd     # 763
fi
```

**配置迁移的"方向"**：
- `cd /` 进**旧系统** → 按 `BACKUP_LIST` 打包 → 存到 **新槽** 的 `.reserved/openwrt_config.tar.gz`
- 再解包覆盖**新槽**根 → 用户的配置写进了新系统
- 之后用 `.snapshots/etc-000`（升级开场时对新槽 etc 子卷拍的只读快照）**强制还原** fstab / luci / rpcd —— 保证新槽那三个关键配置不受打包/复制污染

**BR_FLAG（是否还原配置）**：可选 `restore`（默认 y）/`no-restore`（n）。用户不想保留旧配置时用 no-restore。

---

## 5. `BACKUP_LIST` 到底保住了哪些"配置"（openwrt-backup 21-85 行）

若没有自定义 `/etc/amlogic_backup_list.conf`，默认清单（默认值，60+ 项）涵盖：

| 类别 | 具体项 | 意义 |
|------|--------|------|
| **整个 uci 配置目录** | `./etc/config/` | ⭐ 用户改的网络/无线/防火墙/luci 全在这里 |
| **密码/密钥** | `./etc/shadow`、`./etc/ssh/*key*`、`./etc/ssl/private/`、`./root/.ssh/`、`urandom.seed` | 用户登录密码、SSH 密钥 |
| **docker** | `./etc/docker/daemon.json`、`./etc/docker/key.json` | docker 配置（数据本体在 p4，不在此） |
| **安全/转发** | `./etc/firewall.user`、`./etc/hosts`、`./etc/dnsmasq.conf`、`./etc/dnsmasq.d/`、`./etc/ipset/` | 自定义防火墙/DNS |
| **计划任务** | `./etc/crontabs/` | crontab 任务 |
| **各软件配置目录** | `openclash/` `smartdns/` `mosdns/` `tailscale/` `transmission/` `qBittorrent/` `openvpn/` `ocserv/` `dae/` `daed/` `v2raya/` `verysync/` 等 | 自装软件的配置文件 |
| **系统杂项** | `./etc/rc.local`、`./etc/environment`、`./etc/exports`、`./etc/samba/smbpasswd`、`./etc/profile` | 自启脚本、共享等 |

> 可自定义：在 `/etc/amlogic_backup_list.conf` 写行，每条一个路径，即完全由你决定备份清单（脚本 16-19 行优先读它）。

---

## 6. 升级后「配置」与「软件」的最终去向（结论表）

| 项 | 升级到新槽后 | 机制 |
|----|------|------|
| **新固件自带的软件** | ✅ 在新槽 | 第 3 节整树复制（来自 .img 的 P2） |
| **用户改过的配置文件**（uci/网络/防火墙等） | ✅ 保留到新槽 | 第 4 节 BACKUP_LIST 打包还原 |
| **用户密码 / SSH 密钥** | ✅ 保留 | BACKUP_LIST 含 shadow/ssh 密钥 |
| **docker 数据** | ✅ 保留 | 数据在 p4 SHARED 分区，不在 rootfs 槽 |
| **用户在旧系统额外 opkg/apk 装的软件【包】** | ❌ **不带过去** | 新槽装的是新固件自带系统，无包迁移逻辑 |

**一句话**：**配置随升级保留（BACKUP_LIST + 快照还原），软件随固件走（新槽=新固件自带系统），你在旧槽额外装的软件包不会自动迁移到新槽。**

（这是 OpenWrt 固件升级的常规预期：升级后 tools 是新的，但你的设置还在。）

---

## 7. 相关但易混淆的机制

### 7.1 双槽轮换 + 配置为何要"还原"两次（etc 快照）
- 升级对新槽做两次 etc **只读快照**：`etc-000`（726-727）在配置还原前，`etc-001`（844-845）在还原后。
- 这就是 `openwrt-backup` 用 `.snapshots/etc-000` 强还 fstab/luci/rpcd 的原因——它是升级前新槽 etc 的干净基线，防止打包/复制过程误改这三个关键文件导致新系统起不来。
- 快照机制 = OpenWrt 的 btrfs 快照就地升级思路的移植。

### 7.2 "已安装软件"的两个层面（容易混）
- **文件层面**：新固件自带的软件文件都在新槽（第 3 节复制）。你在旧槽**额外装的**软件的【文件】不在新槽。
- **包管理层面**：`opkg`/`apk` 的已装包数据库（`/etc/opkg/status` 或 `/lib/apk/db`）在旧槽，**不迁移**。即使某个自装软件的配置被 BACKUP_LIST 还原了，新槽的包管理器也不认为它"已安装"。
- 影响：升级后如果还想用自装软件，需要在新槽重新 opkg/apk 安装；但它的**配置**若能还原，装上后设置还在。

### 7.3 内核更新（openwrt-kernel）不走双槽
- 只更新内核三件套（boot/dtb/modules）到 `/boot` + `/lib/modules`，**不动 rootfs 槽**，因此**不影响配置和已装软件**（它们本来就在当前槽）。
- 这也呼应：**换内核=轻量；换 rootfs 固件=整系统替身（配置带走，多余软件丢）**。

---

## 8. 实际使用建议

1. **升级前**：确认 `/etc/amlogic_backup_list.conf` 是否覆盖了你关心的路径；如需保留额外软件的配置，可往该文件加行。
2. **升级后**：默认 `restore`（保留配置）。若这次固件变化大、想要干净默认，用 `no-restore`。
3. **自装软件**：升级后记得在新槽 reinstall（配置一般已还原）。
4. **docker 数据**：在 p4，天然跨升级存活，不用管。
5. 想验证：`openwrt-backup -p` 可打印当前生效的 BACKUP_LIST。

---

## 附：关键行号速查（openwrt-update-rockchip）

| 行号 | 作用 |
|------|------|
| 380-398 | 解压新固件（.gz/.xz/.7z/.zip → .img） |
| 462-471 | `losetup -f -P` 挂载新固件镜像 |
| 519-536 | `P1=P2=挂载点`，`mount loop p1→P1`、`loop p2→P2`（只读） |
| 433-460 | 判当前 root 槽 → 定位对侧 NEW_ROOT |
| 601-630 | `mkfs.btrfs` 清空对侧槽 |
| 635-668 | **从 P2(新固件rootfs) 整体复制系统树到新槽** |
| 681-703 | 重写 fstab / config/fstab（新槽 UUID） |
| 726-727 | 新槽 etc 拍只读快照 `.snapshots/etc-000` |
| 745 | `BACKUP_LIST=$(...openwrt-backup -p)` |
| 746-768 | **配置迁移：旧系统打包 → 解到新槽 + 快照强还 fstab/luci/rpcd** |
| 770-842 | 各种系统级修补（inittab/shadow/rc.local/dockerd 自启） |
| 844-845 | 新槽 etc 拍第二快照 `.snapshots/etc-001` |
| 852-924 | 引导切换：改 armbianEnv.txt `rootdev=UUID=<新槽>` → reboot |

**BACKUP_LIST 来源脚本**：`openwrt-backup` 15-19（自定义 conf）/ 21-85（默认清单）。
