#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# KILL SWITCH AVANZADO PARA TERMUX
# Bloquea todo el tráfico excepto a través de la VPN
# ==============================================================================

CONFIG_DIR="$HOME/.vpn-client"
WHITELIST_FILE="$CONFIG_DIR/whitelist.txt"
LOG_FILE="$CONFIG_DIR/logs/killswitch.log"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "${BLUE}[Kill Switch]${NC} $2"
}

get_active_interface() {
    ip route | grep default | awk '{print $5}' | head -1
}

flush_rules() {
    log "Limpiando reglas iptables" "🧹 Limpiando reglas..."
    
    # IPv4
    iptables -F
    iptables -t nat -F
    iptables -X
    iptables -t nat -X
    
    # IPv6
    ip6tables -F 2>/dev/null || true
    ip6tables -t nat -F 2>/dev/null || true
    ip6tables -X 2>/dev/null || true
    ip6tables -t nat -X 2>/dev/null || true
    
    # Restaurar políticas por defecto
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    
    log "Reglas limpiadas" "✅ Reglas limpiadas"
}

apply_kill_switch() {
    local local_iface=$(get_active_interface)
    local vpn_ifaces="tun0 wg0"
    
    log "Aplicando Kill Switch" "🛡️  Aplicando reglas..."
    
    # Limpiar primero
    flush_rules
    
    # ================= CONFIGURACIÓN IPv4 =================
    
    # Políticas por defecto (DROP todo)
    iptables -P INPUT DROP
    iptables -P OUTPUT DROP
    iptables -P FORWARD DROP
    
    # ============ REGLAS DE ENTRADA (INPUT) ==============
    
    # Loopback
    iptables -A INPUT -i lo -j ACCEPT
    
    # Conexiones establecidas y relacionadas
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # Interfaces VPN
    for iface in $vpn_ifaces; do
        iptables -A INPUT -i "$iface" -j ACCEPT
    done
    
    # Redes de la whitelist
    while IFS= read -r line; do
        [[ "$line" =~ ^IP: ]] || continue
        local network=$(echo "$line" | cut -d: -f2)
        iptables -A INPUT -s "$network" -j ACCEPT
        log "Whitelist input: $network" "➕ Permitir entrada: $network"
    done < "$WHITELIST_FILE"
    
    # ============ REGLAS DE SALIDA (OUTPUT) ==============
    
    # Loopback
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Conexiones establecidas y relacionadas
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # DNS permitidos (Quad9 + Cloudflare)
    local dns_servers=("9.9.9.9" "1.1.1.1" "149.112.112.112" "1.0.0.1")
    for dns in "${dns_servers[@]}"; do
        iptables -A OUTPUT -d "$dns" -p udp --dport 53 -j ACCEPT
        iptables -A OUTPUT -d "$dns" -p tcp --dport 53 -j ACCEPT
        log "DNS permitido: $dns" "🌐 DNS: $dns"
    done
    
    # Interfaces VPN
    for iface in $vpn_ifaces; do
        iptables -A OUTPUT -o "$iface" -j ACCEPT
    done
    
    # Redes de la whitelist
    while IFS= read -r line; do
        [[ "$line" =~ ^IP: ]] || continue
        local network=$(echo "$line" | cut -d: -f2)
        iptables -A OUTPUT -d "$network" -j ACCEPT
        log "Whitelist output: $network" "➕ Permitir salida: $network"
    done < "$WHITELIST_FILE"
    
    # ============ BLOQUEO FINAL ==============
    
    # Bloquear todo el tráfico saliente por la interfaz local
    if [[ -n "$local_iface" ]]; then
        iptables -A OUTPUT -o "$local_iface" -j DROP
        log "Bloqueando interfaz local" "🚫 Bloqueado: $local_iface"
    fi
    
    # ================= CONFIGURACIÓN IPv6 =================
    
    # Deshabilitar completamente IPv6
    ip6tables -P INPUT DROP 2>/dev/null || true
    ip6tables -P OUTPUT DROP 2>/dev/null || true
    ip6tables -P FORWARD DROP 2>/dev/null || true
    
    # ============ REGLAS ADICIONALES DE SEGURIDAD ==============
    
    # Protección contra spoofing
    iptables -A INPUT -s 127.0.0.0/8 ! -i lo -j DROP
    iptables -A INPUT -s 0.0.0.0/8 -j DROP
    iptables -A INPUT -s 169.254.0.0/16 -j DROP
    iptables -A INPUT -s 192.0.2.0/24 -j DROP
    iptables -A INPUT -s 224.0.0.0/4 -j DROP
    iptables -A INPUT -s 240.0.0.0/5 -j DROP
    
    # Rate limiting para conexiones nuevas
    iptables -A INPUT -p tcp --syn -m limit --limit 10/second --limit-burst 20 -j ACCEPT
    iptables -A INPUT -p tcp --syn -j DROP
    
    log "Kill Switch aplicado" "✅ Kill Switch activado exitosamente"
    
    # Mostrar resumen
    show_status
}

