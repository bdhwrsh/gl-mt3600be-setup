#!/bin/sh
#
# 把本地公钥幂等地部署到 GL.iNet 路由器的 dropbear authorized_keys。
# 在电脑本地运行；第一次会提示输入路由器管理密码。

set -eu

script_dir="$(cd "$(dirname "$0")" && pwd)"
. "$script_dir/lib-ssh.sh"

pubkey_file="${1:-$HOME/.ssh/id_ed25519.pub}"

case "$pubkey_file" in
    -h|--help|help)
        cat <<'EOF'
用法：
  install-ssh-key.sh [公钥文件]        默认 ~/.ssh/id_ed25519.pub

环境变量：
  MT3600BE_TARGET   默认 root@192.168.8.1
EOF
        exit 0
        ;;
    "~/"*) pubkey_file="$HOME/${pubkey_file#\~/}" ;;
esac

if [ ! -r "$pubkey_file" ]; then
    echo "错误：读不到公钥文件：$pubkey_file" >&2
    echo "没有公钥就先生成（已有请勿重复生成）：ssh-keygen -t ed25519 -C mt3600be" >&2
    exit 1
fi

pubkey="$(cat "$pubkey_file")"

case "$pubkey" in
    ssh-rsa\ *|ssh-ed25519\ *|ecdsa-sha2-*\ *|sk-ssh-ed25519*\ *|sk-ecdsa-*\ *) ;;
    *)
        echo "错误：$pubkey_file 看起来不是 SSH 公钥。" >&2
        echo "注意别把私钥（BEGIN OPENSSH PRIVATE KEY）传上去。" >&2
        exit 1
        ;;
esac

case "$pubkey" in
    *"'"*)
        echo "错误：公钥（多半是注释部分）含单引号，无法安全地传到远端。" >&2
        echo "请去掉注释里的单引号后重试。" >&2
        exit 1
        ;;
esac

case "$pubkey" in
    *"
"*)
        echo "错误：$pubkey_file 含多行内容，请只放一把公钥。" >&2
        exit 1
        ;;
esac

echo "目标：$MT3600BE_TARGET"
echo "公钥：$pubkey_file"

# 整把公钥带空格，必须在远端命令行里加引号，否则会被远端 shell 拆成多个参数
rt_ssh "sh -s -- '$pubkey'" <<'ROUTER_SCRIPT'
set -eu

new_key="$1"
auth_file="/etc/dropbear/authorized_keys"

umask 077
mkdir -p /etc/dropbear
[ -f "$auth_file" ] || : > "$auth_file"

if grep -qxF "$new_key" "$auth_file"; then
    echo "该公钥已存在，未重复写入。"
else
    cp -p "$auth_file" "$auth_file.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    # 确保追加前文件以换行结尾，避免和上一行粘连
    if [ -s "$auth_file" ] && [ "$(tail -c 1 "$auth_file" | wc -l)" -eq 0 ]; then
        echo "" >> "$auth_file"
    fi
    echo "$new_key" >> "$auth_file"
    echo "公钥已追加。"
fi

chmod 600 "$auth_file"
chown root:root "$auth_file" 2>/dev/null || true

echo "当前 $auth_file："
ls -l "$auth_file"
awk '{print NR": "$1" ..."$NF}' "$auth_file"
ROUTER_SCRIPT

echo
echo "验证免密（把私钥路径换成你自己的）："
echo "  ssh -o BatchMode=yes -i ~/.ssh/id_ed25519 $MT3600BE_TARGET 'echo 免密登录成功'"
echo "之后可让本 skill 其他脚本复用这把钥匙："
echo "  export MT3600BE_SSH_KEY=~/.ssh/id_ed25519"
