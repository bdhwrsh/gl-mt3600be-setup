#!/bin/sh
#
# 把 GL.iNet v4.9.0 概览页的风扇温度滑块范围从原厂 70-90℃ 改成自定义范围。
# 只改一个前端静态资源，不改变当前风扇温度，不安装任何软件包。
# 在电脑本地运行。

set -eu

script_dir="$(cd "$(dirname "$0")" && pwd)"
. "$script_dir/lib-ssh.sh"

remote_asset="/www/views/gl-sdk4-ui-overview.common.js.gz"
remote_backup_dir="/root/gl-fan-ui-backup"
remote_backup="$remote_backup_dir/gl-sdk4-ui-overview.common.js.gz.original"

usage() {
    cat <<'EOF'
用法：
  patch-fan-range-ui.sh status              只读检查当前补丁状态
  patch-fan-range-ui.sh apply [MIN MAX]     应用补丁，默认 40 70
  patch-fan-range-ui.sh restore             恢复首次修改前的原厂资源

范围要求：30 <= MIN < MAX <= 90，且跨度至少 9℃。

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

min="${2:-40}"
max="${3:-70}"

case "$min$max" in
    *[!0-9]*) echo "错误：MIN/MAX 必须是整数。" >&2; exit 2 ;;
esac
if [ "$min" -lt 30 ] || [ "$max" -gt 90 ] || [ "$min" -ge "$max" ]; then
    echo "错误：范围必须满足 30 <= MIN < MAX <= 90。" >&2
    exit 2
fi
if [ "$((max - min))" -lt 9 ]; then
    echo "错误：跨度至少 9℃，否则刻度会重叠。" >&2
    exit 2
fi

if [ "$action" = "restore" ]; then
    rt_ssh "set -eu
        test -f '$remote_backup' || { echo '错误：路由器上没有备份 $remote_backup' >&2; exit 1; }
        gzip -t '$remote_backup'
        cp -a '$remote_backup' '$remote_asset'
        gzip -t '$remote_asset'
        sha256sum '$remote_asset'"
    echo "已恢复原厂风扇页面资源。请强制刷新浏览器缓存。"
    exit 0
fi

# ---- 构造锚点字符串 -------------------------------------------------------

mark_entry() { printf '%s:this.$getTemperatureUnit(%s,this.tUnit)' "$1" "$1"; }

build_marks() {
    _step=$(( ($2 - $1) / 3 ))
    _values="$1 $(($1 + _step)) $(($1 + 2 * _step)) $2"
    _prev=""
    _first=1
    printf 'tMarks(){return{'
    for _v in $_values; do
        [ "$_v" = "$_prev" ] && continue
        _prev="$_v"
        [ "$_first" -eq 1 ] || printf ','
        _first=0
        mark_entry "$_v"
    done
    printf '}}'
}

build_clamp() {
    printf 'handleInpSlider(t){t>%s?this.temperature=%s:t<%s&&(this.temperature=%s)}' \
        "$2" "$2" "$1" "$1"
}

build_tip() {
    printf '$t("overview.fan_setting_tips").replace("$$$$",t.$getTemperatureUnit(%s,t.tUnit)).replace("$$$$",t.$getTemperatureUnit(%s,t.tUnit))' \
        "$1" "$2"
}

build_slider() {
    printf 'staticClass:"main-slider",attrs:{min:%s,max:%s,"show-tooltip":!1,marks:t.tMarks' \
        "$(($1 - 1))" "$(($2 + 1))"
}

# 原厂锚点固定为 70-90℃。tMarks 原厂是 5 个刻度（build_marks 生成 4 个），单独写死。
original_marks='tMarks(){return{70:this.$getTemperatureUnit(70,this.tUnit),75:this.$getTemperatureUnit(75,this.tUnit),80:this.$getTemperatureUnit(80,this.tUnit),85:this.$getTemperatureUnit(85,this.tUnit),90:this.$getTemperatureUnit(90,this.tUnit)}}'
original_clamp="$(build_clamp 70 90)"
original_tip="$(build_tip 70 90)"
original_slider="$(build_slider 70 90)"

