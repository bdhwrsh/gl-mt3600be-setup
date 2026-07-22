# 体检、SSH 接入与备份（菜单 0 / 2 / 3）

## 0. 只读体检

登录后在路由器会话执行，全部只读：

```sh
ubus call system board
cat /etc/glversion 2>/dev/null
uname -a
opkg print-architecture
df -h /overlay /tmp
free -m
cat /proc/swaps
```

温度与风扇（有风扇的机型才有 `glfan`）：

```sh
cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null
uci show glfan 2>/dev/null || echo "本机无 glfan 配置"
ps w | grep '[g]l_fan' || echo "未发现 gl_fan 进程"
```

无线地区码（**只看不改**，改动见菜单 10）：

```sh
grep -nE "option (country|region|rd_region|aregion)" \
  /etc/config/wireless /etc/config/wireless_applied 2>/dev/null
```

拨动开关当前绑定：

```sh
uci show switch-button 2>/dev/null || echo "本机无 switch-button 配置"
ls -l /etc/gl-switch.d/ 2>/dev/null
```

GL-MT3600BE 的典型值：

```text
型号     GL.iNet GL-MT3600BE
target   mediatek/mt7987
架构     aarch64_cortex-a53
GL 版本  4.9.0
```

**把体检结果原样报给用户**。后续所有带 ⚠️/⛔ 的项目都以这里读到的**型号和固件版本**为准：型号对不上就不要碰菜单 1，版本对不上就不要套用前端补丁。

## 2. SSH 接入与公钥免密

### 首次登录

GL.iNet 出厂：地址 `192.168.8.1`，SSH 用户 `root`，密码就是初始化向导里设的**管理页密码**（不是 Wi-Fi 密码）。

```sh
ssh root@192.168.8.1
```

如果连不上：

- 确认电脑连的是这台路由器的 LAN 或它的 Wi-Fi；
- 管理页 → 系统 → 高级设置里确认 SSH 已开启（部分固件默认只允许 LAN 侧）；
- 换过 LAN 网段的话用实际网关地址；
- 报 `REMOTE HOST IDENTIFICATION HAS CHANGED`：**先核对指纹**，确认是自己重置过设备再清理 `~/.ssh/known_hosts` 里的对应行，**不要**加 `StrictHostKeyChecking=no`。

### 部署公钥

GL 固件用的是 **dropbear**，不是 openssh-server，公钥文件在：

```text
/etc/dropbear/authorized_keys     权限必须 600
```

没有公钥就先在本地生成（**已有就别重新生成，会覆盖旧私钥**）：

```sh
ssh-keygen -t ed25519 -C "mt3600be"
```

在本地跑脚本，幂等追加、自动修权限并回读校验：

```sh
sh scripts/install-ssh-key.sh ~/.ssh/id_ed25519.pub
```

第一次会提示输入路由器密码（此时还没有免密）。成功后验证：

```sh
ssh -o BatchMode=yes -i ~/.ssh/id_ed25519 root@192.168.8.1 'echo 免密登录成功'
```

之后可以让本 skill 的其他脚本都走这把钥匙：

```sh
export MT3600BE_SSH_KEY=~/.ssh/id_ed25519
```

> 保留配置升级固件时，`/etc/dropbear/authorized_keys` 默认已在系统升级清单内；恢复出厂则会丢，需要重新部署。

## 3. 全量配置备份

**动任何配置之前先做这一步。** 注意这是**配置**备份，救不了菜单 1 那种 flash 层面的损坏——那个有自己的分区备份步骤，两者不能互相替代。

在路由器会话生成备份：

```sh
sysupgrade -b /tmp/backup-$(date +%Y%m%d-%H%M%S).tar.gz
ls -lh /tmp/backup-*.tar.gz
```

在**本地**取回（把文件名换成上面实际输出的）：

```sh
scp -O root@192.168.8.1:/tmp/backup-20260101-120000.tar.gz ~/Downloads/
```

取回后删掉路由器上的临时副本：

```sh
rm -f /tmp/backup-*.tar.gz
```

> 这个备份含 Wi-Fi 密码、SSH 公钥、各类服务凭据。**不要**提交到 Git、上传网盘或贴进聊天。

恢复（会覆盖当前配置并重启，只在确实需要时用）：

```sh
sysupgrade -r /tmp/backup-20260101-120000.tar.gz && reboot
```
