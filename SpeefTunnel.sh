#!/usr/bin/env bash

set -u

APP="SPEEF TUNNEL"
VERSION="1.0.0"

BASE="/etc/speef-tunnel"
TUNNELS="$BASE/tunnels"
STATE="$BASE/state"
KEYDIR="/opt/tunnel/.ssh"
KEY="$KEYDIR/id_ed25519"
USER="tunnel"
SERVICE_PREFIX="speef-tunnel"

R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
W='\033[1;37m'
M='\033[0;35m'
D='\033[0;90m'
N='\033[0m'

[[ $EUID -eq 0 ]] || {
    echo "❌ Please run as root."
    exit 1
}

mkdir -p "$BASE" "$TUNNELS"

pause() {
    echo
    read -rp "👉 Press Enter to continue..."
}

ip4() {
    curl -4 -fsS --max-time 4 https://api.ipify.org 2>/dev/null ||
    hostname -I 2>/dev/null | awk '{print $1}'
}

role() {
    [[ -f "$STATE" ]] &&
        awk -F= '$1=="ROLE"{print $2}' "$STATE"
}

count() {
    find "$TUNNELS" -maxdepth 1 -type f -name '*.conf' 2>/dev/null | wc -l
}

line() {
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
}

header() {
    clear
    echo
    echo -e "${M}                         CODMLAK${N}"
    echo -e "${W}                      SPEEF TUNNEL${N}"
    echo -e "${D}                         v${VERSION}${N}"
    echo
    line
    echo -e " ${C}🌐 Server Information${N}"
    line
    echo -e " IPv4 Address : ${W}$(ip4)${N}"

    local r
    r="$(role || true)"

    if [[ "$r" == "IRAN" ]]; then
        echo -e " Server Role  : ${W}🇮🇷 IRAN${N}"
        echo -e " Status       : ${G}🟢 INSTALLED${N}"
    elif [[ "$r" == "KHAREJ" ]]; then
        echo -e " Server Role  : ${W}🌍 KHAREJ${N}"
        echo -e " Status       : ${G}🟢 INSTALLED${N}"
    else
        echo -e " Server Role  : ${D}Not Installed${N}"
        echo -e " Status       : ${R}🔴 NOT INSTALLED${N}"
    fi

    echo -e " Version      : ${W}${VERSION}${N}"
    echo -e " Tunnels      : ${W}$(count)${N}"
    line
    echo
}

deps() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y openssh-client openssh-server curl ca-certificates iproute2 procps >/dev/null 2>&1
}

user_create() {
    if ! id "$USER" >/dev/null 2>&1; then
        useradd --system --create-home --shell /usr/sbin/nologin "$USER"
    fi
}

state() {
    cat > "$STATE" <<EOT
ROLE=$1
VERSION=$VERSION
INSTALLED_AT=$(date '+%Y-%m-%d %H:%M:%S')
EOT
    chmod 600 "$STATE"
}

iran_install() {
    header
    echo -e "${W}🇮🇷 IRAN SERVER INSTALL${N}"
    line
    echo

    deps
    user_create

    mkdir -p "$KEYDIR"

    if [[ ! -f "$KEY" ]]; then
        ssh-keygen -t ed25519 -f "$KEY" -N "" -C "speef-tunnel" >/dev/null 2>&1
    fi

    chmod 700 "$KEYDIR"
    chmod 600 "$KEY"
    chmod 644 "$KEY.pub"

    state "IRAN"

    echo
    line
    echo -e "${G}🟢 Iran server is ready.${N}"
    line
    echo
    echo -e "${Y}🔑 Public Key for Kharej:${N}"
    echo
    cat "$KEY.pub"
    echo
    echo -e "${D}این کلید فقط برای Pair کردن دو سرور است.${N}"
    pause
}

