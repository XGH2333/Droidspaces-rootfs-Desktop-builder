#!/usr/bin/env bash
set -euo pipefail

# configure-ssh — 在 RootFS 构建期配置 sshd
# - 启用 sshd 服务（Debian/Fedora 默认未 enable，Ubuntu/Arch 已 enable）
# - 允许密码登录（所有发行版）
# - 可选：向普通用户追加 SSH 公钥
#
# 用法: configure-ssh <username> <enable_sshd true|false> [ssh_public_key]

USERNAME="${1:?缺少用户名}"
ENABLE_SSHD="${2:-false}"
SSH_PUBLIC_KEY="${3:-}"

case "$ENABLE_SSHD" in true|false) ;; *)
    echo "无效的 enable_sshd 值：$ENABLE_SSHD" >&2; exit 1 ;;
esac

# 提供公钥时隐含启用 sshd
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    ENABLE_SSHD="true"
fi

# ---- 公钥格式校验（防 workflow 传入坏值；允许多个 key，逗号分隔） ----
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    IFS=',' read -ra KEYS <<< "$SSH_PUBLIC_KEY"
    for key in "${KEYS[@]}"; do
        key="$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -n "$key" ]] || continue
        if ! echo "$key" | grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com) [A-Za-z0-9+/=]+( .*)?$'; then
            echo "SSH 公钥格式无效：$key" >&2
            exit 1
        fi
    done
fi

if [[ "$ENABLE_SSHD" != "true" ]]; then
    echo "[configure-ssh] 未开启 sshd，跳过。"
    exit 0
fi

# ---- 生成缺失的主机密钥 ----
ssh-keygen -A

# ---- sshd_config：允许密码登录 ----
SSHD_CONFIG="/etc/ssh/sshd_config"
[[ -f "$SSHD_CONFIG" ]] || { echo "找不到 $SSHD_CONFIG" >&2; exit 1; }

# 用 drop-in 覆盖（sshd_config.d 优先级高于主配置），同时保留主配置原样以便卸载
install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/50-droidspaces.conf <<'EOF'
# Droidspaces RootFS: allow password login for the container user
PasswordAuthentication yes
KbdInteractiveAuthentication no
UsePAM yes
EOF

# 兜底：部分发行版主配置没有 Include，直接改主配置
if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_CONFIG"; then
    sed -i 's/^[#[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' "$SSHD_CONFIG"
    grep -q '^PasswordAuthentication yes' "$SSHD_CONFIG" || \
        echo 'PasswordAuthentication yes' >> "$SSHD_CONFIG"
fi

# ---- 追加公钥 ----
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
    [[ -n "$USER_HOME" ]] || { echo "找不到用户 $USERNAME" >&2; exit 1; }
    install -d -m 0700 -o "$USERNAME" -g "$USERNAME" "$USER_HOME/.ssh"
    AUTH_KEYS="$USER_HOME/.ssh/authorized_keys"
    touch "$AUTH_KEYS"
    for key in "${KEYS[@]}"; do
        key="$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -n "$key" ]] || continue
        # 幂等：已存在的公钥不重复写入
        if ! grep -qF "$key" "$AUTH_KEYS" 2>/dev/null; then
            echo "$key" >> "$AUTH_KEYS"
        fi
    done
    chown "$USERNAME:$USERNAME" "$AUTH_KEYS"
    chmod 0600 "$AUTH_KEYS"
    echo "[configure-ssh] 已向 $USERNAME 的 authorized_keys 追加 ${#KEYS[@]} 个公钥。"
fi

# ---- 启用 sshd 服务 ----
# systemd 在容器构建 chroot 中可离线 enable（仅创建 symlink）
case "$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')" in
    fedora) SSH_SERVICE="sshd" ;;
    arch|archarm|archlinux) SSH_SERVICE="sshd" ;;
    *) SSH_SERVICE="ssh" ;;
esac

if systemctl enable "$SSH_SERVICE" 2>/dev/null; then
    echo "[configure-ssh] 已启用 $SSH_SERVICE 服务。"
else
    # 兼容无 systemctl 场景：手动创建 symlink
    SYSTEMD_DIR="/etc/systemd/system/multi-user.target.wants"
    UNIT_SRC="/lib/systemd/system/${SSH_SERVICE}.service"
    [[ -f "$UNIT_SRC" ]] || UNIT_SRC="/usr/lib/systemd/system/${SSH_SERVICE}.service"
    if [[ -f "$UNIT_SRC" ]]; then
        install -d -m 0755 "$SYSTEMD_DIR"
        ln -sfn "$UNIT_SRC" "$SYSTEMD_DIR/${SSH_SERVICE}.service"
        echo "[configure-ssh] 已手动启用 $SSH_SERVICE 服务。"
    else
        echo "[configure-ssh] 警告：找不到 $SSH_SERVICE.service，未能启用服务。" >&2
    fi
fi

echo "[configure-ssh] sshd 配置完成（允许密码登录$([[ -n "$SSH_PUBLIC_KEY" ]] && printf '，已注入公钥')）。"