show_status() {
    echo -e "\n${GREEN}=== ESTADO KILL SWITCH ===${NC}"
    echo ""
    
    # Mostrar políticas
    echo -e "${YELLOW}Políticas IPv4:${NC}"
    iptables -S | grep "^\-P"
    
    echo -e "\n${YELLOW}Reglas OUTPUT:${NC}"
    iptables -L OUTPUT -n --line-numbers
    
    echo -e "\n${YELLOW}Interfaz local:${NC} $(get_active_interface)"
    
    # Verificar VPN activa
    if ip link show | grep -q "tun0\|wg0"; then
        echo -e "${YELLOW}Interfaces VPN:${NC}"
        ip link show | grep -E "(tun0|wg0)" | awk '{print "  " $2 " " $3}'
    else
        echo -e "${RED}⚠️  No hay interfaces VPN activas${NC}"
    fi
}

disable_kill_switch() {
    log "Desactivando Kill Switch" "🔓 Desactivando..."
    
    flush_rules
    
    # Restaurar IPv6
    ip6tables -P INPUT ACCEPT 2>/dev/null || true
    ip6tables -P OUTPUT ACCEPT 2>/dev/null || true
    ip6tables -P FORWARD ACCEPT 2>/dev/null || true
    
    log "Kill Switch desactivado" "✅ Kill Switch desactivado"
}

check_leaks() {
    echo -e "\n${BLUE}=== TEST DE FUGAS ===${NC}"
    
    # Test DNS
    echo -e "\n${YELLOW}Test DNS:${NC}"
    local dns_result=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
    if [[ -n "$dns_result" ]]; then
        echo -e "  ${RED}⚠️  Posible fuga DNS: $dns_result${NC}"
    else
        echo -e "  ${GREEN}✅ DNS seguro${NC}"
    fi
    
    # Test Web
    echo -e "\n${YELLOW}Test Web:${NC}"
    local web_result=$(curl -s --connect-timeout 5 https://api.ipify.org)
    if [[ -n "$web_result" ]]; then
        echo -e "  IP visible: $web_result"
    fi
    
    # Test IPv6
    echo -e "\n${YELLOW}Test IPv6:${NC}"
    if ping6 -c 1 ipv6.google.com 2>/dev/null | grep -q "bytes from"; then
        echo -e "  ${RED}⚠️  IPv6 activo${NC}"
    else
        echo -e "  ${GREEN}✅ IPv6 bloqueado${NC}"
    fi
}

case "${1:-status}" in
    "start"|"enable"|"on")
        apply_kill_switch
        ;;
    "stop"|"disable"|"off")
        disable_kill_switch
        ;;
    "status")
        show_status
        ;;
    "test")
        check_leaks
        ;;
    "flush")
        flush_rules
        ;;
    *)
        echo "Uso: $0 {start|stop|status|test|flush}"
        echo "  start/enable/on  - Activar Kill Switch"
        echo "  stop/disable/off - Desactivar Kill Switch"
        echo "  status           - Ver estado actual"
        echo "  test             - Test de fugas"
        echo "  flush            - Limpiar todas las reglas"
        exit 1
        ;;
esac
