#!/bin/sh
#=============================================================================
# LubanCat-1 固件自动升级脚本 (在 ImmortalWrt 设备上运行)
#
# 功能:
#   1. 查询 GitHub 最新 release, 自动定位 LubanCat-1 的 .img.gz 固件
#   2. 下载到 /tmp/upload/
#   3. 调用 openwrt-update-rockchip 执行双槽 OTA 升级 (自动 mainline uboot + 备份恢复配置)
#
# 用法:
#   sh upgrade-lubancat.sh            # 查询最新并用最新版
#   sh upgrade-lubancat.sh <tag>      # 指定版本, 如 ImmortalWrt-25.12.2-20261001-1302
#   sh upgrade-lubancat.sh --dry      # 只查询最新固件 URL, 不下载不升级
#
# 依赖: curl (设备自带), openwrt-update-rockchip (luci-app-amlogic 已装)
#=============================================================================
set -u

REPO="yzxiu/router"
TAG="${1:-}"
DRY=0
[ "${TAG}" = "--dry" ] && { DRY=1; TAG=""; }

UPLOAD_DIR="/tmp/upload"
mkdir -p "${UPLOAD_DIR}"

echo "======================================================================"
echo " LubanCat-1 固件自动升级"
echo "======================================================================"

# ---------- 1. 确定 release tag ----------
if [ -n "${TAG}" ]; then
    echo "[1/4] 使用指定版本: ${TAG}"
    RELEASE_URL="https://api.github.com/repos/${REPO}/releases/tags/${TAG}"
else
    echo "[1/4] 查询最新 release ..."
    RELEASE_URL="https://api.github.com/repos/${REPO}/releases/latest"
fi

REL_JSON=$(curl -fsSL --connect-timeout 15 "${RELEASE_URL}" 2>/dev/null) \
    || { echo "[ERROR] 无法访问 GitHub API (网络不通或版本不存在)"; exit 1; }

REL_TAG=$(echo "${REL_JSON}" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
echo "      -> release tag: ${REL_TAG}"

# ---------- 2. 从 assets 定位 lubancat-1 固件 ----------
#   asset url 形如 https://api.github.com/repos/.../releases/assets/<id>
#   固件名形如 openwrt_rockchip_lubancat-1_k6.18.54_*.img.gz
FW_NAME=$(echo "${REL_JSON}" \
    | sed -n 's/.*"name": *"\([^"]*lubancat-1[^"]*\.img\.gz\)".*/\1/p' \
    | head -n1)
FW_URL=$(echo "${REL_JSON}" \
    | sed -n 's/.*"browser_download_url": *"\([^"]*lubancat-1[^"]*\.img\.gz\)".*/\1/p' \
    | head -n1)

if [ -z "${FW_NAME}" ] || [ -z "${FW_URL}" ]; then
    echo "[ERROR] 在 release ${REL_TAG} 中未找到 LubanCat-1 的 .img.gz 固件"
    exit 1
fi
echo "[2/4] 固件: ${FW_NAME}"

if [ "${DRY}" = "1" ]; then
    echo "(dry-run) 下载地址:"
    echo "  ${FW_URL}"
    echo "下载到: ${UPLOAD_DIR}/${FW_NAME}"
    echo "升级命令: cd /tmp/upload && openwrt-update-rockchip ${FW_NAME} yes restore"
    exit 0
fi

# ---------- 3. 下载 ----------
FW_PATH="${UPLOAD_DIR}/${FW_NAME}"
if [ -f "${FW_PATH}" ]; then
    echo "[3/4] 已存在 ${FW_NAME}, 跳过下载 (要强制重下请先删除)"
else
    echo "[3/4] 下载中 ..."
    curl -fL --connect-timeout 15 -o "${FW_PATH}" "${FW_URL}" || {
        echo "[ERROR] 下载失败"; rm -f "${FW_PATH}"; exit 1; }
    echo "      下载完成: $(du -h "${FW_PATH}" | awk '{print $1}')"
fi

# ---------- 4. 触发升级 ----------
echo "[4/4] 启动升级 (openwrt-update-rockchip, auto-uboot=yes, restore=yes) ..."
command -v openwrt-update-rockchip >/dev/null 2>&1 \
    || { echo "[ERROR] 设备未安装 openwrt-update-rockchip (缺 luci-app-amlogic)"; exit 1; }

cd "${UPLOAD_DIR}" || exit 1
echo ">>> 即将重启设备, 升级过程请勿断电。Ctrl+C 取消..."
sleep 5
openwrt-update-rockchip "${FW_NAME}" yes restore
