#!/bin/sh
#
# GL.iNet 物理拨动开关事件处理器模板。
#
# 用法：改好下面两个变量后，复制到路由器：
#   scp -O switch-handler-template.sh root@192.168.8.1:/etc/gl-switch.d/<模块名>.sh
#   chmod 755 /etc/gl-switch.d/<模块名>.sh
#   sh -n     /etc/gl-switch.d/<模块名>.sh
# 再用 uci 绑定（见 references/switch-button.md）。
#
# 固件默认方向（本模板沿用，不反转）：
#   物理左侧 ON  -> ACTION=pressed  -> 本脚本收到参数 "on"
#   物理右侧 OFF -> ACTION=released -> 本脚本收到参数 "off"
#
# 不要在电脑本地执行本脚本，也不要在部署后手动用 on/off 试跑。

# ==== 改这里 ===============================================================

# 必填：要控制的 init 脚本
SERVICE_INIT="/etc/init.d/你的服务"

# 可选：服务自身的开机自启开关（UCI 路径）。不需要就留空。
# 例：OpenClash 填 openclash.config.enable
UCI_ENABLE=""

# ===========================================================================

tag="gl-switch-$(basename "$0" .sh)"
gl_action="$1"

log() { logger -t "$tag" "$*"; }

if [ ! -x "$SERVICE_INIT" ]; then
    log "找不到可执行的 $SERVICE_INIT，忽略事件 $gl_action"
    exit 1
fi

set_enable() {
    [ -n "$UCI_ENABLE" ] || return 0
    uci -q set "$UCI_ENABLE=$1"
    uci -q commit "${UCI_ENABLE%%.*}"
}

case "$gl_action" in
    on)
        log "物理左侧 ON：启动 $SERVICE_INIT"
        set_enable 1
        "$SERVICE_INIT" start
        ;;
    off)
        log "物理右侧 OFF：停止 $SERVICE_INIT"
        set_enable 0
        "$SERVICE_INIT" stop
        ;;
    *)
        log "不支持的开关事件：$gl_action"
        exit 1
        ;;
esac
