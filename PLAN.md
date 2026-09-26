# router 整合计划（唯一准绳）

多机型 OpenWrt 固件统一打包仓库的完整计划。**后续所有工作以本计划为准**。

## 目标

一个 `router` 仓库，统一打包：
- **GL-MT3000** / **Cudy TR3000** / **x86-64**：直接 ImmortalWrt 源码编译完整可刷固件
- **LubanCat-1**：armsr 编 rootfs + ophub 封装成可刷 `.img`（阶段3）

仓库**不包含 ImmortalWrt 源码**，CI 运行时拉取上游官方源码与 feeds。

## 架构原则（已确定，不更改）

1. **只用 router 仓库**：`immortalwrt_yzx` / `packages_yzx` 是同一套旧体系，**已弃用，仅作参考**，不去维护/驱动。
2. **仓库内容**：GitHub Actions 流水线 + 各机型 config + 编译期临时调整（脚本/文件）。
3. **上游**：官方 ImmortalWrt + 官方 feeds，运行时拉取；上游版本参数化（当前默认 tag `v25.12.2`）。
4. **定制方式**：官方 feeds 基线 + router 里脚本在**编译期做临时调整**（不 fork/不依赖 packages_yzx）。
5. **先默认后定制**：先用官方纯净默认 config 打包成功，再做定制版本。
6. **每机型独立 config**：mt3000 / tr3000 / x86-64 分开，不共用。
7. **产物是完整固件包**（sysupgrade.bin / combined img），不只是 rootfs —— 流水线命名按此语义（`build-firmware`）。

## 仓库结构（目标形态）

```
router/
├── .github/workflows/
│   └── build-firmware.yml      # 主流水线: 源码编译完整固件 (机型参数化, matrix 五平台并发)
├── config/
│   ├── platforms.conf          # 【平台层】声明编译哪些设备 + target/runner (唯一来源)
│   ├── packages.conf           # 【通用软件层】所有平台都装的包 (CONFIG_PACKAGE_*)
│   ├── platform/
│   │   ├── mt3000.conf         # 【平台专用软件层】该平台附加/+ 排除/- 的包
│   │   ├── tr3000.conf
│   │   ├── x86-64.conf
│   │   ├── nanopi-r3s.conf
│   │   └── lubancat.conf       # (后续晶晨宝盒 luci-app-amlogic 等放这里)
│   └── README.md               # config/ 分层说明
├── ophub/                       # (阶段3) LubanCat 封装素材: remake + dts/{msata,fan} + rootfs 注入
│   └── dts/{msata,fan}/.dts     #   板级 overlay 源码, CI 现场编译成 .dtbo
├── feeds.conf                   # 官方 feeds (锁定 v25.12.2 pin)
├── scripts/
│   ├── generate-config.sh       # 分层合成 config: 平台层+通用软件+平台专用 (已重构)
│   └── ...                      # 其他编译期调整脚本
├── README.md
└── PLAN.md                      # 本文件
```

## 阶段 1 — 默认版跑通 mt3000（✅ 完成）

目标：mt3000 官方纯净默认版出完整 `squashfs-sysupgrade.bin`。

- [x] 建 router 骨架：workflow + feeds.conf + generate-config.sh + README（commit `3e27a1d`）
- [x] push 触发 CI（run `36104139589`）
- [x] 本地独立树验证 router 脚本可跑（`/workspace/openwrt/router-build`，官方 v25.12.2）
- [x] 本地编译出 `sysupgrade.bin`（`immortalwrt-mediatek-filogic-glinet_gl-mt3000-squashfs-sysupgrade.bin`，13.2MB，sha256 `0d11e9ae...`）
- [x] 验证产物：211 包、基础组件齐全、纯官方（无定制包）
- [x] 阶段1 收尾：确认默认版可刷

## 阶段 2 — 多机型（✅ 完成；⏸️ 包定制暂且缓）

