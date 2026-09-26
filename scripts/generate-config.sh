#!/usr/bin/env bash
# generate-config.sh <device>
# 生成指定机型的 ImmortalWrt config (分层: 平台层 + 通用软件层 + 平台专用软件层)
# 用法: 在 openwrt 源码目录运行: bash scripts/generate-config.sh mt3000
#
# 配置来源 (config/ 目录, 三层):
#   platforms.conf                      # 平台层: 决定编译哪些设备 + target 映射
#   packages.conf                       # 通用软件层: 所有平台都装的包 (CONFIG_PACKAGE_x=y)
#   platform/<device>.conf              # 平台专用软件层: 该平台 附加/+ 或 排除/- 的包
set -euo pipefail

DEVICE="${1:?Usage: generate-config.sh <device>}"

# config 目录 = 本脚本目录的上级的 config/
CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config"
PLATFORMS="${CONFIG_DIR}/platforms.conf"
PACKAGES="${CONFIG_DIR}/packages.conf"
PLATFORM_CONF="${CONFIG_DIR}/platform/${DEVICE}.conf"

# --- 从 platforms.conf 按 device 取一行 ---
LINE="$(awk -v dev="$DEVICE" '$1==dev && $1!~/^#/ && NF>=4 {print; exit}' "${PLATFORMS}")"
if [ -z "${LINE}" ]; then
  echo "ERROR: device '${DEVICE}' not found in ${PLATFORMS}" >&2
  exit 1
fi
TARGET_BOARD="$(echo "${LINE}" | awk '{print $2}')"
TARGET_SUBTARGET="$(echo "${LINE}" | awk '{print $3}')"
DEVICE_PROFILE="$(echo "${LINE}" | awk '{print $4}')"
[ "${DEVICE_PROFILE}" = "-" ] && DEVICE_PROFILE=""

echo ">> Generating config for ${DEVICE} (${TARGET_BOARD}/${TARGET_SUBTARGET}) profile=${DEVICE_PROFILE:-none}"

# --- 暂存区: 组装软件包行 (允许平台排除覆盖通用) ---
# 用普通数组存 "name=y" / "name=#" 两态, 避免 set -u 下空关联数组的坑
declare -A pkg_map=()   # name -> "y" | "excluded"
pkg_names=()            # 按序记录 name, 供输出
raw_config_lines=()     # 非 Package 的 CONFIG 选项 (LIBCURL_*, BUSYBOX_*) 原样透传

add_pkg() {  # $1=name(可能带 =y) $2=y|excluded
  local name="$1" state="$2"
  name="${name%=y}"    # 剥掉可能带上的 "=y" 后缀
  if [ -z "${pkg_map[$name]+x}" ]; then
    pkg_names+=("$name")
  fi
  pkg_map["$name"]="$state"
}

# 读通用层 packages.conf
if [ -f "${PACKAGES}" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "${line}" | xargs)"
    [ -z "${line}" ] && continue
    if [[ "${line}" =~ ^CONFIG_PACKAGE_([A-Za-z0-9_+.-]+)=y$ ]]; then
      add_pkg "${BASH_REMATCH[1]}" "y"
    elif [[ "${line}" =~ ^CONFIG_[A-Za-z0-9_]+(=[ym])?$ ]]; then
      # 非 Package 的 CONFIG 选项 (如 CONFIG_LIBCURL_*, CONFIG_BUSYBOX_*): 原样透传
      raw_config_lines+=("${line}")
    # else: 其他非 CONFIG 行/格式不对 → 忽略
    fi
  done < "${PACKAGES}"
fi

# 读平台专用层: + 附加 / - 排除
if [ -f "${PLATFORM_CONF}" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "${line}" | xargs)"
    [ -z "${line}" ] && continue
    case "${line}" in
      +CONFIG_PACKAGE_*=y)
        add_pkg "${line#+CONFIG_PACKAGE_}" "y"   # 传 name=含 =y, add_pkg 内剥
        ;;
      -CONFIG_PACKAGE_*)
        add_pkg "${line#-CONFIG_PACKAGE_}" "excluded"
        ;;
      *)
        echo "WARNING: skip unrecognized line in ${PLATFORM_CONF}: ${line}" >&2
        ;;
    esac
  done < "${PLATFORM_CONF}"
fi

# --- 写 .config: target 选择 + 软件包(排除后) ---
: > .config
echo "CONFIG_TARGET_${TARGET_BOARD}=y" >> .config
echo "CONFIG_TARGET_${TARGET_BOARD}_${TARGET_SUBTARGET}=y" >> .config
if [ -n "${DEVICE_PROFILE}" ]; then
  echo "CONFIG_TARGET_${TARGET_BOARD}_${TARGET_SUBTARGET}_DEVICE_${DEVICE_PROFILE}=y" >> .config
fi

# 软件包: 按 name 排序输出 (排除的写 not set)
if [ "${#pkg_names[@]}" -gt 0 ]; then
  echo "" >> .config
  echo "# === software packages (common + platform-specific) ===" >> .config
  for name in $(printf '%s\n' "${pkg_names[@]}" | sort); do
    if [ "${pkg_map[$name]}" = "y" ]; then
      echo "CONFIG_PACKAGE_${name}=y" >> .config
    else
      echo "# CONFIG_PACKAGE_${name} is not set  # excluded by ${DEVICE}" >> .config
    fi
  done
fi

# 非 Package 的 CONFIG 选项 (LIBCURL_*, BUSYBOX_* 等): 原样透传
if [ "${#raw_config_lines[@]}" -gt 0 ]; then
  echo "" >> .config
  echo "# === raw CONFIG options (component features) ===" >> .config
  for line in "${raw_config_lines[@]}"; do
    echo "${line}" >> .config
  done
fi

echo ">> Run 'make defconfig' to finalize"
