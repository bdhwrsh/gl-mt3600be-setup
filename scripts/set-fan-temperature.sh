#!/bin/sh
#
# 查看/设置 GL.iNet 路由器的风扇启动温度（UCI: glfan），在电脑本地运行。
# 只改 temperature，保留 warn_temperature 等出厂参数；失败自动回滚。

set -eu

script_dir="$(cd "$(dirname "$0")" && pwd)"
. "$script_dir/lib-ssh.sh"

usage() {
    cat <<'EOF'
用法：
  set-fan-temperature.sh status      只读查看当前配置与进程
  set-fan-temperature.sh <30-90>     设置风扇启动温度（℃）

环境变量：
  MT3600BE_TARGET   默认 root@192.168.8.1
  MT3600BE_SSH_KEY  私钥路径；留空则用密码或 ssh-agent
EOF
}

if [ "$#" -ne 1 ]; then
    usage >&2
    exit 2
fi

action="$1"
case "$action" in
    -h|--help|help)
        usage
        exit 0
        ;;
    status)
        mode="status"
        temperature=""
        ;;
    *[!0-9]*|'')
        echo "错误：温度必须是 30 到 90 之间的整数。" >&2
        exit 2
        ;;
    *)
        if [ "$action" -lt 30 ] || [ "$action" -gt 90 ]; then
            echo "错误：温度必须在 30 到 90℃ 之间。" >&2
            exit 2
        fi
        if [ "$action" -lt 40 ]; then
            echo "提示：低于 40℃ 会让风扇几乎常转，噪音明显。"
        fi
        mode="set"
        temperature="$action"
        ;;
esac

rt_ssh sh -s -- "$mode" "$temperature" <<'ROUTER_SCRIPT'
set -eu

mode="$1"
temperature="${2:-}"
config_file="/etc/config/glfan"
service_file="/etc/init.d/gl_fan"

die() {
    echo "错误：$*" >&2
    exit 1
}

show_status() {
    echo "风扇控制配置："
    for key in temperature warn_temperature integration differential; do
        printf '  %s=%s\n' "$key" "$(uci -q get "glfan.@globals[0].$key" || echo '(未设置)')"
    done
    echo "运行进程："
    ps w 2>/dev/null | grep '[g]l_fan' || echo "  未发现 gl_fan 进程"
    echo "当前温度传感器："
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$zone" ] || continue
        printf '  %s = %s\n' "$zone" "$(cat "$zone")"
    done
}

command -v uci >/dev/null 2>&1 || die "路由器上没有 uci 命令"
[ -f "$config_file" ] || die "不存在 $config_file，此机型可能没有可调风扇"
[ -x "$service_file" ] || die "不存在可执行的 $service_file"
[ "$(uci -q get 'glfan.@globals[0]' || true)" = "globals" ] || \
    die "没有找到 glfan.@globals[0] 配置段"

if [ "$mode" = "status" ]; then
    show_status
    exit 0
fi

case "$temperature" in
    *[!0-9]*|'') die "收到无效温度" ;;
esac
[ "$temperature" -ge 30 ] && [ "$temperature" -le 90 ] || \
    die "温度必须在 30 到 90℃ 之间"

umask 077
backup_file="/root/glfan-backup-$(date +%Y%m%d-%H%M%S)"
cp -p "$config_file" "$backup_file" || die "无法备份 $config_file"

restore_backup() {
    cp -p "$backup_file" "$config_file"
    "$service_file" restart >/dev/null 2>&1 || true
}

if uci set "glfan.@globals[0].temperature=$temperature" && uci commit glfan; then
    :
else
    restore_backup
    die "写入 UCI 失败，已恢复原配置"
fi

if ! "$service_file" restart; then
    restore_backup
    die "gl_fan 重启失败，已恢复原配置"
fi

saved_temperature="$(uci -q get 'glfan.@globals[0].temperature' || true)"
if [ "$saved_temperature" != "$temperature" ]; then
    restore_backup
    die "写入结果校验失败，已恢复原配置"
fi

echo "设置成功：风扇启动温度为 ${temperature}℃"
echo "备份文件：$backup_file"
echo
show_status
ROUTER_SCRIPT