- [x] tr3000 / x86-64 各自 config 加入（独立文件）✅ commit `49b7f1b`
- [x] workflow 用 matrix **三平台并发**编译 ✅ commit `d4e19eb`
- [x] 修复 Create Release 权限（`permissions: contents: write`）✅ commit `dd59a0d`
- [x] **验证三平台各出完整包**：CI run `36122447198` success，Release `firmware-mt3000-5`/`tr3000-5`/`x86-64-5` 均创建
  - mt3000 → `squashfs-sysupgrade.bin`
  - tr3000 → `preloader.bin` + ATF bl2（ubootmod 方案）
  - x86-64 → `squashfs-combined-efi.img.gz` 等完整镜像
- [ ] ⏸️ 建立"编译期临时调整"机制（`patch-feeds.sh` 等）——**暂缓，用户要求先缓一缓**
  - 升级 sing-box / nebula 到新版（官方 feeds 1.12.25 / 1.10.3 → 1.14.2 / 1.11.2）
  - 加定制包（WireGuard 三件套、docker 等，按需）
- [ ] ⏸️ 定制包在官方基线 + 编译期 patch 下验证——**暂缓**

## 阶段 3 — LubanCat-1（当前）

目标：LubanCat-1 完整可刷固件（armsr 编 rootfs + ophub remake 封装成 `.img`）。
**先把主线逻辑跑通**：armsr/armv8 编 rootfs → remake 封装可刷 .img，同一流水线内闭环。

- [x] **armsr/armv8 加入 build-firmware matrix**：`generate-config.sh` 加 `lubancat` 分支（`armsr/armv8`），workflow matrix 加 `lubancat`，Collect 步骤加 `*rootfs.tar.gz` ✅ commit `27dd6ad` / CI run `36156780374` 验证中
- [x] 本地验证：`generate-config.sh lubancat` → `make defconfig` 通过（`CONFIG_TARGET_armsr_armv8_DEVICE_generic=y`，rootfs 含 `.tar.gz`）
- [ ] **封装成可刷 `.img`**（方案已确认，见下"LubanCat 封装方案"）——同 build-firmware 的 lubancat job 内，rootfs 编译完后接着调 remake 封装
- [ ] 验证可刷 `.img` 产出

### 阶段3 分步拆解（执行清单）

**A. rootfs 产物确认（等 CI）**
- [ ] A1 等 run `36156780374` 的 lubancat job 出 `*rootfs.tar.gz`，确认 armsr 编译闭环
- [ ] A2 确认产物在 Release/artifact 的形态与命名

**B. 搬文件进 router（✅ 完成，commit `6c0faa4`）**
- [x] B1 建 `router/ophub/` 目录结构（`ophub/`：remake + make-openwrt + msata/fan + u-boot 骨架）
- [x] B2 从 `amlogic-s9xxx-openwrt` 复制 `remake` 脚本（`bash -n` 语法通过，无参启动正常）
- [x] B3 复制 `make-openwrt/` 的 LubanCat 必需定制（`different-files/lubancat-1/`、`platform-files/rockchip/`、`common-files/`）
- [x] B4 复制 `msata/lubancat-msata.dtbo` + `fan/lubancat-fan-pwm.dtbo`
- [x] B5 本地试跑 `./remake` 语法/help（无参启动验证 ok；补建 `u-boot/rockchip/` 骨架让 download_depends 正常触发下载）

