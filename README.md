# mt3600be-setup

给 **GL.iNet GL-MT3600BE** 用的开箱设置 skill（Claude Code / Claude Agent SDK）。
克隆到本地后跟 Claude （或其他AI Agent） 说一句「帮我做 MT3600BE 开箱设置」，它会先列一份可选项清单，你挑编号，它再动手。

大部分项目对其他 GL.iNet 4.x 机型同样适用；**前端补丁类项目只在 GL 固件 v4.9.0 上实测过。**

## 能做什么

| # | 项目 | 风险 |
|---|---|---|
| 0 | 只读体检（型号、固件、架构、内存、存储、温度、无线地区） | 无 |
| 1 | ⛔ **修改固件地区代码 CN → US**（仅限 MT3600BE，解锁国际版功能与隐藏菜单） | **最高：写裸 flash，有变砖风险** |
| 2 | SSH 接入 + 公钥免密登录（dropbear） | 低 |
| 3 | 全量配置备份 `sysupgrade -b` | 无 |
| 4 | 设置风扇启动温度（改 `glfan`，立即生效） | 低 |
| 5 | ⚠️ 管理页温度滑块范围补丁（原厂 70–90℃ → 自定义，默认 40–70℃） | 中 |
| 6 | 物理拨动开关绑定任意服务（左 ON 启动 / 右 OFF 停止） | 低 |
| 7 | ⚠️ 让管理页能保存自定义开关模块（绕过 `check_sync_status`） | 中 |
| 8 | 安装 zram-swap（512MB 机型缓解 OOM） | 低 |
| 9 | 隐私收尾：关闭云服务、远程管理、DDNS；顺手改时区/主机名 | 低 |
| 10 | ⛔ 查看 / 修改无线地区码（UCI） | 高，涉及当地无线电法规 |

**第 1 项要做就必须最先做**：它改的是 flash 里的 factory 数据，不随固件走，改完建议恢复出厂让地区相关配置重新生成——开箱阶段做代价为零，等你把 Wi-Fi 和插件都配好了再改就得重来一遍。这一项**故意没有做成一键脚本**：每一步都有验证闸门（型号校验 → 整分区备份到本地并核对哈希 → 目标偏移必须恰好读到 `CN` → 写后回读必须是 `US`），读到的东西不对就停。

## 安装

克隆到本地 Claude Code 会扫描的技能目录。目录名必须为 `mt3600be-setup`（与 SKILL.md 中的 `name` 保持一致）：

```sh
# 克隆到 Claude 全局 skills 文件夹
git clone https://github.com/bdhwrsh/gl-mt3600be-setup.git ~/.claude/skills/mt3600be-setup
```

```sh
# 或使用其他 agent，暂存到桌面，手动移动到工作区
git clone https://github.com/bdhwrsh/gl-mt3600be-setup.git ~/Desktop/mt3600be-setup
```

装好后跟 Claude 说「帮我做 MT3600BE 开箱设置」即可。

目录结构：

```text
mt3600be-setup/
├── SKILL.md                       # 入口：可选项清单、安全边界、连接约定
├── references/
│   ├── region-code.md             # 菜单 1（最危险，单独一份）
│   ├── checkup-and-access.md      # 菜单 0 / 2 / 3
│   ├── fan.md                     # 菜单 4 / 5（含四处锚点依据）
│   ├── switch-button.md           # 菜单 6 / 7
│   ├── system.md                  # 菜单 8 / 9
│   └── wireless-region.md         # 菜单 10（危险项，单独一份）
└── scripts/
    ├── lib-ssh.sh                 # 公共 SSH/SCP 封装，供以下脚本 source
    ├── install-ssh-key.sh
    ├── set-fan-temperature.sh
    ├── patch-fan-range-ui.sh
    ├── patch-switch-button-ui.sh
    └── switch-handler-template.sh # 路由器侧模板
```

## 直接当脚本用

不装 skill 也行，脚本本身是独立的 POSIX sh。下面按在终端里一行一行输入的顺序来讲，看不懂的命令照抄即可。

**准备**：打开终端，先进入你克隆下来的项目文件夹（路径按你的实际位置改，例如全局 skill 目录）：

```sh
cd ~/.claude/skills/mt3600be-setup
```

