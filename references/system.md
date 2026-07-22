# zram-swap 与隐私收尾（菜单 8 / 9）

## 菜单 8：安装 zram-swap

MT3600BE 这类 512MB 内存的机型，一旦跑代理内核、AdGuard Home 或大规则集，很容易被 OOM killer 干掉进程——典型症状是**服务莫名其妙自己停了**，日志里最后一条看着毫无关联。

先确认是不是真的 OOM（路由器会话）：

```sh
free -m
cat /proc/swaps
dmesg | grep -E "Out of memory|Killed process|oom-kill" | tail
```

`/proc/swaps` 空 + dmesg 有 oom 记录 = 值得装。

```sh
opkg update
opkg install zram-swap
/etc/init.d/zram start
/etc/init.d/zram enable
```

验证，应该出现 `/dev/zram0`：

```sh
cat /proc/swaps
free -m
```

512MB 机型默认约 240MB 压缩交换区，实际以现场输出为准。

> 排查经验：某个进程在加载大体积规则/数据库时被 `Killed`，**先看 dmesg 确认 OOM**，别急着怀疑数据文件损坏——两者的表象几乎一样，但处理方式完全不同。

`opkg` 报锁占用时：

```sh
ps w | grep "[o]pkg"
```

有真实进程就等它跑完，**不要删锁文件**；没有进程则稍等后重试一次。

---

## 菜单 9：隐私收尾

GL.iNet 固件默认开着若干云端和远程功能。**逐项问用户要不要关**，不要一把梭。

先看当前状态：

```sh
uci show gl-cloud 2>/dev/null
uci show glconfig 2>/dev/null | grep -iE "cloud|ddns|remote|report|upload"
/etc/init.d/gl_cloud status 2>/dev/null || echo "无 gl_cloud 服务"
ls /etc/init.d/ | grep -iE "cloud|ddns|astro"
```

不同固件版本的服务名和 UCI 段名**不一样**，以上面读到的实际结果为准，别照抄下面的名字。

### 关闭 GL 云服务 / 远程管理

管理页路径通常是：**应用 → GoodCloud**（或 系统 → 高级设置），关掉"绑定到 GoodCloud"和"允许远程访问"。命令行等价操作（服务名以实际读到的为准）：

```sh
/etc/init.d/gl_cloud stop
/etc/init.d/gl_cloud disable
```

### 关闭 DDNS（不用就关）

```sh
/etc/init.d/ddns stop
/etc/init.d/ddns disable
```

### 确认 WAN 侧没开管理端口

```sh
uci show firewall | grep -iE "redirect|rule" | grep -iE "22|80|443"
netstat -tlnp 2>/dev/null | head -20
```

WAN 口不应该监听 SSH 或管理页。**确实需要远程管理就用 WireGuard/Tailscale 拨回来，不要把 22/80 直接暴露到公网。**

### 顺手改掉的两件事

时区（默认常是 UTC，日志时间会对不上）：

```sh
uci set system.@system[0].zonename='Asia/Shanghai'
uci set system.@system[0].timezone='CST-8'
uci commit system
/etc/init.d/system reload
date
```

主机名：

```sh
uci set system.@system[0].hostname='myrouter'
uci commit system
/etc/init.d/system reload
```

改完确认一遍：

```sh
date
uci show system.@system[0]
```