**C. 封装编排（✅ 完成，commit 待填）**
- [x] C1 build-firmware.yml 的 lubancat job 加封装 step：rootfs 编完后 `cd ophub && sudo ./remake -b lubancat-1 -k 6.18.y`（含依赖安装）
- [x] C2 改为**统一 Release**（参考 immortalwrt_yzx）：build job 只 `upload-artifact`，新增独立 `release` job（`needs: build`）下载所有 `firmware-*` → 合并 → sha256sum → 单个 `ImmortalWrt-<tag>-<时间>` release 汇总 mt3000/tr3000/x86-64/lubancat 全部固件
- [x] C2-归档 按 yzx 风格分三类 artifact：`firmware-<device>`（case 精选每平台关键固件）+ `openwrt-bin-<device>-<run_id>`（完整 bin 归档）+ `openwrt-logs-<device>-<run_id>`（失败日志）——不再 find 全量杂收
- [x] C3 验证封装 step 与现有编译 step 衔接：rootfs 从 `openwrt/bin/targets/armsr/*rootfs.tar.gz` → `ophub/openwrt-armsr/`（remake `openwrt_path`），YAML 校验通过
- [x] C-环境修复：**remake 需 coreutils≥9.1（`cp --update=none`），ubuntu-22.04(8.32) 失败** → LubanCat job 用 `include` 单独指定 `ubuntu-24.04`（参考 amlogic-s9xxx-openwrt）；其他编译平台维持 `ubuntu-22.04`（参考 immortalwrt_yzx）
- [x] C-Collect修复：**remake 产物被 gzip 压缩成 `.img.gz`**（remake 1315-1325 行 pigz/gzip 压缩），原 Collect 匹配 `*.img` 失败 → 改 `*.img*` 兼容

**D. 联调验证**
- [x] D1 push 触发 CI，lubancat job **完整跑通**（rootfs→.img）：run `36181279612` build-lubancat success，产出 `openwrt_rockchip_lubancat-1_k6.18.53_2026.09.25.img.gz`（176MB，内核 6.18.53，sha `f8e43dc0...`）
- [x] D2 验证产物可刷：LubanCat `.img` 已用 btrfs restore 解包验证（GPT 两分区 boot 383MiB + btrfs rootfs 1279MiB 结构完整，OpenWrt 目录/kernel 6.18.53/overlay 齐全）；路由器固件（mt3000 .bin/tr3000 .itb）为官方产物结构
- [x] D3 统一 release 汇总：run `36181279612` 出 `ImmortalWrt-25.12.2-20260925-2221`（Latest）合并 mt3000/x86-64/lubancat 三平台 + checksums
  - ⚠️ 发现 **tr3000 漏发**：release job 的 Gather 用 find 按后缀过滤（`.bin/.img.gz/.img/rootfs.tar.gz`），漏了 tr3000 的 `.itb` 后缀 → 修复为加 `-o -name '*.itb'`（commit `49a7826`，run `36196504093` 验证）✅ 四平台齐全
- [x] D4 最终确认：run `36196504093` 全 success，release `ImmortalWrt-25.12.2-20260926-0037`（Latest）四平台固件完整（tr3000 .itb 14.2MB / mt3000 .bin 12.6MB / x86-64 img.gz / lubancat .img.gz 175MB）

**E. 收尾**
- [x] E2 阶段3主线逻辑跑通：官方 armsr rootfs → ophub remake → 可刷 .img.gz，统一 release 四平台汇总 ✅
- [x] E1 更新 PLAN.md 勾选完成项示意（本条即本次收尾更新）
- [x] E4 清理：旧 run / 监控进程已停，临时解包目录已清理
- [ ] E3 包定制（暂缓）：晶晨宝盒 Web 界面缺失（luci-app-amlogic 未编入官方纯净 rootfs）、WireGuard/docker/排除项等定制在后续 stage

> 依赖：A 等 CI 独立；B 本地可做不依赖 CI；C 依赖 B；D 需 A+B+C 就绪。推进顺序 B → C，A 并行，最后 D 联调。

## LubanCat 封装方案（阶段3，已确认）

