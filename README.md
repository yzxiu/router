# router - 多机型 OpenWrt 固件打包仓库

> 📌 **后续所有工作以 [PLAN.md](PLAN.md) 为准**（目标 / 架构原则 / 阶段规划 / 编译期调整机制）。

整合多台设备/平台的 ImmortalWrt 固件打包，统一用 GitHub Actions 流水线。
本仓库**不包含 ImmortalWrt 源码**，运行时（CI）才拉取上游源码与 feeds。

## 版本分支组织

本仓库按 **ImmortalWrt 版本**用分支组织，每个版本分支独立打包对应上游版本的固件。

- 上游每发布一个新版本（如 `v25.12.2`、`v25.12.3` …），就在本仓库新建一个**同名分支**。
- 每个版本分支完整包含所有构建内容：流水线（`.github/workflows`）、分层配置（`config/`）、脚本（`scripts/`）、LubanCat 封装素材（`ophub/`）。
- 在该分支上提交 → push 即自动触发 CI（workflow 的 `push` 触发 `v*` 分支），编译**该分支对应的 ImmortalWrt 版本**的固件。
- `main` 分支仅作仓库说明页（单 README），不含构建代码；可用版本分支见仓库 **Branches** 列表。
- 当前默认 tag：`v25.12.2`（workflow_dispatch 可手动改）

## 支持的机型

| 机型 | 架构 / target | 产物 (完整可刷固件) |
|------|---------------|---------------------|
| GL-MT3000 | mediatek / filogic (aarch64_cortex-a53) | `squashfs-sysupgrade.bin` |
| Cudy TR3000 | mediatek / filogic (aarch64_cortex-a53) | `squashfs-sysupgrade.itb` (ubootmod) |
| x86-64 | x86 / 64 | `combined[-efi].img.gz` |
| LubanCat-1 | armsr / armv8 → ophub remake 封装 | `openwrt_rockchip_lubancat-1_k6.18.53_<date>.img.gz` |
| NanoPi R3S | rockchip / armv8 (rk3566) | `friendlyarm_nanopi-r3s-squashfs-sysupgrade.img.gz` |

> mt3000 / tr3000 / x86-64 直接用 ImmortalWrt 源码编译出完整可刷固件；
> LubanCat-1 先用官方 armsr 编 rootfs，再经 ophub remake 封装成可刷 `.img.gz`；
> NanoPi R3S 走官方 rockchip target，直接源码编译输出（不需 remake）。

## 目录

```
.github/workflows/build-firmware.yml   # 主流水线: setup 动态矩阵 + build matrix 五平台 + 统一 release
config/
  platforms.conf                       # 【平台层】声明编译哪些设备 + target + runner (唯一来源)
  packages.conf                        # 【通用软件层】所有平台都装的包 + 功能选项
  platform/                            # 【平台专用软件层】每平台 附加/+ 或 排除/- 的包
    mt3000.conf / tr3000.conf / x86-64.conf / lubancat.conf / nanopi-r3s.conf
scripts/generate-config.sh             # 分层合成 config: 平台层 + 通用软件 + 平台专用 (单参数 <device>)
ophub/                                 # LubanCat 封装素材
  dts/{msata,fan}/                     #   板级 overlay 的 .dts 源码 (CI 现场编译成 .dtbo)
  make-openwrt/.../different-files/lubancat-1/rootfs/   #   LubanCat rootfs 定制注入 (dhcp/network/fan)
  remake                               #   armsr rootfs → 可刷 .img.gz 封装脚本
feeds.conf                             # 官方 feeds (锁定 v25.12.2 pin)
AGENTS.md                              # 仓库协作约定 (改后等确认 / CI 上限)
README.md
PLAN.md                                # 唯一准绳
```

## 配置分层

三层各自独立，加/减平台或软件互不干扰：
- **平台层** `config/platforms.conf`：每行 `<device> <target> <subtarget> <profile> <runner>`，驱动 CI matrix 与 target 映射（唯一来源）。
- **通用软件层** `config/packages.conf`：所有平台统一安装的包（`CONFIG_PACKAGE_x=y`）+ 非包功能选项（`CONFIG_LIBCURL_*` / `CONFIG_BUSYBOX_*`）。以 immortalwrt_yzx `myconfig` 为蓝本，全部用官方源默认版本。当前含 **29 个包**（代理/VPN、WireGuard 全套、工具、**SmartDNS**、运行库）+ 14 个功能选项。
- **平台专用软件层** `config/platform/<device>.conf`：该平台 附加 `+CONFIG_PACKAGE_x=y` / 排除 `-CONFIG_PACKAGE_x`（覆盖通用层）。当前五平台均为空占位。

## 使用方法

### GitHub Actions (推荐)
在仓库 Actions 页 `workflow_dispatch` 触发（可选机型 + tag），或 push 到 `v*` 版本分支自动触发（五平台并发）。CI 运行中若同时活跃 run 超 5 个会自动取消最旧（保留最新 3 个，见 AGENTS.md）。

### 本地生成 config
在官方 ImmortalWrt 源码目录运行：
```bash
bash <router>/scripts/generate-config.sh <device>   # 读三层 → 写 .config
make defconfig                                       # 定稿
```
> 废弃了旧的 `config/<device>.config`（已移入 `backup/config-old/`）。

## 阶段进度

1. **阶段1**: mt3000 官方纯净默认版跑通 ✅
2. **阶段2**: tr3000 / x86-64 多机型 + 统一 Release ✅（包定制⏸️暂缓）
3. **阶段3**: LubanCat-1（armsr rootfs → ophub remake → 可刷 .img.gz）+ 四平台统一 Release ✅
4. **支线（已完成）**:
   - 平台配置与软件配置分层 ✅
   - 新增 NanoPi R3S 平台（rockchip 官方 target，五平台统一）✅
   - 通用软件层按 yzx 蓝本填充（25 包 + 14 选项）✅
   - **SmartDNS 四件套入通用层**（smartdns + smartdns-ui + luci-app-smartdns + zh-cn）✅
   - **LubanCat ophub 定制对齐上游**：板级 overlay 改为现场编译（dts 源码入库、CI `dtc` 出 .dtbo）；dhcp/network 全量同步（LAN 当 DHCP 客户端、纯 DNS）✅

详见 [PLAN.md](PLAN.md)。

## 上游版本

- 上游源码: https://github.com/immortalwrt/immortalwrt
- 上游 packages: https://github.com/immortalwrt/packages (官方, 锁定 v25.12.2 pin)