kharej_install() {
    header
    echo -e "${W}🌍 KHAREJ SERVER INSTALL${N}"
    line
    echo

    deps
    user_create

    mkdir -p "/home/$USER/.ssh"
    touch "/home/$USER/.ssh/authorized_keys"

    echo -e "${C}🔑 Public Key سرور ایران را وارد کنید:${N}"
    echo

    local pub
    read -r -p "👉 Iran Public Key: " pub

    if [[ ! "$pub" =~ ^ssh-ed25519[[:space:]] ]]; then
        echo -e "${R}❌ Public Key نامعتبر است.${N}"
        pause
        return
    fi

    grep -qxF "$pub" "/home/$USER/.ssh/authorized_keys" ||
        echo "$pub" >> "/home/$USER/.ssh/authorized_keys"

    chown -R "$USER:$USER" "/home/$USER/.ssh"
    chmod 700 "/home/$USER/.ssh"
    chmod 600 "/home/$USER/.ssh/authorized_keys"

    local cfg="/etc/ssh/sshd_config"
    local marker="# CODMLAK-SPEEF-TUNNEL"

    if ! grep -qF "$marker" "$cfg" 2>/dev/null; then
        cat >> "$cfg" <<EOT

$marker
Match User $USER
    PasswordAuthentication no
    PubkeyAuthentication yes
    AllowTcpForwarding local
    X11Forwarding no
    AllowAgentForwarding no
    PermitTTY no
EOT
    fi

    if ! sshd -t; then
        echo -e "${R}❌ SSH configuration test failed.${N}"
        pause
        return
    fi

    systemctl enable ssh >/dev/null 2>&1 || true
    systemctl restart ssh

    state "KHAREJ"

    echo
    line
    echo -e "${G}🟢 Kharej server is ready.${N}"
    line
    echo
    echo -e "${G}✔ Iran key registered${N}"
    echo -e "${G}✔ TCP forwarding enabled${N}"
    echo -e "${G}✔ SSH restrictions enabled${N}"
    pause
}

install_menu() {
    while true; do
        header
        echo -e "${W}📥 INSTALL SPEEF TUNNEL${N}"
        line
        echo
        echo " 1) 🇮🇷 Install as Iran Server"
        echo " 2) 🌍 Install as Kharej Server"
        echo " 3) 🔙 Back"
        echo
        read -r -p "👉 Your choice: " x

        case "$x" in
            1) iran_install ;;
            2) kharej_install ;;
            3) return ;;
            *) echo -e "${R}❌ Invalid choice.${N}"; sleep 1 ;;
        esac
    done
}

valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

add_tunnel() {
    header

    [[ "$(role)" == "IRAN" ]] || {
        echo -e "${R}❌ فقط روی سرور ایران.${N}"
        pause
        return
    }

    echo -e "${W}➕ ADD TUNNEL${N}"
    line
    echo

    local lp rip rp sp
    read -r -p "🇮🇷 Iran Listen Port : " lp
    valid_port "$lp" || { echo "❌ Invalid port"; pause; return; }

    [[ ! -f "$TUNNELS/$lp.conf" ]] || {
        echo -e "${R}❌ این پورت قبلاً ساخته شده.${N}"
        pause
        return
    }

    read -r -p "🌍 Kharej IP / Host   : " rip
    [[ -n "$rip" ]] || { echo "❌ Invalid address"; pause; return; }

    read -r -p "🎯 Kharej Target Port : " rp
    valid_port "$rp" || { echo "❌ Invalid target port"; pause; return; }

    read -r -p "🔐 Kharej SSH Port [22]: " sp
    sp="${sp:-22}"
    valid_port "$sp" || { echo "❌ Invalid SSH port"; pause; return; }

    cat > "$TUNNELS/$lp.conf" <<EOT
LOCAL_PORT=$lp
REMOTE_IP=$rip
REMOTE_PORT=$rp
SSH_PORT=$sp
EOT

    cat > "/etc/systemd/system/$SERVICE_PREFIX-$lp.service" <<EOT
[Unit]
Description=Speef Tunnel $lp
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
ExecStart=/usr/bin/ssh -N -T \
-o ExitOnForwardFailure=yes \
-o ServerAliveInterval=10 \
-o ServerAliveCountMax=6 \
-o TCPKeepAlive=yes \
-o ConnectTimeout=10 \
-o ConnectionAttempts=3 \
-o StrictHostKeyChecking=no \
-o PasswordAuthentication=no \
-o PubkeyAuthentication=yes \
-o Compression=no \
-o IPQoS=throughput \
-o UserKnownHostsFile=$KEYDIR/known_hosts \
-o Ciphers=chacha20-poly1305@openssh.com,aes256-gcm@openssh.com \
-o KexAlgorithms=curve25519-sha256,curve25519-sha256@libssh.org \
-o Port=$sp \
-i $KEY \
-L 0.0.0.0:$lp:127.0.0.1:$rp \
$USER@$rip
Restart=always
RestartSec=2
StartLimitIntervalSec=0
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOT

    chmod 600 "$TUNNELS/$lp.conf"
    chmod 644 "/etc/systemd/system/$SERVICE_PREFIX-$lp.service"

    systemctl daemon-reload
    systemctl enable "$SERVICE_PREFIX-$lp.service" >/dev/null 2>&1
    systemctl restart "$SERVICE_PREFIX-$lp.service"

    echo
    if systemctl is-active --quiet "$SERVICE_PREFIX-$lp.service"; then
        echo -e "${G}🟢 Tunnel $lp ACTIVE${N}"
    else
        echo -e "${R}🔴 Tunnel $lp FAILED${N}"
        systemctl status "$SERVICE_PREFIX-$lp.service" --no-pager -l
    fi

    pause
}