- **位置**：封装在 **build-firmware 的 lubancat job 内**做完（不是独立 build-lubancat.yml）——rootfs 编译完后，同一 job 里接着调 remake 封装成 `.img`。
- **不 uses: 引用**：不通过 `uses: yzxiu/amlogic-s9xxx-openwrt@main` 调用；把 **用到的文件直接复制进 router 仓库**。
- **文件来源** `yzxiu/amlogic-s9xxx-openwrt`（本地已 clone 于 `/workspace/openwrt/amlogic-s9xxx-openwrt`，main @ `a820c16`，已含 LubanCat 定制）：
  - `remake`（核心封装脚本，62KB）
  - `make-openwrt/` 里预置的 LubanCat/rockchip 定制：
    - `different-files/lubancat-1/`（风扇温控 `fan-thermal`/`fan` 脚本等）
    - `platform-files/rockchip/`（`inittab`）
    - `common-files/` 基础（`download_depends` 会拉，可预置保证）
  - `msata/lubancat-msata.dtbo` + `fan/lubancat-fan-pwm.dtbo`（板级 overlay，U-Boot 读 user_overlays）
  - 其余（kernel / u-boot / 其他平台文件）由 remake 运行时 `download_kernel`/`download_depends` 自动拉取，不用预拷
- **运行方式**：router 里建 `ophub/` 子目录（保结构），workflow 内 `cd ophub && sudo ./remake ...`（remake 以 `${PWD}` 为基准，需在仓库根结构内运行）。
- **kernel**：用 `6.18.y`（ophub 该版内核含 WireGuard 适配，之前 LubanCat 用 6.18.53）。
- **编排**：build-firmware 的 lubancat job = 源码编 armsr rootfs → 拷 `*rootfs.tar.gz` 进 ophub → `sudo ./remake -b lubancat-1 -k 6.18.y` → 收集 `.img`。

## 编译期临时调整机制（阶段2 详化）

官方 feeds 不动，用 router 里的脚本在编译前临时修改 feeds（`feeds/packages/.../Makefile` 等），实现：
- 包版本 bump（如 sing-box 1.12.25 → 1.14.2）
- 新增/移除包
优点：`immortalwrt_yzx` / `packages_yzx` 非依赖，官方基线 + 可复现的 patch。

## 当前进行中

- ✅ 阶段1 完成（mt3000 默认版可刷，本地验证）
- ✅ 阶段2 完成（三平台并发出完整包 + Release，run `36122447198` success）
- ✅ 阶段3 完成（lubancat armsr rootfs → ophub remake → 可刷 .img.gz，统一 release 四平台汇总，见 D 段）
- ⏸️ 包定制（编译期临时调整）暂缓
- ✅ 支线·通用软件层：yzx 全套包 + SmartDNS 已填入 packages.conf（见下表）
- ✅ 支线·LubanCat ophub 定制对齐上游（overlay 现场编译 + dhcp/network 同步，见下表）
- ✅ 支线·版本分支策略：仓库按 ImmortalWrt 版本分 v* 分支，各分支独立构建对应版本（见下表）

## 支线：通用软件层按 yzx 蓝本填充（✅ 完成）

目标：按 immortalwrt_yzx `myconfig` 蓝本，把通用软件包清单填进 `config/packages.conf`（官方默认版本）。

- [x] 用户拍板「用官方默认版本，不调整 package 版本」；adguardhome 全平台弃用
- [x] `packages.conf` 从「仅 resolveip」(v1, `57de0e7`) 扩充为 yzx 全套：
  - **25 个包**：代理/UDP2RAW（sing-box / nebula / gost / udp2raw）、WireGuard 全套（wireguard-tools / luci-proto-wireguard / kmod-wireguard + 8 个 kmod 依赖）、工具（resolveip / bash / curl / sudo / terminfo）、运行库（libatomic / libstdcpp / libncurses / libreadline / libcurl）
  - **14 个功能选项**：12 个 `CONFIG_LIBCURL_*`（HTTP/FTP/PROXY/OPENSSL/NGHTTP2 等）+ `CONFIG_BUSYBOX_CUSTOM` / `CONFIG_BUSYBOX_CONFIG_NOHUP`
  - 减掉：adguardhome（用户弃用）、libusb-1.0（被动依赖，defconfig 时被 fold）
