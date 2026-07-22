#!/bin/sh
#
# 由同目录的脚本 source 使用，不要直接执行。
#
# 环境变量：
#   MT3600BE_TARGET       SSH 目标，默认 root@192.168.8.1
#   MT3600BE_SSH_KEY      私钥路径；留空则用密码或 ssh-agent
#   MT3600BE_SCP_COMPAT   默认 -O（旧 SCP 协议）。OpenSSH < 8.6 请显式设为空字符串

MT3600BE_TARGET="${MT3600BE_TARGET:-root@192.168.8.1}"
MT3600BE_SSH_KEY="${MT3600BE_SSH_KEY:-}"
MT3600BE_SCP_COMPAT="${MT3600BE_SCP_COMPAT--O}"

if [ -n "$MT3600BE_SSH_KEY" ]; then
    # 允许写成 ~/.ssh/id_ed25519
    case "$MT3600BE_SSH_KEY" in
        "~/"*) MT3600BE_SSH_KEY="$HOME/${MT3600BE_SSH_KEY#\~/}" ;;
    esac
    if [ ! -r "$MT3600BE_SSH_KEY" ]; then
        echo "错误：无法读取 SSH 私钥：$MT3600BE_SSH_KEY" >&2
        exit 1
    fi
fi

# rt_ssh <远程命令...>
rt_ssh() {
    if [ -n "$MT3600BE_SSH_KEY" ]; then
        ssh -o IdentitiesOnly=yes -i "$MT3600BE_SSH_KEY" "$MT3600BE_TARGET" "$@"
    else
        ssh "$MT3600BE_TARGET" "$@"
    fi
}

# rt_scp_from <远程路径> <本地路径>
rt_scp_from() {
    # shellcheck disable=SC2086  # $MT3600BE_SCP_COMPAT 需要按词展开，可为空
    if [ -n "$MT3600BE_SSH_KEY" ]; then
        scp $MT3600BE_SCP_COMPAT -q -o IdentitiesOnly=yes -i "$MT3600BE_SSH_KEY" \
            "$MT3600BE_TARGET:$1" "$2"
    else
        scp $MT3600BE_SCP_COMPAT -q "$MT3600BE_TARGET:$1" "$2"
    fi
}

# rt_scp_to <本地路径> <远程路径>
rt_scp_to() {
    # shellcheck disable=SC2086
    if [ -n "$MT3600BE_SSH_KEY" ]; then
        scp $MT3600BE_SCP_COMPAT -q -o IdentitiesOnly=yes -i "$MT3600BE_SSH_KEY" \
            "$1" "$MT3600BE_TARGET:$2"
    else
        scp $MT3600BE_SCP_COMPAT -q "$1" "$MT3600BE_TARGET:$2"
    fi
}

rt_hint_scp() {
    cat >&2 <<'EOF'
提示：若报 "unknown option -- O"，说明本机 OpenSSH < 8.6，请改用：
  MT3600BE_SCP_COMPAT= sh <脚本> ...
若报 "/usr/libexec/sftp-server: not found"，则相反——必须保留默认的 -O。
EOF
}