list_tunnels() {
    header
    echo -e "${W}📋 SPEEF TUNNEL LIST${N}"
    line
    echo

    local f lp rip rp

    for f in "$TUNNELS"/*.conf; do
        [[ -f "$f" ]] || continue

        unset LOCAL_PORT REMOTE_IP REMOTE_PORT SSH_PORT
        source "$f"

        lp="$LOCAL_PORT"
        rip="$REMOTE_IP"
        rp="$REMOTE_PORT"

        if systemctl is-active --quiet "$SERVICE_PREFIX-$lp.service"; then
            echo -e "🇮🇷 $lp → 🌍 $rip:$rp   ${G}🟢 ACTIVE${N}"
        else
            echo -e "🇮🇷 $lp → 🌍 $rip:$rp   ${R}🔴 DOWN${N}"
        fi
    done

    [[ "$(count)" -gt 0 ]] || echo -e "${D}No tunnels configured.${N}"
    pause
}

service_action() {
    local act="$1"
    header

    local p
    read -r -p "👉 Tunnel Port: " p
    valid_port "$p" || { echo "❌ Invalid port"; pause; return; }

    local svc="$SERVICE_PREFIX-$p.service"

    systemctl cat "$svc" >/dev/null 2>&1 || {
        echo -e "${R}❌ Tunnel not found.${N}"
        pause
        return
    }

    systemctl "$act" "$svc"

    echo
    systemctl status "$svc" --no-pager -l
    pause
}

logs() {
    header

    local p
    read -r -p "👉 Tunnel Port: " p
    valid_port "$p" || { echo "❌ Invalid port"; pause; return; }

    journalctl -u "$SERVICE_PREFIX-$p.service" -n 80 --no-pager
    pause
}

remove_tunnel() {
    header

    local p
    read -r -p "👉 Tunnel Port: " p
    valid_port "$p" || { echo "❌ Invalid port"; pause; return; }

    local svc="$SERVICE_PREFIX-$p.service"

    systemctl cat "$svc" >/dev/null 2>&1 || {
        echo -e "${R}❌ Tunnel not found.${N}"
        pause
        return
    }

    read -r -p "⚠️ Remove $p? [y/N]: " ok
    [[ "$ok" =~ ^[Yy]$ ]] || return

    systemctl disable --now "$svc" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/$svc"
    rm -f "$TUNNELS/$p.conf"
    systemctl daemon-reload

    echo -e "${G}✔ Tunnel removed.${N}"
    pause
}

tunnel_menu() {
    while true; do
        header
        echo -e "${W}🔧 TUNNEL MANAGEMENT${N}"
        line
        echo
        echo " 1) ➕ Add Tunnel"
        echo " 2) 📋 List Tunnels"
        echo " 3) 🔄 Restart Tunnel"
        echo " 4) ▶️ Start Tunnel"
        echo " 5) ⏹️ Stop Tunnel"
        echo " 6) 📜 View Logs"
        echo " 7) 🩺 Tunnel Status"
        echo " 8) 🗑️ Remove Tunnel"
        echo " 9) 🔙 Back"
        echo
        read -r -p "👉 Your choice: " x

        case "$x" in
            1) add_tunnel ;;
            2) list_tunnels ;;
            3) service_action restart ;;
            4) service_action start ;;
            5) service_action stop ;;
            6) logs ;;
            7) service_action status ;;
            8) remove_tunnel ;;
            9) return ;;
            *) echo "❌ Invalid choice"; sleep 1 ;;
        esac
    done
}

info() {
    header
    echo -e "${W}📊 SERVER INFORMATION${N}"
    line
    echo
    echo "Hostname     : $(hostname)"
    echo "IPv4         : $(ip4)"
    echo "OS           : $(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")"
    echo "Kernel       : $(uname -r)"
    echo "Architecture : $(uname -m)"
    echo "Uptime       : $(uptime -p 2>/dev/null)"
    echo "Role         : $(role || echo Not-Installed)"
    echo "Tunnels      : $(count)"
    pause
}

health() {
    header
    echo -e "${W}🩺 HEALTH CHECK${N}"
    line
    echo

    command -v ssh >/dev/null &&
        echo -e "${G}🟢 SSH Client${N}" ||
        echo -e "${R}🔴 SSH Client${N}"

    systemctl is-active --quiet ssh 2>/dev/null &&
        echo -e "${G}🟢 SSH Server${N}" ||
        echo -e "${Y}🟡 SSH Server${N}"

    local f
    for f in "$TUNNELS"/*.conf; do
        [[ -f "$f" ]] || continue
        unset LOCAL_PORT
        source "$f"

        systemctl is-active --quiet "$SERVICE_PREFIX-$LOCAL_PORT.service" &&
            echo -e "${G}🟢 Tunnel $LOCAL_PORT${N}" ||
            echo -e "${R}🔴 Tunnel $LOCAL_PORT${N}"
    done

    pause
}

backup() {
    header

    mkdir -p /var/backups/speef-tunnel

    local out="/var/backups/speef-tunnel/speef-$(date +%Y%m%d-%H%M%S).tar.gz"

    tar -czf "$out" \
        "$BASE" \
        /etc/systemd/system/speef-tunnel-*.service \
        2>/dev/null || true

    echo -e "${G}✔ Backup:${N} $out"
    pause
}

uninstall() {
    header

    echo -e "${Y}⚠️ Speef Tunnel configuration and services will be removed.${N}"
    echo -e "${D}Tunnel user and SSH keys are preserved.${N}"
    echo

    read -r -p "Continue? [y/N]: " ok
    [[ "$ok" =~ ^[Yy]$ ]] || return

    local f n

    for f in /etc/systemd/system/$SERVICE_PREFIX-*.service; do
        [[ -f "$f" ]] || continue
        n="$(basename "$f")"
        systemctl disable --now "$n" >/dev/null 2>&1 || true
        rm -f "$f"
    done

    systemctl daemon-reload
    rm -rf "$BASE"

    echo -e "${G}✔ Speef Tunnel removed.${N}"
    pause
}

main() {
    while true; do
        header

        echo " 1) 📥 Install Speef Tunnel"
        echo " 2) 🔧 Tunnel Management"
        echo " 3) 📊 Server Information"
        echo " 4) 🩺 Health Check"
        echo " 5) 💾 Backup & Restore"
        echo " 6) 🔄 Update Speef Tunnel"
        echo " 7) 🧹 Uninstall"
        echo " 8) 🚪 Exit"
        echo

        read -r -p " 👉 Your choice: " x

        case "$x" in
            1) install_menu ;;
            2) tunnel_menu ;;
            3) info ;;
            4) health ;;
            5) backup ;;
            6)
                header
                echo -e "${Y}🔄 Update system will be connected to the official repository in the release build.${N}"
                pause
                ;;
            7) uninstall ;;
            8) clear; exit 0 ;;
            *) echo -e "${R}❌ Invalid choice.${N}"; sleep 1 ;;
        esac
    done
}

main
