# config/platform/ — 平台专用软件需求层
# 这里的 <device>.conf 只对该平台生效 (附加/排除通用 packages.conf 里的包)。
#
# 语法 (每行一个):
#   +CONFIG_PACKAGE_<name>=y   # 附加: 该平台额外安装的包
#   -CONFIG_PACKAGE_<name>     # 排除: 该平台不要通用清单里的某包 (生成时对应
#                              #        "# CONFIG_PACKAGE_<name> is not set")
#
# 例 (lubancat):
#   +CONFIG_PACKAGE_luci-app-amlogic=y   # 晶晨宝盒 (仅 lubancat 有)
#
# 当前专用配置全部留空, 后续按平台逐步补。
