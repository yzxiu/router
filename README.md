# router - 多机型 OpenWrt 固件打包仓库

> 📌 **后续所有工作以 [PLAN.md](PLAN.md) 为准**（目标 / 架构原则 / 阶段规划 / 编译期调整机制）。

整合多台设备/平台的 ImmortalWrt 固件打包，统一用 GitHub Actions 流水线。
本仓库**不包含 ImmortalWrt 源码**，运行时（CI）才拉取上游源码与 feeds。

## 支持的机型

| 机型 | 架构 / target | 产物 (完整可刷固件) |
|------|---------------|---------------------|
| GL-MT3000 | mediatek / filogic (aarch64_cortex-a53) | `squashfs-sysupgrade.bin` |
| Cudy TR3000 | mediatek / filogic (aarch64_cortex-a53) | `squashfs-sysupgrade.itb` (ubootmod) |
| x86-64 | x86 / 64 | `combined[-efi].img.gz` |
| LubanCat-1 | armsr / armv8 → ophub remake 封装 | `openwrt_rockchip_lubancat-1_k6.18.53_<date>.img.gz` |
| NanoPi R3S | rockchip / armv8 (rk3566) | `friendlyarm_nanopi-r3s-squashfs-sysupgrade.img` |

> mt3000 / tr3000 / x86-64 直接用 ImmortalWrt 源码编译出完整可刷固件；
> LubanCat-1 先用官方 armsr 编 rootfs，再经 ophub remake 封装成可刷 `.img.gz`。
> 四平台已全部跑通（阶段3 主线闭环，统一 Release 汇总，见 PLAN D 段）。

## 目录

```
.github/workflows/build-firmware.yml   # 主流水线: setup 动态矩阵 + build matrix 四平台 + 统一 release
config/
  platforms.conf                       # 【平台层】声明编译哪些设备 + target + runner (唯一来源)
  packages.conf                        # 【通用软件层】所有平台都装的包 + 功能选项
  platform/                            # 【平台专用软件层】每平台 附加/+ 或 排除/- 的包
    mt3000.conf / tr3000.conf / x86-64.conf / lubancat.conf / nanopi-r3s.conf
scripts/generate-config.sh             # 分层合成 config: 平台层 + 通用软件 + 平台专用 (单参数 <device>)
ophub/                                 # LubanCat 封装素材: remake + make-openwrt + msata/fan dtbo
feeds.conf                             # 官方 feeds (锁定 v25.12.2 pin)
AGENTS.md                              # 仓库协作约定 (旧 CI run 不用停)
README.md
PLAN.md                                # 唯一准绳
```

## 配置分层

三层各自独立，加/减平台或软件互不干扰：
- **平台层** `config/platforms.conf`：每行 `<device> <target> <subtarget> <profile> <runner>`，驱动 CI matrix 与 target 映射（唯一来源）。
- **通用软件层** `config/packages.conf`：所有平台统一安装的包（`CONFIG_PACKAGE_x=y`）+ 非包功能选项（`CONFIG_LIBCURL_*` / `CONFIG_BUSYBOX_*`）。以 immortalwrt_yzx `myconfig` 为蓝本，全部用官方源默认版本。当前含 25 个包（代理/VPN、WireGuard 全套、工具、运行库）+ 14 个功能选项。
- **平台专用软件层** `config/platform/<device>.conf`：该平台 附加 `+CONFIG_PACKAGE_x=y` / 排除 `-CONFIG_PACKAGE_x`（覆盖通用层）。当前四平台均为空占位。

## 使用方法

### GitHub Actions (推荐)
在仓库 Actions 页 `workflow_dispatch` 触发（选机型），或 push 到 main 自动触发（四平台并发）。

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
   - 支线：平台配置与软件配置分层 ✅ (已将 resolveip) → yzx 全套 25 包填入通用层（CI 编译验证中）

详见 [PLAN.md](PLAN.md)。

## 上游版本

- 当前默认 tag: `v25.12.2` (可参数化传入)
- 上游源码: https://github.com/immortalwrt/immortalwrt
- 上游 packages: https://github.com/immortalwrt/packages (官方, 锁定 v25.12.2 pin)
