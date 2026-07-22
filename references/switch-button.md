# 物理拨动开关绑定自定义服务（菜单 6 / 7）

GL.iNet 机身侧面那个拨杆出厂只能绑定固件预置的功能（VPN、AdGuard Home 等）。这两项让它能启停**任意** init 服务，比如 OpenClash、Tailscale、自建脚本。

## 固件默认方向

`/etc/rc.button/switch` 先把物理事件转成参数，再调用 `/etc/gl-switch.d/<模块名>.sh`：

| 物理位置 | 原始事件 | 传给模块的参数 |
|---|---|---|
| 左侧 ON | `pressed` | `on` |
| 右侧 OFF | `released` | `off` |

模板脚本直接沿用这个默认方向，**不反转**。想反过来就在模板里把两个分支对调，并在文档/交接里写清楚。

---

## 菜单 6：安装并绑定模块

### ① 改模板

复制 `scripts/switch-handler-template.sh`，改开头两个变量：

```sh
SERVICE_INIT="/etc/init.d/你的服务"   # 必填
UCI_ENABLE=""                          # 可选，如 openclash.config.enable
```

`UCI_ENABLE` 填了的话，拨到 ON 会先 `uci set <路径>=1` 再启动，OFF 反之——适用于那些"重启后按 enable 决定要不要自启"的服务（OpenClash 就是）。不需要就留空。

### ② 复制到路由器（本地执行）

模块名自己定，只能用小写字母、数字和下划线，下面以 `myservice` 为例：

```sh
scp -O scripts/switch-handler-template.sh \
  root@192.168.8.1:/etc/gl-switch.d/myservice.sh
```

### ③ 校验（路由器会话）

```sh
chmod 755 /etc/gl-switch.d/myservice.sh
sh -n /etc/gl-switch.d/myservice.sh
```

到这一步为止**不会**绑定开关，也**不会**启停任何服务。

### ④ 绑定（路由器会话）

```sh
uci set switch-button.@main[0].func=myservice
uci -q delete switch-button.@main[0].sub_func
uci commit switch-button
```

绑定只写配置，**不会主动同步当前拨杆位置**；要等**下一次拨动或路由器重启**才按物理位置执行。

验证：

```sh
uci -q get switch-button.@main[0].func
logread -f | grep gl-switch     # 另开一个会话，拨一下就能看到日志
```

### 解绑

```sh
uci set switch-button.@main[0].func=none
uci -q delete switch-button.@main[0].sub_func
uci commit switch-button
```

解绑不会改变服务当前的运行状态。

### 保留配置升级时保住模块（可选）

```sh
grep -qxF /etc/gl-switch.d/myservice.sh /etc/sysupgrade.conf \
  || echo /etc/gl-switch.d/myservice.sh >> /etc/sysupgrade.conf
```

> 只有**你自己写的模块脚本**可以进 `sysupgrade.conf`。下面菜单 7 的厂商前端补丁**绝对不行**。

---

## 菜单 7：让 GL 管理页能保存自定义模块

⚠️ **改的是厂商前端压缩 JS，仅在 GL v4.9.0 实测通过。** 先用菜单 0 确认版本。

GL v4.9.0 会自动把 `/etc/gl-switch.d/` 下的模块列进管理页下拉菜单，但点保存时前端会调用只认识原厂功能的 `check_sync_status`，于是返回 `invalid parameter` ——菜单里看得见、选得中、就是存不下。

只用命令行绑定（菜单 6 ④）完全够用，**这一项纯粹是为了在管理页里也能点**。不想动厂商文件就跳过。

在本地执行：

```sh
sh scripts/patch-switch-button-ui.sh status
```

```sh
sh scripts/patch-switch-button-ui.sh apply myservice "My Service"
```

```sh
sh scripts/patch-switch-button-ui.sh restore
```

`apply` 的第二个参数是下拉菜单里显示的标签，省略则直接用模块名。

补丁按 v4.9.0 的**两个唯一文本锚点**定位 `/www/views/gl-sdk4-ui-btnsettings.common.js.gz`，只做三件事：

- 在 `labelMap` 里加一项，让菜单显示你指定的标签；
- 在 `handleApply` 里放行你的模块名，保存时跳过原厂状态检查，直接以 `sync=false` 写入绑定；
- **不同步当前拨杆位置，不启停任何服务。**

已经打过同名补丁则幂等退出；锚点不唯一或版本不兼容则拒绝修改并失败退出。首次 `apply` 前原件备份到路由器：

```text
/root/gl-btn-ui-backup/gl-sdk4-ui-btnsettings.common.js.gz.original
```

补丁后**强制刷新浏览器缓存**再打开开关设置页。

### 固件升级边界

**不要**把改过的前端文件加入 `sysupgrade.conf`，也不要把旧固件的 `.js.gz` 复制到新固件。升级后页面代码会变，需要重新定位锚点适配；`restore` 只对同一次备份有意义。
