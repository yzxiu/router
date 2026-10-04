# Docker 零侵入网络 + 配置在升级时的存亡分析

> 本文记录 LubanCat-1（旁路由形态）上 Docker 的完整定制方案：如何让 dockerd **不创建 docker0、不写任何 iptables/nft 规则**，以及这些配置在**双槽 OTA 升级**时哪些保留、哪些会被升级脚本破坏（附 2026-10-03 实机根因排查）。
>
> 实机对照：LubanCat-1（armsr/armv8，内核 6.18.54-ophub）vs NanoPi R3S（rockchip，内核 6.12.103）。

---

## 1. 目标形态（files/lubancat1/ 出厂配置）

| 文件 | 内容要点 |
|---|---|
| `/etc/docker/daemon.json` | `iptables/ip6tables=false`、`bridge=none`、`ip-forward/ip-masq=false`、`log-driver=none`（日志不落盘）、registry-mirrors |
| `/etc/config/dockerd` | 仅 `option alt_config_file '/etc/docker/daemon.json'` |
| `/etc/sysctl.d/99-disable-brnetfilter.conf` | `bridge-nf-call-iptables/ip6tables/arptables=0`（兜底） |
| `/etc/modprobe.d/blacklist-brnetfilter.conf` | `blacklist br_netfilter`（阻止 Docker 自动加载） |

效果：`docker network ls` 只剩 `host/none`；**容器必须 `--network host`**；无端口映射能力（host 模式不需要）；容器日志走前台/syslog，不落盘；拉镜像代理走本机 sing-box（`127.0.0.1:1087`，见 §5）。

---

## 2. docker0 是谁创建的 —— 不是 dockerd，是 netifd

一个容易搞反的事实链：

1. `/etc/init.d/dockerd`（procd 脚本，300 行）的 **`boot()` 钩子**在开机时执行：
   ```sh
   boot() {
       uciadd                 # ← 元凶
       rc_procd start_service
   }
   ```
2. `uciadd()` 无参默认 `iface=docker device=docker0 zone=docker`，往 UCI 写三段：
   - `network.docker` interface（`proto=none, auto=0`）
   - `network` device 段：**`type=bridge, name=docker0`** ← 关键
   - `firewall.docker` zone（input/output/forward 全 ACCEPT）
   - 每段都有"已存在则跳过"的幂等判断
   - 最后 `reload_config` → **netifd（OpenWrt 网络管理器）** 实例化 UCI 里定义的桥 → **docker0 出现**

3. dockerd 自身因 `daemon.json` `bridge=none` **不会**建桥。docker0 与 dockerd 无关——它是 netifd 建的，由 init 脚本的 `boot()→uciadd()` 驱动。

**注意**：`uciadd` 无条件执行（boot 钩子里无开关），即使 daemon.json 配了 `bridge=none` 也照样塞 UCI。纯 device 段（桥）没有 `auto` 概念，UCI 里定义了 netifd 就会实例化。

**修复**：`boot()` 去掉 `uciadd`（`sed -i "/^boot() {/,/^}/ { /uciadd$/d }"`）。代价：init 脚本属 dockerd 包文件，**重装/升级 dockerd 包会被还原** → 需固化进 `files/lubancat1/etc/init.d/dockerd`（待做）。配套：UCI 三段（network.docker / docker0 device / firewall.docker）可删可留（留着 uciadd 跳过，删了被塞回——在 boot 已去掉后无所谓）。

---

## 3. 🔴 br_netfilter —— 旁路由 TCP 全卡的真凶（2026-10-03 实机根因）

### 现象
旁路由形态（下游设备网关指向本机，sing-box tproxy 透明代理）下：**ICMP 通、UDP DNS 通、所有 TCP 卡死**。

### 证据链
```
TCP tproxy 规则命中（nft 计数增长、conntrack SYN_SENT packets=1 无重传）
但 sing-box 12345 端口 0 连接、0 日志
tcpdump 在下游 netns / veth / br-lan 各点均抓不到 SYN 的任何回包
→ 包被 tproxy verdict 接管后在 bridge 上下文中静默消失
```

### 根因
`br_netfilter` 模块（Docker 会自动加载）使**桥转发的包提前进入 netfilter PREROUTING**。sing-box 的 `tproxy` verdict 依赖"包随后走正常 IP 路由（fwmark → `ip rule fwmark 0x1 lookup 100` → `table 100: local default dev lo`）送达本机透明 socket"，而在 **bridge 上下文**里这条路径不成立 → 包被静默丢弃。

对照机 R3S（op4）**未加载** br_netfilter，相同规则一直正常——这就是"规则完全一样、一台通一台不通"的全部差异。

为什么 DNS/ICMP 幸存：DNS 目标是本机 IP（走 local-in 路径，不受 tproxy 策略路由影响）；ICMP 不进 tproxy 规则（只匹配 tcp/udp）。