- [x] **SmartDNS 四件套入通用层**：smartdns + smartdns-ui + luci-app-smartdns + luci-i18n-smartdns-zh-cn（commit `04a148f`），包数 25 → 29
- [x] `generate-config.sh` 升级：支持**非 Package 的 CONFIG 透传**（原只认 `CONFIG_PACKAGE_`，14 个功能选项会静默丢）——将 `CONFIG_LIBCURL_*`/`CONFIG_BUSYBOX_*` 原样透传到 .config
- [x] 本地 `defconfig` 验证：四平台全通过，**25 包全被官方源接受**，14 功能选项正确透传（NGHTTP2 因缺依赖被 defconfig 关闭，不影响编译）
- [x] 注释按软件组细分（代理/VPN / WireGuard / 工具 / 运行库 / 功能选项每组带说明），并**去除分组序号**（commit `04a148f`，方便增改）
- [x] **CI 编译验证通过**：五平台（含 R3S）均能 defconfig 接受 smartdns 四件套；后续 push 已带这些包进入编译链路

## 支线：新增 NanoPi R3S 平台（✅ 完成）

目标：加入 NanoPi R3S（RK3566 双网口软路由）。与 LubanCat 不同——R3S 是 OpenWrt **官方 rockchip target 原生支持**的设备，直接源码编译出可刷 `.img`，无需 ophub remake。

- [x] 调研确认：R3S = `rockchip/armv8` target，device id `friendlyarm_nanopi-r3s`（官方 firmware-selector 支持），rk3566 `pine64-img` bootflow，产物 `squashfs-sysupgrade.img.gz`（`IMAGES := sysupgrade.img.gz`）；源码树 `target/linux/rockchip/` 有完整定义（armv8.mk + 专属 board.d + DTS patch）
- [x] `config/platforms.conf` 加行：`nanopi-r3s rockchip armv8 friendlyarm_nanopi-r3s ubuntu-24.04`
- [x] workflow Collect case 加 `nanopi-r3s)` 分支：`cp bin/targets/rockchip/armv8/*nanopi-r3s*sysupgrade.img*`（产物是 `.img.gz`，非 squashfs-sysupgrade.img；修复见 commit `73c5c41`）
- [x] `config/platform/nanopi-r3s.conf` 建空占位（对齐其他平台）
- [x] 本地验证：setup awk 矩阵正确含 r3s；generate-config.sh `nanopi-r3s` → `.config` 正确写 `CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r3s=y`，defconfig OK（其他 rockchip 设备置 not set）
- [x] **CI 依赖修复**：rockchip target 的 u-boot 需要 `python3-pyelftools`（ubuntu-24.04 默认未装，apt 包名是 `python3-pyelftools` 而非 `python3-elftools`，commit `f5c37ae`）；Collect 产物后缀 `.img.gz`（commit `73c5c41`）
- [x] （待定）若需定制 R3S 专属软件/驱动，填 `config/platform/nanopi-r3s.conf`

## 支线：平台配置与软件配置分离（✅ 完成）

目标：把「平台列表 + 软件包」从耦合的 `config/<device>.config` 拆成独立声明层，加/减平台或软件互不干扰。

