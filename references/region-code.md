# 固件地区代码 CN → US（菜单 1）⛔

**这是整份 skill 里风险最高的一项。没有用户明确点头就停在只读那一步。**

## 这是什么

GL.iNet 的 **CN 版固件**在插件生态、无线发射功率和可用频段上有限制，管理页里一部分菜单直接隐藏。地区代码是**写在 flash 的 factory 数据里的 2 个 ASCII 字节**，跟固件版本无关——刷固件、恢复出厂都不会改变它。把它从 `CN` 改成 `US`，那些限制和隐藏菜单就解开了。

这跟菜单 10 的**无线地区码**是两回事：

| | 菜单 1 固件地区代码 | 菜单 10 无线地区码 |
|---|---|---|
| 存在哪 | flash 的 factory 分区（裸字节） | `/etc/config/wireless`（UCI 配置） |
| 影响 | 整个固件的功能集、菜单可见性 | 单个 radio 的信道和功率 |
| 恢复出厂后 | **保留** | 回到默认 |
| 风险 | 写错可能不可逆损坏 | 改错重启就能救 |

做完菜单 1 之后，无线国家码通常会跟着变成新地区的默认值，一般**不需要**再单独做菜单 10。

## 为什么必须放在开箱第一步

改完建议做一次**恢复出厂**，让所有跟地区相关的配置重新生成。开箱阶段做代价为零——还没有任何配置可丢。等你把 Wi-Fi、代理、插件都配好了再改，就得重来一遍。

## ⛔ 风险

1. **这是直接写裸 flash 分区**，不是改配置文件。同一分区里还存着 MAC 地址和射频校准数据，**写错偏移量可能造成不可逆损坏**——U-Boot 重刷固件也救不回射频校准。
2. **偏移量因型号而异，差得非常远**。已知的公开数据：

   | 型号 | 分区 | 偏移量 |
   |---|---|---|
   | **GL-MT3600BE** | `/dev/mtdblock3` | **16520** |
   | MT3000 | `/dev/mtdblock3` | 136 |
   | MT6000 | `/dev/mmcblk0p2` | 136 |
   | MT2500 | `/dev/mmcblk0boot1` | 136（需先解写保护） |
   | AX1800 / AXT1800 | `/dev/mtdblock8` | 152 |
   | BE3600 | `/dev/mtdblock11` | 见来源 |

   注意 MT3600BE 的 16520 和其他型号的 136/152 差了两个数量级。**照抄别的型号的数字＝毁设备。**
3. 可能影响保修。

**所以下面每一步都有验证闸门：读到的东西不对就停，绝不硬写。**

---

## 执行流程

### 第 0 步：确认型号（不匹配就停）

```sh
ubus call system board
cat /etc/glversion
cat /proc/mtd
```

`model` 必须是 **GL-MT3600BE**。不是就到此为止，把型号报给用户，让用户自己去找对应型号的偏移量。

把 `/proc/mtd` 的输出**完整报给用户**，确认 `mtd3` 存在及其大小。

### 第 1 步：只读查看当前地区代码

```sh
dd if=/dev/mtdblock3 bs=1 count=2 skip=16520 2>/dev/null | hexdump -C
```

期望看到：

```text
00000000  43 4e                                             |CN|
```

**读到的不是 `CN` 就停下。** 可能是型号不同、固件不同，或者已经改过了。先看上下文再说：

```sh
dd if=/dev/mtdblock3 bs=1 count=80 skip=16488 2>/dev/null | hexdump -C
```

（`16488 = 16520 - 32`，即前后各看 32 字节。）

### 第 2 步：备份整个分区到电脑（强制，不可跳过）

**这是唯一的回退依据。** 在路由器上导出：

```sh
dd if=/dev/mtdblock3 of=/tmp/mtd3-backup.bin bs=64k
sha256sum /tmp/mtd3-backup.bin
ls -l /tmp/mtd3-backup.bin
```

在**电脑本地**取回并核对哈希：

```sh
scp -O root@192.168.8.1:/tmp/mtd3-backup.bin ~/Downloads/
shasum -a 256 ~/Downloads/mtd3-backup.bin
```

**两边哈希必须一致**，不一致就重传。取回后清理路由器上的临时文件：

```sh
rm -f /tmp/mtd3-backup.bin
```

★ 明确告诉用户：这个 `.bin` 一定要收好，出问题只能靠它。

### 第 3 步：离线核对偏移量（推荐）

在电脑本地扫描刚取回的备份，确认 16520 确实落在地区码上，而不是碰巧撞上别的 `CN`：

