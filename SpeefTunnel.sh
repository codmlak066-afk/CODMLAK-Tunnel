#!/usr/bin/env bash

set -u

APP="CODMLAK SPEEF TUNNEL"
CORE="/root/speef-tunnel-v1/core/bin/speef-core"
BASE="/etc/speef/tunnels"
SERVICE="speef-core"
BACKUP="/var/backups/speef-tunnel"

mkdir -p "$BASE" "$BACKUP"

red(){ printf '\033[31m%s\033[0m\n' "$1"; }
green(){ printf '\033[32m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$1"; }

valid_port(){
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

valid_ip(){
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

valid_target(){
    [[ "$1" =~ ^[^:]+:[0-9]+$ ]]
}

pause(){
    echo
    read -r -p "Press Enter to continue..." _
}

role="$(cat /etc/speef/role 2>/dev/null || true)"

if [[ "$role" != "iran" && "$role" != "kharej" ]]; then
    echo
    echo "Select Server Role:"
    echo
    echo "  1) 🇮🇷 Iran (Server)"
    echo "  2) 🌍 Kharej (Client)"
    echo
    read -r -p "Select [1-2]: " r

    case "$r" in
        1) role="iran" ;;
        2) role="kharej" ;;
        *) red "Invalid selection."; exit 1 ;;
    esac

    mkdir -p /etc/speef
    echo "$role" > /etc/speef/role
fi

create_tunnel(){

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "             ➕ CREATE TUNNEL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    read -r -p "Tunnel Port (1-65535): " port

    if ! valid_port "$port"; then
        red "Invalid port."
        return
    fi

    config="$BASE/$port.json"

    if [[ -f "$config" ]]; then
        red "Tunnel $port already exists."
        return
    fi

    if ss -lntH | awk '{print $4}' | grep -Eq "([:.])$port$"; then
        red "Port $port is already listening."
        return
    fi

    if [[ "$role" == "iran" ]]; then

        read -r -p "Kharej Server IP: " remote

        if ! valid_ip "$remote"; then
            red "Invalid IP."
            return
        fi

        read -r -s -p "Tunnel Token: " token
        echo

        [[ -n "$token" ]] || { red "Token cannot be empty."; return; }

        cat > "$config" <<EOF
{
  "role": "server",
  "listen": "0.0.0.0",
  "remote": "$remote",
  "target": "",
  "tunnel_port": $port,
  "token": "$token",
  "connection_pool": 8,
  "keepalive": 20,
  "retry_interval": 2,
  "timeout": 10,
  "mode": "tcp"
}
EOF

    else

        read -r -p "Iran Server IP: " remote

        if ! valid_ip "$remote"; then
            red "Invalid IP."
            return
        fi

        read -r -p "Local Target (IP:PORT): " target

        if ! valid_target "$target"; then
            red "Invalid target. Example: 127.0.0.1:35650"
            return
        fi

        read -r -s -p "Tunnel Token: " token
        echo

        [[ -n "$token" ]] || { red "Token cannot be empty."; return; }

        cat > "$config" <<EOF
{
  "role": "client",
  "listen": "",
  "remote": "$remote",
  "target": "$target",
  "tunnel_port": $port,
  "token": "$token",
  "connection_pool": 8,
  "keepalive": 20,
  "retry_interval": 2,
  "timeout": 10,
  "mode": "tcp"
}
EOF

    fi

    chmod 600 "$config"

    systemctl daemon-reload
    systemctl enable --now "$SERVICE@$port.service"

    echo
    green "✅ Tunnel created."
    echo "Port: $port"
}