**第 1 步 · 设置两个环境变量**——告诉脚本要连哪台路由器、用哪个密钥。每次新开一个终端窗口，都要先把这两行跑一遍：

```sh
# 路由器的登录地址。root@ 后面是路由器 IP，GL.iNet 出厂默认就是 192.168.8.1，一般不用改
export MT3600BE_TARGET=root@192.168.8.1

# 登录用的 SSH 私钥路径。如果你还没配过密钥、想用密码登录，把这一行整行删掉即可（脚本会提示你输密码）
export MT3600BE_SSH_KEY=~/.ssh/id_ed25519
```

**第 2 步 · 装公钥，实现免密码登录**（第一次会提示你输一次路由器管理密码）：

```sh
sh scripts/install-ssh-key.sh ~/.ssh/id_ed25519.pub
```

**第 3 步 · 查看 / 设置风扇启动温度**：

```sh
sh scripts/set-fan-temperature.sh status    # 只读：先看当前设置
sh scripts/set-fan-temperature.sh 50        # 把风扇启动温度设成 50℃
```

**第 4 步 · 改风扇滑块的可调范围**（会修改路由器网页）：

```sh
sh scripts/patch-fan-range-ui.sh status        # 只读：看当前补丁状态
sh scripts/patch-fan-range-ui.sh apply 40 70   # 把滑块范围改成 40–70℃
sh scripts/patch-fan-range-ui.sh restore       # 想撤销时：一键还原
```

**第 5 步 · 放行拨动开关设置页**（可选，会修改路由器网页）：

```sh
sh scripts/patch-switch-button-ui.sh apply myservice "My Service"
```

> 第 3–5 步是按需选用的，不必全跑。带 `status` 的都是只读、可以放心先试；带 `apply` 的才会真正改动路由器，且都能用 `status` 查看、`restore` 还原。

**本机需要**：`ssh`、`scp`（OpenSSH ≥ 8.6，为了 `-O`；更旧的设 `MT3600BE_SCP_COMPAT=`）、`perl`、`gzip`、`sha256sum` 或 `shasum`。macOS 和主流 Linux 发行版默认都有。

## 设计约定

- **默认只读。** 脚本默认只查看、不修改，只有你明确指定的那一项才会真正写入路由器。
- **先备份再改。** 每次写入前都会自动备份；万一失败自动还原。
- **最冒险的一步不自动化。** 唯一需要直接写 flash 的操作（改地区码）没做成脚本，而是带你一步步手动执行，中途设了四道检查——只要有一步结果不对就停下。
- **网页补丁改得很谨慎。** 两个界面补丁靠一段唯一的文本来定位要改的位置，定位不唯一就拒绝修改；改完还会校验文件是否完好（`gzip -t` + SHA256）。两者都支持 `status`（查看状态）和 `restore`（一键还原）。
- **不碰物理开关。** 不替你拨开关、不同步拨杆方向、不自动启停任何服务。
- **升级固件后请使用 Claude Code 重新运行此项目。** gl 网页修改补丁不会写进 `sysupgrade.conf`，所以刷新固件后这些界面改动会失效，需要重新执行一次。

## 免责声明

非官方项目，与 GL.iNet 无关。修改厂商固件的地区代码、前端资源和无线设置有风险，**请自行判断并承担后果**。

- **第 1 项（固件地区代码）会直接写裸 flash 分区**，同一分区还存着 MAC 和射频校准数据。偏移量因型号而异（MT3600BE 是 `mtdblock3@16520`，而 MT3000 是 `@136`、AXT1800 是 `mtdblock8@152`——差两个数量级）。**照抄别的型号的数字会毁设备，且可能不可逆。** 也可能影响保修。
- 第 10 项（无线地区码）可能违反当地无线电管理规定。

以上仅供在你自己拥有的设备上、合法合规的前提下使用。

来源与致谢：地区代码的偏移量与命令来自社区公开教程（见 `references/region-code.md` 的来源列表），本项目在其基础上追加了型号校验、强制整分区备份、写前读值校验和写后回读校验。温度滑块部分的思路来自 wkdaily 的 `mt3600.sh` / GlInjector（见 `references/fan.md`）；本项目不引入 GlInjector，只做定点文本替换。

MIT License。