- [x] **平台层** `config/platforms.conf`：声明编译哪些设备 + target/subtarget/设备profile/runner。**唯一来源**，驱动 CI matrix + generate-config.sh 映射（不再硬编码 workflow/generate-config case）
- [x] **通用软件层** `config/packages.conf`：所有平台都装的包（`CONFIG_PACKAGE_*` 行）。初始为空，后续按 yzx 蓝本填充（见上「通用软件层按 yzx 蓝本填充」）
- [x] **平台专用软件层** `config/platform/<device>.conf`：该平台附加（`+CONFIG_PACKAGE_x=y`）/排除（`-CONFIG_PACKAGE_x` 覆盖通用）。四个平台均建空占位 + `README.md` 语法说明
- [x] 重构 `scripts/generate-config.sh`：单参数 `<device>`，读三层 → 合成 `.config`（target + 通用包 + 平台专用附加/排除）；**废弃**旧的 `config/<device>.config` 与 HAS_CONFIG 逻辑（旧 .config 移 `backup/config-old/`）
- [x] workflow：新增 `setup` job 从 platforms.conf 生成矩阵（`fromJson`），build job `needs: setup` 消费；移除 HAS_CONFIG 相关引用
- [x] 本地验证：四平台 generate + `make defconfig` 全 OK；三层合并（附加/排除）功能测试通过（临时测试包 testcommon=全平台 / testboth=被 lubancat 排除 / testlubancatonly=lubancat 独有）
- [x] **CI 修复**：run `36217657839` 在 Generate device config 失败——`set -u` 下空 `packages.conf` 时 `${#pkg[@]}` 报 `unbound variable` → 改用普通数组 `pkg_names` + `add_pkg()`（并在其中剥 `=y` 后缀）；修复后空配置四平台 + 三层合并均本地验证通过（commit 见下）
- [ ] 注：专用软件暂留空，晶晨宝盒等 lubancat 专属包后续填 `config/platform/lubancat.conf`

## 支线：LubanCat ophub 定制对齐上游（✅ 完成）

目标：把 `yzxiu/amlogic-s9xxx-openwrt` 仓库 commit 范围 `c0056fd..a820c16`（LubanCat-1 ImageBuilder 构建线调整）中的内容，逐项评估并迁移到本仓库（LubanCat 走 armsr+remake 路线，只迁适用的运行时/板级定制，不迁 ImageBuilder workflow）。

- [x] **板级 overlay 改现场编译**：原只有编译好的 `.dtbo` 二进制（msata / fan），无源码、有版本漂移风险 → 迁移 `.dts` 源码到 `ophub/dts/{msata,fan}/`，CI 用 `dtc -@` 现场编译成 `.dtbo`；本地验证产物与上游 `cmp` 完全一致（commit `6cac99b` / `0c092f5`）
- [x] **dhcp / network 运行时配置同步**（仅 lubancat 平台注入 `different-files/lubancat-1/rootfs/etc/config/`）：
  - `network`：br-lan 桥接 eth0，`lan` 接口 `proto dhcp`（LubanCat-1 单网口，从上级拿 IP）
  - `dhcp`：dnsmasq 沿用官方默认 DNS 配置，`config dhcp lan/wan` 都 `ignore 1`（本机不答 DHCP，避免与上级冲突，作纯 DNS）
  - commit `02d5074`
- [x] **排查未迁移项结论**：上游该范围其余改动为 ImageBuilder 专属（三套 workflow）或已含（remake overlay 注入、fan 用户态守护在 `different-files`）。`99-lubancat-default-theme`（回 bootstrap 主题）判定**无需迁移**——本仓库 LubanCat 用官方纯净 rootfs 默认即 bootstrap，不含 material（上游是因曾装 material 才需要该兜底脚本）

## 支线：版本分支策略（✅ 完成）

目标：本仓库按 **ImmortalWrt 版本**用分支组织，每个版本分支独立打包对应上游版本的固件。

- [x] **`main` 重建为纯说明页**：orphan 重置，只保留单个 README.md（说明版本分支组织 + 支持机型 + 目录结构），force push 覆盖（commit `f8a67b9`）
- [x] **建 `v25.12.2` 版本分支**：从原 main 分出（含全部构建代码），push 后成为当前主开发分支（commit `6026ef0` 起）
- [x] **workflow 触发改 `v*` 分支**：`on.push.branches` 从 `[main]` → `['v*']`，push 到 `v25.12.2`（或未来 `v25.12.3`）即自动触发编译对应版本
- [x] workflow_dispatch 的 `tag` 默认值由用户在切换版本分支时手动改（如 v25.12.2 → v25.12.3）
- [ ] 后续：上游出新版本（如 v25.12.3）→ 建同名分支 → 在分支上改配置 → push 触发该版本编译