### 修复
```sh
rmmod br_netfilter                                    # 立即生效
echo "blacklist br_netfilter" > /etc/modprobe.d/blacklist-brnetfilter.conf
cat > /etc/sysctl.d/99-disable-brnetfilter.conf <<EOF   # 兜底
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-arptables = 0
EOF
```

### 与 Docker 的关系
| Docker 功能 | 依赖 br_netfilter？ |
|---|---|
| 容器启停、host 网络 | ❌ |
| bridge 容器互通、NAT 出站、端口映射 | ❌（走 nat 表 postrouting/prerouting 的路由路径）|
| （仅 iptables 旧式"桥内同网段直通过滤"等边缘场景） | ✅ 但几乎无人使用 |

→ 单机 host 用法下**卸载无功能损失**。且 Docker 只有在 bridge/iptables 模式下才可能重新加载它——我们已 `bridge=none + iptables=false`，正常不会再被拉起。

### 内核版本相关性
R3S（6.12.103）无此问题可能也与其内核/环境未加载该模块有关；6.18.54-ophub 上实测必现。**TPROXY 与 br_netfilter 不兼容是已知行为**，另见 https://github.com/openwrt/openwrt/issues 上相关讨论。

---

## 4. ImmortalWrt dockerd init 脚本的字段白名单（alt_config_file 的由来）

`/etc/init.d/dockerd` 的 `process_config()` 只认这些 UCI 字段：
```
data_root / log_level / iptables / ip6tables / log_driver / bip /
registry_mirrors / hosts / dns / ipv6 / ip / fixed_cidr / fixed_cidr_v6 /
proxies(http/https/no) / storage_driver
```
**`bridge` 不在白名单里** —— `option bridge 'none'` 写在 UCI 里会被**静默忽略**。

解决：`option alt_config_file '/etc/docker/daemon.json'` 让 init 直接软链完整 daemon.json，绕过白名单。副作用：设置了 alt_config_file 后 **process_config 整体跳过**（UCI 里所有其他字段包括 proxies section 均不生效），一切以 daemon.json 为准。

---

## 5. 拉镜像代理的演进（http-in → mixed）

| 方案 | 问题 |
|---|---|
| sing-box `http-in`（TLS 代理 @11088，账密认证） | 必须带 SNI 域名（`op4.ck4.top`）才能握手；账密明文不能入库；依赖 dnsmasq hosts 解析 |
| ✅ **sing-box `mixed` @127.0.0.1:1087**（已在 op_config 启用） | 无认证、纯回环、HTTP CONNECT 自动识别；dockerd `daemon.json` `proxies` 直接 `http://127.0.0.1:1087` |

实测：`docker pull hello-world` 8.8s（此前 http-in 方案多次超时失败）。
sing-box 日志确认：`inbound/mixed[2]: inbound connection to registry-1.docker.io:443`。

> 注意：本机容器若用 `socks5://` 记得改 `socks5h://`（DNS 交代理端），否则本机解析被污染导致 5s 卡顿。

---

## 6. OTA 升级时这些配置的存亡（⭐ 核心结论）

### 6.1 保留机制（双槽 OTA 的配置迁移）
`openwrt-update-rockchip`（带 `restore` 参数）按 `openwrt-backup -p` 的 65 项清单，把旧系统的 `/etc/config/` 整目录、`/etc/docker/daemon.json`、`/etc/hosts`、`/etc/rc.local`、`/etc/shadow` 等打包恢复到新槽 → **UCI 与 daemon.json 原则上都跨升级保留**。

### 6.2 🔴 但 dockerd 有专门的"反 alt_config_file"逻辑（OTA 路径必踩）
`openwrt-update-rockchip` L525-598（对**新固件镜像 rootfs** loop 挂载处理）：

```sh
if [ -f ${P2}/etc/init.d/dockerman ] && [ -f ${P2}/etc/config/dockerd ]; then
    # 提取旧系统 data_root/bip/log_level/iptables/registry_mirrors
    #   (UCI 优先, 其次 /etc/docker/daemon.json + jq)
    ...
    # 🔑 刻意删除 alt_config_file:
    if uci get dockerd.globals.alt_config_file >/dev/null 2>&1; then
        uci delete dockerd.globals.alt_config_file
        uci commit
    fi
    # 把提取的数据烘焙进新固件 UCI dockerd.globals.*, auto_start=1
fi
```

设计意图：普通用户 docker 配置散落 UCI/daemon.json，升级后应"回到出厂 UCI + 迁移数据面"。但对**依赖 alt_config_file 的 bridge:none 方案**，这个删除会让 init 回落到 UCI 模式 → `bridge` 白名单外 → dockerd 回到默认行为 → docker0/iptables 复活，**全部修复归零**。

### 6.3 三种刷/升级路径的实际结果（2026-10-03 实测）

