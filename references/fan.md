# 风扇温度与管理页温度滑块（菜单 4 / 5）

两件事互相独立，别混：

- **菜单 4** `set-fan-temperature.sh` 改**实际生效的风扇启动温度**（`/etc/config/glfan` + 重启 `gl_fan`），立即生效。
- **菜单 5** `patch-fan-range-ui.sh` 改**管理页滑块能拖到的范围**（前端静态资源），**不改变当前温度**。

只想让风扇早点转，做菜单 4 就够了。只有想在 GL 管理页上手动拖到 70℃ 以下时，才需要菜单 5。

---

## 菜单 4：设置风扇启动温度

在本地执行：

```sh
sh scripts/set-fan-temperature.sh status
```

```sh
sh scripts/set-fan-temperature.sh 50
```

脚本行为：

- 接受 `30–90℃` 整数（低于 40 会额外提示：风扇可能长期常转）；
- 修改前自动备份 `/etc/config/glfan` 到路由器 `/root/glfan-backup-<时间戳>`；
- 写入失败或 `gl_fan` 重启失败时**自动恢复备份**；
- 只设置 `temperature`，保留出厂告警阈值 `warn_temperature` 及 `integration`、`differential` 等控制参数；
- 不安装软件包，不碰其他任何配置。

手动回滚某个备份（路由器会话）：

```sh
cp -p /root/glfan-backup-20260101-120000 /etc/config/glfan && /etc/init.d/gl_fan restart
```

> 没有 `/etc/config/glfan` 说明该机型没有可调风扇，脚本会直接报错退出。

---

## 菜单 5：把管理页滑块范围改掉

⚠️ **改的是厂商前端压缩 JS，仅在 GL v4.9.0 实测通过。** 先用菜单 0 确认版本。

原厂概览页把风扇滑块钉死在 `70–90℃`。补丁只改这一个文件：

```text
/www/views/gl-sdk4-ui-overview.common.js.gz
```

不安装 GlInjector，不改 Nginx、登录页、防火墙或任何其他功能。

在本地执行：

```sh
sh scripts/patch-fan-range-ui.sh status
```

```sh
sh scripts/patch-fan-range-ui.sh apply
```

```sh
sh scripts/patch-fan-range-ui.sh apply 45 75
```

```sh
sh scripts/patch-fan-range-ui.sh restore
```

`apply` 不带参数时用默认的 `40 70`。范围要求：`30 ≤ MIN < MAX ≤ 90` 且跨度至少 9℃。

首次 `apply` 前原件备份到路由器：

```text
/root/gl-fan-ui-backup/gl-sdk4-ui-overview.common.js.gz.original
```

`apply` 和 `restore` 之后都要**强制刷新浏览器缓存**，否则看到的还是旧 JS。

脚本流程：下载 `.js.gz` → `gzip -t` → 解压到本地临时目录 → 校验四个原始锚点**各恰好出现一次** → 精确文本替换 → 复校四个修改后锚点 → `gzip -n -9` 确定性重压 → 首次修改前在路由器留原件 → 上传后再 `gzip -t` + `sha256sum`。任何一步不符就拒绝写入。

### 已经打过别的范围怎么办

原始锚点找不到、修改后锚点也对不上，说明文件已被改成了**其他范围**（或固件不是 v4.9.0）。先 `restore` 回原件，再重新 `apply`。脚本会在这种情况下直接给出这个提示，不会强改。

---

## 四处替换的依据

补丁执行前要求每个原始锚点**恰好出现一次**，否则拒绝修改。下面以默认的 `40–70℃` 为例。

### 1. 温度刻度

```js
// 原厂
tMarks(){return{70:this.$getTemperatureUnit(70,this.tUnit),75:this.$getTemperatureUnit(75,this.tUnit),80:this.$getTemperatureUnit(80,this.tUnit),85:this.$getTemperatureUnit(85,this.tUnit),90:this.$getTemperatureUnit(90,this.tUnit)}}
// 修改后
tMarks(){return{40:this.$getTemperatureUnit(40,this.tUnit),50:this.$getTemperatureUnit(50,this.tUnit),60:this.$getTemperatureUnit(60,this.tUnit),70:this.$getTemperatureUnit(70,this.tUnit)}}
```

### 2. 输入钳位

```js
// 原厂
handleInpSlider(t){t>90?this.temperature=90:t<70&&(this.temperature=70)}
// 修改后
handleInpSlider(t){t>70?this.temperature=70:t<40&&(this.temperature=40)}
```

### 3. 范围提示文字

```js
// 原厂
$t("overview.fan_setting_tips").replace("$$$$",t.$getTemperatureUnit(70,t.tUnit)).replace("$$$$",t.$getTemperatureUnit(90,t.tUnit))
// 修改后
$t("overview.fan_setting_tips").replace("$$$$",t.$getTemperatureUnit(40,t.tUnit)).replace("$$$$",t.$getTemperatureUnit(70,t.tUnit))
```

### 4. 滑块属性

```js
// 原厂
staticClass:"main-slider",attrs:{min:69,max:91,"show-tooltip":!1,marks:t.tMarks
// 修改后
staticClass:"main-slider",attrs:{min:39,max:71,"show-tooltip":!1,marks:t.tMarks
```

`39/71` 是滑块组件的外层边界（比可选范围各扩 1℃），真正能停留和保存的温度由 `handleInpSlider` 钳位——沿用原厂 `69/91 + 70–90℃` 的同一结构。

### 后端为什么不用改

`/usr/lib/oui-httpd/rpc/fan` 的 `set_config` 有效逻辑：

```lua
local temperature = params.temperature
if temperature then
    c:set("glfan", "globals", "temperature", temperature)
    c:commit("glfan")
    ngx.pipe.spawn({"/etc/init.d/gl_fan", "restart"}):wait()
end
```

它**不检查**温度是否落在 `70–90℃`，也不动 `warn_temperature`。原厂限制**完全在前端**，所以改这四处就能正常保存更低的温度，不需要动 RPC、UCI 结构或风扇服务。这也是菜单 3 能直接写入 40℃ 的原因。

### 上游来源与致谢

思路来自 wkdaily 的 `mt3600.sh`：其菜单第 6 项本身不改滑块，而是安装 `glinjector_3.0.5-6_all.ipk`，由 GlInjector 在浏览器运行时完成同样的四项修改（重写 `handleInpSlider`、重写 `tMarks`、替换 `fan_setting_tips` 上下限、改 `main-slider` 的 `min/max`）。本 skill 不引入 GlInjector 的全局注入框架，只把这四项结果定点写进原厂资源。

```text
主脚本：  https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/mt3600.sh
公共函数：https://cafe.cpolar.cn/wkdaily/gl/raw/branch/main/lib/lib-common.sh
第三方包：glinjector_3.0.5-6_all.ipk
  SHA256：89736459007d5fc6fe1ca0ba7cab46fff81771d994c4b08f61a6ccc4bb9d9a12
```

### 固件升级边界

**不要**把改过的前端文件加入 `sysupgrade.conf`。升级会改变压缩包内容、变量名和组件结构，把旧文件覆盖到新固件可能直接打不开管理页。升级后让新固件恢复原厂资源，重新定位四个锚点再更新补丁。
