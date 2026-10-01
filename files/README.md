# files/ — 设备自定义文件覆盖

本目录用于存放**打进固件 rootfs 的自定义文件**。构建时这些文件会按原路径覆盖进目标设备的固件镜像。

## 目录结构约定

每个设备一个独立目录，目录名与设备标识一致（见 `config/platforms.conf`）：

```
files/<device>/<目标路径>/<文件名>
```

例如 LubanCat-1：
```
files/lubancat1/usr/sbin/upgrade-lubancat.sh
```
构建后该文件会出现在固件内的 `/usr/sbin/upgrade-lubancat.sh`。

## 工作原理

1. 构建时，workflow 的 `Copy custom files` 步骤会把本仓库 `files/<DEVICE>/` 的内容
   复制到 OpenWrt 源码树的 `files/` 目录（`include/image.mk` 的 `prepare_rootfs` 使用 `$(TOPDIR)/files`）。
2. OpenWrt 构建系统会把源码树顶 `files/` 目录下的文件，**按相对路径原样铺进固件 rootfs**。
3. 若某设备没有 `files/<DEVICE>/` 目录，则该步骤静默跳过，不影响其他平台。

## 约定

- **每个设备一个子目录**，不要共用/混放，避免不同设备的自定义文件互相污染。
- **目录名必须与 `platforms.conf` 里的设备标识一致**（如 `lubancat1`、`radxa-a5e`）。
- 文件权限会保留，脚本类记得 `chmod +x`，以便固件内可直接执行。
- 需要给设备加自定义文件时，在 `files/<device>/` 下按目标路径放置即可，**无需改动 workflow**。