tunnel_list(){

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "              📋 TUNNEL LIST"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    found=0

    for config in "$BASE"/*.json; do
        [[ -f "$config" ]] || continue

        found=1
        port="$(basename "$config" .json)"

        if systemctl is-active --quiet "$SERVICE@$port.service"; then
            status="🟢 ACTIVE"
        else
            status="🔴 DOWN"
        fi

        echo "Port $port : $status"
    done

    [[ "$found" == "1" ]] || yellow "No tunnels found."
}

tunnel_status(){

    read -r -p "Tunnel Port: " port

    if ! valid_port "$port"; then
        red "Invalid port."
        return
    fi

    systemctl --no-pager --full status "$SERVICE@$port.service"
}

restart_tunnel(){

    read -r -p "Tunnel Port: " port

    valid_port "$port" || { red "Invalid port."; return; }

    systemctl restart "$SERVICE@$port.service"

    if systemctl is-active --quiet "$SERVICE@$port.service"; then
        green "✅ Tunnel restarted."
    else
        red "❌ Tunnel failed."
    fi
}

stop_tunnel(){

    read -r -p "Tunnel Port: " port

    valid_port "$port" || { red "Invalid port."; return; }

    systemctl stop "$SERVICE@$port.service"
    green "🛑 Tunnel stopped."
}

delete_tunnel(){

    read -r -p "Tunnel Port: " port

    valid_port "$port" || { red "Invalid port."; return; }

    config="$BASE/$port.json"

    [[ -f "$config" ]] || { red "Tunnel not found."; return; }

    echo
    yellow "This will delete tunnel $port."
    read -r -p "Confirm [y/N]: " confirm

    [[ "$confirm" == "y" || "$confirm" == "Y" ]] || {
        yellow "Cancelled."
        return
    }

    systemctl disable --now "$SERVICE@$port.service" 2>/dev/null || true
    rm -f "$config"

    green "🗑️ Tunnel deleted."
}

view_logs(){

    read -r -p "Tunnel Port: " port

    valid_port "$port" || { red "Invalid port."; return; }

    journalctl -u "$SERVICE@$port.service" -n 100 --no-pager
}

optimize(){

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "               ⚡ OPTIMIZE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    cat > /etc/sysctl.d/99-speef-tunnel.conf <<'EOF'
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
EOF

    sysctl --system >/dev/null 2>&1

    green "✅ BBR enabled."
    green "✅ TCP Fast Open enabled."
    green "✅ Settings saved permanently."
}

backup(){

    mkdir -p "$BACKUP"

    timestamp="$(date +%Y%m%d_%H%M%S)"
    file="$BACKUP/speef-$timestamp.tar.gz"

    tar -czf "$file" \
        /etc/speef/tunnels \
        /etc/speef/role \
        /etc/systemd/system/speef-core@.service \
        /etc/sysctl.d/99-speef-tunnel.conf \
        2>/dev/null || true

    green "✅ Backup created:"
    echo "$file"
}

health(){

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "              📊 SYSTEM HEALTH"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    if [[ -x "$CORE" ]]; then
        green "🟢 Speef Core: FOUND"
    else
        red "🔴 Speef Core: NOT FOUND"
    fi

    echo "Role: $role"
    echo "Core: $CORE"
    echo

    echo "Active tunnels:"
    systemctl list-units \
        --type=service \
        --state=running \
        'speef-core@*' \
        --no-legend 2>/dev/null || true
}

update(){

    echo
    yellow "Update is not enabled yet."
    yellow "GitHub release/update system will be added after the final core release."
}

menu(){

    while true; do

        clear

        echo "╔══════════════════════════════════════╗"
        echo "║       🚀 CODMLAK SPEEF TUNNEL       ║"

        if [[ "$role" == "iran" ]]; then
            echo "║                🇮🇷 IRAN             ║"
        else
            echo "║               🌍 KHAREJ             ║"
        fi

        echo "╚══════════════════════════════════════╝"
        echo
        echo "  1) ➕ Create Tunnel"
        echo "  2) 📋 Tunnel List"
        echo "  3) 📊 Tunnel Status"
        echo "  4) 🔄 Restart Tunnel"
        echo "  5) 🛑 Stop Tunnel"
        echo "  6) 🗑️ Delete Tunnel"
        echo "  7) 📜 View Logs"
        echo "  8) ⚡ Optimize"
        echo "  9) 💾 Backup"
        echo " 10) ❤️ Health"
        echo " 11) 🔄 Update"
        echo "  0) Exit"
        echo

        read -r -p "Select an option: " option

        case "$option" in
            1) create_tunnel ;;
            2) tunnel_list ;;
            3) tunnel_status ;;
            4) restart_tunnel ;;
            5) stop_tunnel ;;
            6) delete_tunnel ;;
            7) view_logs ;;
            8) optimize ;;
            9) backup ;;
            10) health ;;
            11) update ;;
            0) exit 0 ;;
            *) red "Invalid option." ;;
        esac

        pause
    done
}

if [[ ! -x "$CORE" ]]; then
    red "❌ Speef Core not found:"
    echo "$CORE"
    exit 1
fi

menu
