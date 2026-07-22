#!/bin/sh
#
# 让 GL.iNet v4.9.0 的拨动开关设置页能保存自定义 /etc/gl-switch.d/<模块>.sh。
# 只改前端静态资源：不绑定开关、不同步拨杆位置、不启停任何服务。
# 在电脑本地运行。

set -eu

script_dir="$(cd "$(dirname "$0")" && pwd)"
. "$script_dir/lib-ssh.sh"

remote_asset="/www/views/gl-sdk4-ui-btnsettings.common.js.gz"
remote_backup_dir="/root/gl-btn-ui-backup"
remote_backup="$remote_backup_dir/gl-sdk4-ui-btnsettings.common.js.gz.original"

usage() {
    cat <<'EOF'
用法：
  patch-switch-button-ui.sh status                    只读检查当前补丁状态
  patch-switch-button-ui.sh apply <模块名> [显示标签]  放行指定模块
  patch-switch-button-ui.sh restore                   恢复首次修改前的原厂资源

模块名 = /etc/gl-switch.d/<模块名>.sh 的文件名，只能用小写字母、数字、下划线。
显示标签省略时直接用模块名。

环境变量：
  MT3600BE_TARGET   默认 root@192.168.8.1
  MT3600BE_SSH_KEY  私钥路径；留空则用密码或 ssh-agent
EOF
}

action="${1:-status}"
case "$action" in
    -h|--help|help) usage; exit 0 ;;
    status|apply|restore) ;;
    *) usage >&2; exit 2 ;;
esac

if [ "$action" = "restore" ]; then
    rt_ssh "set -eu
        test -f '$remote_backup' || { echo '错误：路由器上没有备份 $remote_backup' >&2; exit 1; }
        gzip -t '$remote_backup'
        cp -a '$remote_backup' '$remote_asset'
        gzip -t '$remote_asset'
        sha256sum '$remote_asset'"
    echo "已恢复原厂开关设置页资源。请强制刷新浏览器缓存。"
    exit 0
fi

module="${2:-}"
if [ "$action" = "apply" ] && [ -z "$module" ]; then
    echo "错误：apply 需要指定模块名。" >&2
    usage >&2
    exit 2
fi
module="${module:-openclash}"

case "$module" in
    *[!a-z0-9_]*|'')
        echo "错误：模块名只能包含小写字母、数字和下划线：$module" >&2
        exit 2
        ;;
esac

label="${3:-$module}"
case "$label" in
    *'"'*|*'\'*|*"'"*)
        echo "错误：显示标签不能包含引号或反斜杠。" >&2
        exit 2
        ;;
esac

# ---- 锚点 -----------------------------------------------------------------

original_label='labelMap(){return{adguardhome:"AdGuard Home",'
patched_label="labelMap(){return{$module:\"$label\",adguardhome:\"AdGuard Home\","

original_apply='handleApply(){this.func.includes("none")||this.showTorTips?this.setBtnConfig():this.checkFuncStatus()}'
patched_apply="handleApply(){this.func.includes(\"none\")||this.func.includes(\"$module\")||this.showTorTips?this.setBtnConfig():this.checkFuncStatus()}"

# ---- 下载并检查 -----------------------------------------------------------

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gl-btn-ui.XXXXXX")"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT HUP INT TERM

if ! rt_scp_from "$remote_asset" "$work_dir/original.js.gz"; then
    rt_hint_scp
    exit 1
fi
gzip -t "$work_dir/original.js.gz"
gzip -dc "$work_dir/original.js.gz" > "$work_dir/btnsettings.js"

count_exact() { grep -Fo "$1" "$work_dir/btnsettings.js" | wc -l | tr -d ' '; }

if [ "$(count_exact "$patched_label")" = "1" ] && \
   [ "$(count_exact "$patched_apply")" = "1" ]; then
    echo "开关设置页已经放行模块 $module（标签 $label），无需修改。"
    exit 0
fi

label_hits="$(count_exact "$original_label")"
apply_hits="$(count_exact "$original_apply")"

if [ "$action" = "status" ]; then
    if [ "$label_hits" = "1" ] && [ "$apply_hits" = "1" ]; then
        echo "当前是原厂状态，尚未放行任何自定义模块。"
        exit 0
    fi
    echo "状态未知：原厂锚点命中 labelMap=$label_hits, handleApply=$apply_hits。" >&2
    echo "可能已为其它模块打过补丁，或固件不是 GL v4.9.0。" >&2
    echo "建议先 restore 回原厂资源，再重新 apply。" >&2
    exit 1
fi

if [ "$label_hits" != "1" ] || [ "$apply_hits" != "1" ]; then
    echo "错误：原厂锚点不唯一或不存在（labelMap=$label_hits, handleApply=$apply_hits），拒绝修改。" >&2
    echo "若之前为别的模块打过补丁，请先执行：patch-switch-button-ui.sh restore" >&2
    exit 1
fi

# ---- 替换并校验 -----------------------------------------------------------

ORIGINAL_LABEL="$original_label" PATCHED_LABEL="$patched_label" \
ORIGINAL_APPLY="$original_apply" PATCHED_APPLY="$patched_apply" \
perl -0pi -e '
    s/\Q$ENV{ORIGINAL_LABEL}\E/$ENV{PATCHED_LABEL}/g;
    s/\Q$ENV{ORIGINAL_APPLY}\E/$ENV{PATCHED_APPLY}/g;
' "$work_dir/btnsettings.js"

if [ "$(count_exact "$patched_label")" != "1" ] || \
   [ "$(count_exact "$patched_apply")" != "1" ]; then
    echo "错误：本地补丁结果校验失败，未上传任何内容。" >&2
    exit 1
fi

gzip -n -9 -c "$work_dir/btnsettings.js" > "$work_dir/patched.js.gz"
gzip -t "$work_dir/patched.js.gz"

local_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

rt_ssh "set -eu
    mkdir -p '$remote_backup_dir'
    if [ ! -e '$remote_backup' ]; then cp -a '$remote_asset' '$remote_backup'; fi
    gzip -t '$remote_backup'"

rt_scp_to "$work_dir/patched.js.gz" "$remote_asset"

remote_hash="$(rt_ssh "set -eu
    chmod 664 '$remote_asset'
    gzip -t '$remote_asset'
    sha256sum '$remote_asset' | awk '{print \$1}'")"

expected_hash="$(local_sha256 "$work_dir/patched.js.gz")"

if [ -n "$expected_hash" ] && [ "$remote_hash" != "$expected_hash" ]; then
    echo "错误：上传后哈希不一致（本地 $expected_hash / 远端 $remote_hash）。" >&2
    echo "原件仍在 $remote_backup，可执行 restore 恢复。" >&2
    exit 1
fi

echo "已放行模块 $module，菜单标签显示为「$label」。"
echo "SHA256：$remote_hash"
echo "原件备份：$remote_backup"
echo "补丁不绑定开关、不同步拨杆位置、不启停任何服务。"
echo "请强制刷新浏览器缓存后再打开开关设置页。"
