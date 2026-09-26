#!/usr/bin/env bash
# patch-feeds.sh
# 用 router 仓库里的定制包目录 (scripts/package-overrides/<pkg>/) 整体替换 feeds 里对应包目录。
# 目的: 在官方 feeds 基线上定制/升级特定包 (如 sing-box), 而不用 fork feed、不用 sed 逐行改。
#   - 每个定制包一个子目录: scripts/package-overrides/<pkg>/   (含 Makefile + files/ 等)
#   - 调度器遍历所有子目录, 在 feeds 里定位同名包并复制覆盖。
# 用法: 在 openwrt 源码目录 (feeds update/install 之后) 运行: bash <router>/scripts/patch-feeds.sh
# 说明: 版本/编译选项直接写死在 override 目录的 Makefile 里, 手动维护, 不运行时获取。
set -euo pipefail

OVERRIDES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package-overrides"
# 若在 CI, 从 GITHUB_WORKSPACE 定位 (workflow 里 checkout 的是 router 仓库)
if [[ -n "${GITHUB_WORKSPACE:-}" && -d "${GITHUB_WORKSPACE}/scripts/package-overrides" ]]; then
  OVERRIDES_DIR="${GITHUB_WORKSPACE}/scripts/package-overrides"
fi

# 在 openwrt 源码目录内执行 (feeds/ 存在)
[[ -d feeds ]] || { echo "ERROR: 当前目录不是 openwrt 源码树 (无 feeds/)" >&2; exit 1; }

patched=0
for dir in "${OVERRIDES_DIR}"/*/; do
  [[ -d "${dir}" ]] || continue
  pkg="$(basename "${dir%/}")"
  echo "=== overriding feed package: ${pkg} ==="

  # 在 feeds 里定位同名包目录 (包可能在 net/ libs/ 等子目录, 用 find 递归找)
  # 排除 .git 与 build_dir 等非 feeds 路径
  target="$(find feeds -type d -name "${pkg}" -not -path "*/.git/*" 2>/dev/null | head -n 1)"
  if [[ -z "${target}" ]]; then
    echo "  ⚠️ feeds 中未找到包目录 [${pkg}], 跳过 (可确认 feeds update 是否已拉取)"
    continue
  fi

  echo "  → 覆盖 ${target}"
  # 先清空目标, 再整体复制 (避免残留旧文件)
  rm -rf "${target}"
  cp -af "${dir%/}/." "${target}/"
  patched=$((patched+1))
done

echo "patch-feeds: 共覆盖 ${patched} 个包"
exit 0