patched_marks="$(build_marks "$min" "$max")"
patched_clamp="$(build_clamp "$min" "$max")"
patched_tip="$(build_tip "$min" "$max")"
patched_slider="$(build_slider "$min" "$max")"

# ---- 下载并检查 -----------------------------------------------------------

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gl-fan-ui.XXXXXX")"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT HUP INT TERM

if ! rt_scp_from "$remote_asset" "$work_dir/original.js.gz"; then
    rt_hint_scp
    exit 1
fi
gzip -t "$work_dir/original.js.gz"
gzip -dc "$work_dir/original.js.gz" > "$work_dir/overview.js"

count_exact() { grep -Fo "$1" "$work_dir/overview.js" | wc -l | tr -d ' '; }

patched_hits=0
for anchor in "$patched_marks" "$patched_clamp" "$patched_tip" "$patched_slider"; do
    [ "$(count_exact "$anchor")" = "1" ] && patched_hits=$((patched_hits + 1))
done

original_hits=0
for anchor in "$original_marks" "$original_clamp" "$original_tip" "$original_slider"; do
    [ "$(count_exact "$anchor")" = "1" ] && original_hits=$((original_hits + 1))
done

if [ "$patched_hits" = "4" ]; then
    echo "滑块范围已经是 ${min}-${max}℃，无需修改。"
    exit 0
fi

if [ "$action" = "status" ]; then
    if [ "$original_hits" = "4" ]; then
        echo "当前是原厂状态（70-90℃），尚未打补丁。"
    else
        echo "状态未知：既不匹配原厂锚点，也不匹配 ${min}-${max}℃ 的补丁锚点。" >&2
        echo "可能已被改成其它范围，或固件不是 GL v4.9.0。" >&2
        echo "建议先 restore 回原厂资源，再重新 apply。" >&2
        exit 1
    fi
    exit 0
fi

if [ "$original_hits" != "4" ]; then
    echo "错误：原厂锚点不唯一或不存在（命中 $original_hits/4），拒绝修改。" >&2
    echo "若之前打过其它范围的补丁，请先执行：patch-fan-range-ui.sh restore" >&2
    exit 1
fi

# ---- 替换并校验 -----------------------------------------------------------

ORIGINAL_MARKS="$original_marks" PATCHED_MARKS="$patched_marks" \
ORIGINAL_CLAMP="$original_clamp" PATCHED_CLAMP="$patched_clamp" \
ORIGINAL_TIP="$original_tip" PATCHED_TIP="$patched_tip" \
ORIGINAL_SLIDER="$original_slider" PATCHED_SLIDER="$patched_slider" \
perl -0pi -e '
    s/\Q$ENV{ORIGINAL_MARKS}\E/$ENV{PATCHED_MARKS}/g;
    s/\Q$ENV{ORIGINAL_CLAMP}\E/$ENV{PATCHED_CLAMP}/g;
    s/\Q$ENV{ORIGINAL_TIP}\E/$ENV{PATCHED_TIP}/g;
    s/\Q$ENV{ORIGINAL_SLIDER}\E/$ENV{PATCHED_SLIDER}/g;
' "$work_dir/overview.js"

for anchor in "$patched_marks" "$patched_clamp" "$patched_tip" "$patched_slider"; do
    if [ "$(count_exact "$anchor")" != "1" ]; then
        echo "错误：本地补丁结果校验失败，未上传任何内容。" >&2
        exit 1
    fi
done

gzip -n -9 -c "$work_dir/overview.js" > "$work_dir/patched.js.gz"
gzip -t "$work_dir/patched.js.gz"

local_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# 首次修改前在路由器留原件
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

echo "已把风扇温度滑块范围改为 ${min}-${max}℃。"
echo "SHA256：$remote_hash"
echo "原件备份：$remote_backup"
echo "只改了 WebUI 静态资源，当前风扇温度设置未变。"
echo "请在浏览器中强制刷新页面缓存（macOS: Command+Shift+R）。"
