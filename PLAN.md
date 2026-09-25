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
│   └── build-firmware.yml      # 主流水线: 源码编译完整固件 (机型参数化, matrix 四平台并发)
├── config/
│   ├── mt3000.config
│   ├── tr3000.config
│   ├── x86-64.config
│   └── lubancat-1.config        # (阶段3, 待固化)
├── ophub/                       # (阶段3) LubanCat 封装素材: remake + make-openwrt + msata/fan
├── feeds.conf                   # 官方 feeds (锁定 v25.12.2 pin)
├── scripts/
│   ├── generate-config.sh       # 按机型生成 config (已建)
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

**D. 联调验证**
- [ ] D1 push 触发 CI，看 lubancat job 完整跑通（rootfs→.img）
- [ ] D2 验证产物 `.img` 可刷（大小/结构）
- [ ] D3 确认三 Linux 平台 + lubancat 四条线都出 Release

**E. 收尾**
- [ ] E1 更新 PLAN.md 勾选完成项 + commit/push
- [ ] E2 清理旧 run / 监控进程

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
- ⏸️ 包定制（编译期临时调整）暂缓
- 🔄 阶段3 进行中：lubancat（armsr/armv8）已加进 build-firmware matrix（run `36156780374` 验证 rootfs 编译）；封装方案已确认（同 job 内 remake 封装 .img），待 rootfs 出 .img 后联调
