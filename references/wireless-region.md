# 查看 / 修改无线地区码（菜单 10）⛔

## 先分清楚：这跟菜单 1 不是一回事

| | 菜单 1 固件地区代码 | 本项：无线地区码 |
|---|---|---|
| 存在哪 | flash 的 factory 分区（裸字节） | `/etc/config/wireless`（UCI 配置） |
| 影响 | 整个固件的功能集、菜单可见性 | 单个 radio 的信道和功率 |
| 恢复出厂后 | 保留 | 回到默认 |
| 改错了 | 可能不可逆 | 重启就能救 |

**做过 [菜单 1](region-code.md)（CN → US）之后，无线国家码通常会跟着变成新地区的默认值，一般不需要再单独做这一项。** 先用下面的只读命令确认现状，确实不对再改。

## 先读这一段

**默认不做。**

1. **法规**：无线地区码决定可用信道、发射功率上限和 DFS 行为。改成所在国家/地区实际允许范围之外的设置，可能**违反当地无线电管理规定**，也可能干扰雷达、气象等受保护频段。只在你确实清楚本地法规、且设备就在你自己手里时操作。
2. **可用性**：地区码填错会直接导致 Wi-Fi 不广播、5GHz/6GHz 频段消失、客户端连不上。**改之前必须能通过网线或 SSH 进得去**，否则可能把自己关在门外。
3. **未必生效**：部分 GL.iNet 固件的地区受驱动或 EEPROM 约束，UCI 改了也会被忽略或开机复原。**改完必须复核实际生效值**，不要只看配置文件写了什么就宣布成功。

**执行前必须做到**：菜单 2 的全量备份已完成；用户在知晓上述三点后**明确同意**；已告知回滚方法。用户没有明确点头就停在"只读查看"。

## 只读查看

路由器会话：

```sh
grep -nE "option (country|region|rd_region|aregion)" \
  /etc/config/wireless /etc/config/wireless_applied 2>/dev/null
uci show wireless | grep -iE "country|region"
```

实际生效值（不同驱动支持的命令不一样，有哪个用哪个）：

```sh
iw reg get 2>/dev/null
iwinfo 2>/dev/null | grep -iE "country|Hardware|ESSID"
```

把看到的原值**原样记下来再动手**，回滚要用。

## 修改

先单独备份无线配置：

```sh
cp -p /etc/config/wireless /root/wireless-backup-$(date +%Y%m%d-%H%M%S)
cp -p /etc/config/wireless_applied /root/wireless_applied-backup-$(date +%Y%m%d-%H%M%S) 2>/dev/null || true
```

查出所有 wifi-device 的名字（通常是 `radio0`、`radio1`、`radio2`）：

```sh
uci show wireless | grep "=wifi-device"
```

逐个设置国家码（ISO 3166-1 两位大写，例如 `JP`、`DE`、`CN`、`US`）：

```sh
uci set wireless.radio0.country='XX'
uci set wireless.radio1.country='XX'
uci commit wireless
wifi reload
```

`wifi reload` 之后 Wi-Fi 会短暂断开。**别用 Wi-Fi 连接执行这一步**，用网线。

GL 固件另外维护 `/etc/config/wireless_applied`，管理页保存无线设置时会用它覆盖 `wireless`。如果重启后地区码被还原，说明这份也得跟着改：

```sh
grep -nE "country|region" /etc/config/wireless_applied
uci set wireless_applied.radio0.country='XX'      # 段名以上面 grep 的实际结果为准
uci commit wireless_applied
```

## 复核（必做）

```sh
uci show wireless | grep -i country
iw reg get 2>/dev/null
iwinfo 2>/dev/null | grep -iE "country|ESSID"
```

再重启一次确认不会被还原：

```sh
reboot
```

重启后重新跑一遍上面的复核命令。**配置文件的值 ≠ 驱动实际采用的值**，两者不一致时以驱动为准，并如实报告给用户：这台设备的地区码改不动。

## 回滚

```sh
cp -p /root/wireless-backup-20260101-120000 /etc/config/wireless
cp -p /root/wireless_applied-backup-20260101-120000 /etc/config/wireless_applied 2>/dev/null || true
wifi reload
```

彻底救砖（Wi-Fi 完全起不来时）：网线连 LAN 口 → SSH 进去回滚，或用菜单 2 的备份 `sysupgrade -r` 恢复；再不行走 GL.iNet 的 U-Boot 刷机模式（长按 reset 上电，浏览器打开 `192.168.1.1`）。

## 恢复出厂后

恢复出厂或重刷固件后，地区码会回到固件默认（常见是 `US`/`FCC`）。**这不代表旧配置被恢复了**，只是默认值——排查时别把它当成"备份污染"。