```sh
perl -e 'local $/; open my $f,"<:raw",$ARGV[0] or die; my $d=<$f>;
  printf("长度 %d 字节\n", length $d);
  printf("偏移 %d 处：%s\n", $ARGV[1], substr($d,$ARGV[1],2));
  my $p=-1; while(($p=index($d,"CN",$p+1))>=0){
    my $s=substr($d,($p>24?$p-24:0),56); $s=~s/[^\x20-\x7e]/./g;
    printf("  %s %-8d  %s\n", ($p==$ARGV[1]?"->":"  "), $p, $s); }' \
  ~/Downloads/mtd3-backup.bin 16520
```

把结果给用户看：偏移 16520 处必须是 `CN`，且上下文应该像一段配置区（附近常见 `firsttest`、`secondtest`、`COUNTRY` 之类的标记），而不是一堆随机二进制。

### 第 4 步：写入（⛔ 到这一步必须有用户明确的"确认执行"）

确认前三步全部通过，再写这 2 个字节：

```sh
printf 'US' | dd of=/dev/mtdblock3 bs=1 seek=16520 conv=notrunc
sync
```

> 用 `printf 'US'` 不要用 `echo -n`——busybox 的 `echo` 对 `-n` 的处理不一致，可能把 `-n` 当内容写进去。

### 第 5 步：回读验证（不通过就别重启）

```sh
dd if=/dev/mtdblock3 bs=1 count=2 skip=16520 2>/dev/null | hexdump -C
```

必须看到：

```text
00000000  55 53                                             |US|
```

**没看到 `US` 就不要重启**，先拿备份文件人工核对。

### 第 6 步：重启（让用户自己执行）

```sh
reboot
```

重启后：

1. 管理页语言切到 **English**，检查原本隐藏的菜单是否出现；
2. 复查无线国家码是否已跟着变（命令见 [wireless-region.md](wireless-region.md) 的只读部分）；
3. **可选但推荐**：管理页做一次恢复出厂，让地区相关配置全部重新生成。开箱阶段做代价为零。

---

## 回退

改回 CN，同样先读后写：

```sh
dd if=/dev/mtdblock3 bs=1 count=2 skip=16520 2>/dev/null | hexdump -C   # 应为 US
printf 'CN' | dd of=/dev/mtdblock3 bs=1 seek=16520 conv=notrunc
sync
dd if=/dev/mtdblock3 bs=1 count=2 skip=16520 2>/dev/null | hexdump -C   # 应为 CN
reboot
```

**整分区回滚**（只在 2 字节回退救不回来时用，风险更高）：把备份传回路由器后

```sh
dd if=/tmp/mtd3-backup.bin of=/dev/mtdblock3 bs=64k
sync
reboot
```

写整块分区期间**绝对不能断电**。

## 救砖

- 还能 SSH：按上面回退。
- 进不去系统：网线接 LAN 口 → 断电，按住 reset 再上电，保持约 10 秒进入 U-Boot 刷机模式 → 浏览器打开 `192.168.1.1` 上传固件。
- U-Boot 能刷但 Wi-Fi 异常（信号极弱、频段缺失、MAC 变成全 `00` 或全 `FF`）：说明 factory 校准数据被破坏了，**刷固件救不回来**，只能靠第 2 步的分区备份还原。**这就是为什么第 2 步不可跳过。**

## 来源

本节的偏移量和命令来自以下公开教程，本 skill 在其基础上**追加了型号校验、强制整分区备份、写前读值校验、写后回读校验**四道闸门：

- [GL.iNet MT3600BE 路由器折腾备忘 – Miao's Blog](https://blog.miaom.uk/glinet-mt3600be-note/)（MT3600BE 的 `mtdblock3` / 偏移 16520 出处）
- [GL-iNet GL-BE3600 路由器改地区教程 – 比特派对](https://www.bitpd.com/glbe3600unlock.html)
- [Harodekeimu/GL-iNet-GeoChanger](https://github.com/Harodekeimu/GL-iNet-GeoChanger) · [Zayrick/GL-iNet-GeoChanger](https://github.com/Zayrick/GL-iNet-GeoChanger)（多机型分区/偏移对照）
- [GL-iNet MT3000 切換成國際版 – NatLee](https://gist.github.com/NatLee/7added5173feb64b1f76beb5443d8a58)

以上均为第三方社区教程，非 GL.iNet 官方文档。**偏移量随型号和固件批次而变，务必以你自己第 1 步实际读到的内容为准。**