| 路径 | alt_config_file | daemon.json | sysctl/modprobe | init 脚本 |
|---|---|---|---|---|
| **OTA 升级**（openwrt-update-rockchip restore） | ❌ **被删**（见 6.2） | ✅ 保留（备份清单含 `./etc/docker/daemon.json`） | ✅ 保留（sysctl.d 不在清单=保留固件新值；modprobe.d 同） | ⚠️ 升级后 init 是新固件版（若新固件未修复 boot→uciadd 则 docker0 复活）|
| **刷机**（recovery/dd 全新写分区） | ✅ 固件自带（files/ 注入） | ✅ 固件自带 | ✅ 固件自带 | ✅ 若新固件已修复则好；否则需要补丁 |
| **手动覆盖 /etc/** | 按操作 | 按操作 | 按操作 | 按操作 |

> 2026-10-03 实际案例：刷机后曾误判"配置被覆盖"——实测核对 `/etc/docker/daemon.json`（时间戳 05:53）、`/etc/modprobe.d/blacklist-brnetfilter.conf`（08:24）、`/etc/sysctl.d/11-br-netfilter.conf` 等全部完好，是**带修复的新镜像**（files/ 注入已生效），只是 IP 从 .4.2 变为 .4.1 造成"一切归零"的错觉。教训：**先核对文件时间戳与内容再下结论**。

### 6.4 OTA 后的 docker 配置自愈方案（待实施）
OTA 会删 `alt_config_file`，需要一个开机自愈点。候选：

| 方案 | 说明 | 推荐度 |
|---|---|---|
| `/etc/uci-defaults/` 脚本 | 只在首次开机跑一次；OTA 后新槽首启即恢复 `alt_config_file` | ⭐⭐ 但只防一次 |
| **watch_dog_control.sh 追加检查** | op_config 每分钟跑，检测 `uci get dockerd.globals.alt_config_file` 为空则 `uci set` + commit + restart dockerd | ⭐⭐⭐ 最稳（op_config 体系内自愈） |
| 上游修复 openwrt-update-rockchip | 保留而非删除 alt_config_file（尊重用户显式配置） | 根治但依赖上游 PR |

---

## 7. 排查方法论备忘（本次踩坑记录）

1. **不要凭"重启后现象"断言"配置丢了"** —— 先 `ls -la` 文件时间戳 + `cat` 内容，对照预期。本案例里配置全在，只是 IP 变化造成"归零"错觉。
2. **tproxy 类问题三看**：nft 计数（规则是否命中）→ conntrack（包是否到达/被吞：`SYN_SENT packets=1` 无重传 = verdict 吞包）→ sing-box 日志（应用是否收到）。
3. **同配置不同行为时，查内核模块差异**：`lsmod` 对照（本次 br_netfilter）、内核版本（6.18 vs 6.12）、bridge/netfilter 交互。
4. **旁路由 tproxy 快速自检三件套**：
   ```sh
   # ① 规则命中?
   nft list chain ip sing-box SING_BOX    # 看 tproxy 规则有无 counter 增长
   # ② 策略路由齐?
   ip rule show | grep fwmark             # 需有 fwmark 0x1 lookup 100
   ip route show table 100                # 需有 local default dev lo
   # ③ 模块捣乱?
   lsmod | grep br_netfilter              # 有 = tproxy TCP 必坏
   ```
5. **netns 模拟下游**（busybox 环境需 `apk add ip-full`）：
   ```sh
   ip netns add dn1; ip link add veth0 type veth peer name veth1
   ip link set veth1 master br-lan; ip link set veth0 netns dn1; ip link set veth0 up
   ip netns exec dn1 ip addr add 192.168.4.250/24 dev veth0
   ip netns exec dn1 ip route add default via <旁路由IP>
   ip netns exec dn1 curl -m 8 http://<公网IP>     # 免去改下游设备路由
   ```
6. **ImmortalWrt 的 dockerd init 白名单**：UCI 方式配不了 `bridge`，复杂定制一律走 `alt_config_file`。

---

## 8. 相关文件索引

| 位置 | 内容 |
|---|---|
| `files/lubancat1/etc/docker/daemon.json` | 固件出厂 daemon.json（无桥/无 iptables/log=none） |
| `files/lubancat1/etc/config/dockerd` | UCI：仅 alt_config_file |
| `files/lubancat1/etc/sysctl.d/99-disable-brnetfilter.conf` | 桥不过 iptables（兜底） |
| `files/lubancat1/etc/modprobe.d/blacklist-brnetfilter.conf` | 模块黑名单 |
| `files/lubancat1/usr/sbin/upgrade-lubancat.sh` | OTA 升级脚本（直连优先，127.0.0.1:1087 代理回退） |
| op_config `tproxy_op_op4.json`（设备上） | sing-box 配置：tproxy + http-in(11088, TLS) + mixed(127.0.0.1:1087) |
| 设备 `/usr/sbin/openwrt-update-rockchip` | 双槽 OTA 脚本（L525-598 dockerd 迁移逻辑） |
| 设备 `/usr/sbin/openwrt-backup` | 配置备份清单（65 项） |
