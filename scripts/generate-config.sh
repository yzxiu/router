#!/usr/bin/env bash
# generate-config.sh <device> <has_config>
# 生成指定机型的 ImmortalWrt config (阶段1: 官方纯净默认)
# 用法: 在 openwrt 源码目录运行: bash scripts/generate-config.sh mt3000 true|false
set -euo pipefail

DEVICE="${1:-mt3000}"
HAS_CONFIG="${2:-false}"

case "${DEVICE}" in
  mt3000)
    TARGET_BOARD="mediatek"
    TARGET_SUBTARGET="filogic"
    DEVICE_PROFILE="glinet_gl-mt3000"
    ;;
  tr3000)
    TARGET_BOARD="mediatek"
    TARGET_SUBTARGET="filogic"
    DEVICE_PROFILE="cudy_tr3000-v1-ubootmod"
    ;;
  x86-64)
    TARGET_BOARD="x86"
    TARGET_SUBTARGET="64"
    DEVICE_PROFILE=""
    ;;
  *)
    echo "ERROR: unknown device '${DEVICE}'" >&2
    exit 1
    ;;
esac

echo ">> Generating config for ${DEVICE} (${TARGET_BOARD}/${TARGET_SUBTARGET})"

# 阶段1: 官方纯净默认 config
# 若仓库里有定制 config, 则用之; 否则生成官方默认
# config 目录 = 本脚本目录的上级的 config/
CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config"
if [ "${HAS_CONFIG}" = "true" ] && [ -f "${CONFIG_DIR}/${DEVICE}.config" ]; then
  echo ">> Using existing config from router repo: config/${DEVICE}.config"
  cp "${CONFIG_DIR}/${DEVICE}.config" .config
else
  echo ">> No custom config, using official default"
  # 清空, 选 target + 设备, 让 make defconfig 生成官方纯净默认
  : > .config
  echo "CONFIG_TARGET_${TARGET_BOARD}=y" >> .config
  echo "CONFIG_TARGET_${TARGET_BOARD}_${TARGET_SUBTARGET}=y" >> .config
  if [ -n "${DEVICE_PROFILE}" ]; then
    echo "CONFIG_TARGET_${TARGET_BOARD}_${TARGET_SUBTARGET}_DEVICE_${DEVICE_PROFILE}=y" >> .config
  fi
fi

echo ">> Run 'make defconfig' to finalize"
