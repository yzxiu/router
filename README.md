# router - 多机型 OpenWrt 固件打包仓库

> 📌 **后续所有工作以 [PLAN.md](PLAN.md) 为准**（目标 / 架构原则 / 阶段规划 / 编译期调整机制）。

整合多台设备/平台的 ImmortalWrt 固件打包，统一用 GitHub Actions 流水线。
本仓库**不包含 ImmortalWrt 源码**，运行时（CI）才拉取上游源码与 feeds。

## 支持的机型

| 机型 | 架构 / target | 产物 (完整可刷固件) |
|------|---------------|---------------------|
| GL-MT3000 | mediatek / filogic (aarch64_cortex-a53) | `squashfs-sysupgrade.bin` |
| Cudy TR3000 | mediatek / filogic (aarch64_cortex-a53) | `squashfs-sysupgrade.bin` |
| x86-64 | x86 / 64 | `combined[-efi].img.gz` |
| LubanCat-1 (规划中) | armsr / armv8 → ophub 封装 | `.img` |

> 前三台直接用 ImmortalWrt 源码编译出完整可刷固件；
> LubanCat-1 因官方 armsr 为通用 target，先编 rootfs 再经 ophub 封装成可刷 `.img`（阶段3）。

## 目录

```
.github/workflows/build-firmware.yml   # 主流水线(机型参数化)
config/                                # 各机型 config
  mt3000.config                        # (阶段2 加官方纯净版)
  tr3000.config
  x86-64.config
  stage2-custom/                       # 定制版 config 参考(来自 yzx 历史, 阶段2 用)
feeds.conf                             # 官方 feeds (锁定 v25.12.2)
README.md
```

## 使用方法

### GitHub Actions (推荐)
在仓库 Actions 页 `workflow_dispatch` 触发，选择 `device` 并可选修改 `tag`(默认 `v25.12.2`)。

### 触发
- `workflow_dispatch`: 手动指定机型 / tag
- push 到 main: 自动触发 (阶段3 起 LubanCat 流水线同时触发)

## 阶段规划

1. **阶段1 (当前)**: 官方纯净默认 config 跑通 mt3000 出 sysupgrade.bin (不含定制包)
2. **阶段2**: tr3000 / x86-64 干净版 + 加回定制包 (sing-box 1.14.2 / nebula 1.11.2 等)
3. **阶段3**: LubanCat-1 支持 (armsr 编 rootfs + ophub 封装成可刷 .img)

## 上游版本

- 当前默认 tag: `v25.12.2` (可参数化传入)
- 上游源码: https://github.com/immortalwrt/immortalwrt
- 上游 packages: https://github.com/immortalwrt/packages (官方, 锁定 v25.12.2 pin)
