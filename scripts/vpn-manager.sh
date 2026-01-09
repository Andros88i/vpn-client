#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# VPN CLIENT MANAGER - Termux (Sin Root)
# ============================================

CONFIG_DIR="$HOME/.vpn-client"
LOG_FILE="$CONFIG_DIR/logs/vpn.log"
ROTATE_FILE="$CONFIG_DIR/rotate.list"
ACTIVE_SERVER_FILE="$CONFIG_DIR/active_server"
KILL_SWITCH_ACTIVE=false

# =========================================================
# CONFIGURACIÓN
# =========================================================
IMG="/data/data/com.termux/files/home/storage/pictures/Anonymus.png"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Inicialización
init_setup() {
    echo -e "${BLUE}[*] Inicializando VPN Client...${NC}"
    
    mkdir -p "$CONFIG_DIR"/{configs,scripts,logs}
    
    # Crear directorio de sesión para Termux
    mkdir -p $HOME/.termux/session
    
    # Solicitar configuración inicial
    if [[ ! -f "$ROTATE_FILE" ]]; then
        echo -e "${YELLOW}[?] Creando lista de servidores para rotación${NC}"
        echo "# Formato: protocolo:ruta_config:prioridad" > "$ROTATE_FILE"
        echo "# ovpn:/path/to/config.ovpn:1" >> "$ROTATE_FILE"
        echo "# wireguard:/path/to/wg.conf:2" >> "$ROTATE_FILE"
    fi
    
    # Configurar DNS por defecto
    set_dns "9.9.9.9" "1.1.1.1"
    
    # Deshabilitar IPv6
    disable_ipv6
    
    echo -e "${GREEN}[+] Configuración inicial completada${NC}"
}

# ============================================
# KILL SWITCH con iptables (Sin Root)
# ============================================

kill_switch_enable() {
    echo -e "${BLUE}[*] Activando Kill Switch...${NC}"
    
    # Obtener interfaz activa
    LOCAL_IFACE=$(ip route | grep default | awk '{print $5}')
    TUN_IFACE="tun0"
    WG_IFACE="wg0"
    
    # Flush reglas existentes
    iptables -F
    iptables -t nat -F
    iptables -X
    iptables -t nat -X
    
    # Politicas por defecto (DROP todo)
    iptables -P INPUT DROP
    iptables -P OUTPUT DROP
    iptables -P FORWARD DROP
    
    # Permitir loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Permitir conexiones establecidas
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # DNS permitidos (Quad9 + Cloudflare)
    iptables -A OUTPUT -p udp --dport 53 -d 9.9.9.9 -j ACCEPT
    iptables -A OUTPUT -p udp --dport 53 -d 1.1.1.1 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -d 9.9.9.9 -j ACCEPT
    iptables -p tcp --dport 53 -d 1.1.1.1 -j ACCEPT
    
    # Permitir tráfico solo a través del túnel VPN
    iptables -A OUTPUT -o "$TUN_IFACE" -j ACCEPT
    iptables -A OUTPUT -o "$WG_IFACE" -j ACCEPT
    iptables -A INPUT -i "$TUN_IFACE" -j ACCEPT
    iptables -A INPUT -i "$WG_IFACE" -j ACCEPT
    
    # Bloquear todo el resto
    iptables -A OUTPUT -o "$LOCAL_IFACE" -j DROP
    
    # Registrar
    echo "$(date): Kill Switch activado" >> "$LOG_FILE"
    KILL_SWITCH_ACTIVE=true
    
    echo -e "${GREEN}[+] Kill Switch activado${NC}"
}

kill_switch_disable() {
    echo -e "${YELLOW}[*] Desactivando Kill Switch...${NC}"
    
    iptables -F
    iptables -t nat -F
    iptables -X
    iptables -t nat -X
    
    # Restaurar politicas por defecto
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    
    KILL_SWITCH_ACTIVE=false
    echo "$(date): Kill Switch desactivado" >> "$LOG_FILE"
    
    echo -e "${GREEN}[+] Kill Switch desactivado${NC}"
}

# ============================================
# OFUSCACIÓN con Shadowsocks/Stunnel
# ============================================

start_shadowsocks() {
    local config="$1"
    echo -e "${BLUE}[*] Iniciando Shadowsocks (ofuscación)...${NC}"
    
    # Verificar si el archivo de configuración existe
    if [[ ! -f "$config" ]]; then
        echo -e "${RED}[-] Configuración de Shadowsocks no encontrada${NC}"
        return 1
    fi
    
    # Iniciar Shadowsocks en segundo plano
    ss-local -c "$config" -v &
    SS_PID=$!
    
    # Configurar proxy para tráfico
    export HTTP_PROXY="socks5://127.0.0.1:1080"
    export HTTPS_PROXY="socks5://127.0.0.1:1080"
    
    echo "$SS_PID" > "$CONFIG_DIR/ss.pid"
    echo "$(date): Shadowsocks iniciado (PID: $SS_PID)" >> "$LOG_FILE"
    
    # Esperar a que esté listo
    sleep 3
    echo -e "${GREEN}[+] Shadowsocks iniciado${NC}"
}

start_stunnel() {
    local config="$1"
    echo -e "${BLUE}[*] Iniciando Stunnel (ofuscación TLS)...${NC}"
    
    stunnel "$config" &
    STUNNEL_PID=$!
    
    echo "$STUNNEL_PID" > "$CONFIG_DIR/stunnel.pid"
    echo "$(date): Stunnel iniciado (PID: $STUNNEL_PID)" >> "$LOG_FILE"
    
    sleep 2
    echo -e "${GREEN}[+] Stunnel iniciado${NC}"
}

# ============================================
# ROTACIÓN DINÁMICA DE SERVIDORES
# ============================================

rotate_server() {
    local interval=${1:-300}  # 5 minutos por defecto
    
    while true; do
        echo -e "${YELLOW}[*] Iniciando rotación cada ${interval}s...${NC}"
        
        # Obtener lista de servidores disponibles
        mapfile -t servers < <(grep -v "^#" "$ROTATE_FILE" | shuf)
        
        for server_line in "${servers[@]}"; do
            [[ -z "$server_line" ]] && continue
            
            # Parsear línea: protocolo:ruta:prioridad
            IFS=':' read -r protocol config_path priority <<< "$server_line"
            
            echo -e "${BLUE}[*] Conectando a: $(basename "$config_path")${NC}"
            
            # Detener conexión anterior
            stop_vpn
            
            # Iniciar nueva conexión según protocolo
            case "$protocol" in
                "ovpn")
                    start_openvpn "$config_path"
                    ;;
                "wireguard")
                    start_wireguard "$config_path"
                    ;;
                *)
                    echo -e "${RED}[-] Protocolo no soportado: $protocol${NC}"
                    continue
                    ;;
            esac
            
            # Esperar a que la conexión se establezca
            sleep 10
            
            # Verificar conexión
            if check_connection; then
                echo "$(date): Rotado a $config_path" >> "$LOG_FILE"
                echo "$server_line" > "$ACTIVE_SERVER_FILE"
                
                # Activar Kill Switch si no está activo
                if ! $KILL_SWITCH_ACTIVE; then
                    kill_switch_enable
                fi
                
                # Test de fugas DNS
                test_dns_leaks
            else
                echo -e "${RED}[-] Conexión fallida, rotando...${NC}"
                continue
            fi
            
            # Esperar hasta la próxima rotación
            echo -e "${GREEN}[+] Esperando $interval segundos hasta próxima rotación...${NC}"
            sleep "$interval"
        done
    done
}

# ============================================
# CLIENTES VPN
# ============================================

start_openvpn() {
    local config="$1"
    echo -e "${BLUE}[*] Iniciando OpenVPN...${NC}"
    
    # Preparar entorno para OpenVPN
    export PWD="$CONFIG_DIR"
    
    # Ejecutar OpenVPN con configuraciones especiales para Termux
    openvpn \
        --config "$config" \
        --auth-nocache \
        --user $(whoami) \
        --group $(whoami) \
        --dev tun \
        --proto udp \
        --remote-cert-tls server \
        --tls-version-min 1.2 \
        --cipher AES-256-GCM \
        --data-ciphers AES-256-GCM:AES-128-GCM \
        --auth SHA256 \
        --tun-mtu 1500 \
        --fragment 0 \
        --mssfix 0 \
        --verb 3 \
        --log "$CONFIG_DIR/logs/openvpn.log" &
    
    OVPN_PID=$!
    echo "$OVPN_PID" > "$CONFIG_DIR/openvpn.pid"
    
    echo "$(date): OpenVPN iniciado (PID: $OVPN_PID)" >> "$LOG_FILE"
    echo -e "${GREEN}[+] OpenVPN iniciado${NC}"
}

start_wireguard() {
    local config="$1"
    echo -e "${BLUE}[*] Iniciando WireGuard...${NC}"
    
    # WireGuard en Termux necesita configuración especial
    wg-quick up "$config" 2>> "$LOG_FILE"
    
    if [[ $? -eq 0 ]]; then
        echo "$(date): WireGuard iniciado" >> "$LOG_FILE"
        echo -e "${GREEN}[+] WireGuard iniciado${NC}"
    else
        echo -e "${RED}[-] Error al iniciar WireGuard${NC}"
        return 1
    fi
}

# ============================================
# CONFIGURACIÓN DNS Y SEGURIDAD
# ============================================

set_dns() {
    local dns1="$1"
    local dns2="$2"
    
    echo -e "${BLUE}[*] Configurando DNS: $dns1, $dns2${NC}"
    
    # Configurar resolv.conf
    echo "nameserver $dns1" > /data/data/com.termux/files/usr/etc/resolv.conf
    echo "nameserver $dns2" >> /data/data/com.termux/files/usr/etc/resolv.conf
    
    # Configurar mediante ndc (si está disponible)
    if command -v ndc &> /dev/null; then
        ndc resolver setnetdns \"\" \"$dns1\" \"$dns2\"
    fi
    
    echo "$(date): DNS configurado a $dns1, $dns2" >> "$LOG_FILE"
}

disable_ipv6() {
    echo -e "${BLUE}[*] Deshabilitando IPv6...${NC}"
    
    # Deshabilitar IPv6 en todas las interfaces
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
    echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null || true
    
    # Bloquear IPv6 con iptables
    ip6tables -P INPUT DROP 2>/dev/null || true
    ip6tables -P OUTPUT DROP 2>/dev/null || true
    ip6tables -P FORWARD DROP 2>/dev/null || true
    
    echo "$(date): IPv6 deshabilitado" >> "$LOG_FILE"
    echo -e "${GREEN}[+] IPv6 deshabilitado${NC}"
}

# ============================================
# MONITOREO Y VERIFICACIÓN
# ============================================

check_connection() {
    # Verificar conectividad a múltiples fuentes
    local test_urls=(
        "https://api.ipify.org"
        "https://icanhazip.com"
        "https://checkip.amazonaws.com"
    )
    
    for url in "${test_urls[@]}"; do
        if curl -s --connect-timeout 10 --max-time 15 "$url" &> /dev/null; then
            echo -e "${GREEN}[+] Conexión activa${NC}"
            return 0
        fi
    done
    
    echo -e "${RED}[-] Sin conexión${NC}"
    return 1
}

test_dns_leaks() {
    echo -e "${BLUE}[*] Testeando fugas DNS...${NC}"
    
    # Usar dnsleaktest.com API
    curl -s https://www.dnsleaktest.com/api/request | jq . 2>/dev/null
    
    # Test simple
    local result=$(dig +short whoami.akamai.net @9.9.9.9)
    if [[ -n "$result" ]]; then
        echo -e "${GREEN}[+] DNS configurado correctamente${NC}"
        echo "$(date): DNS test passed: $result" >> "$LOG_FILE"
    else
        echo -e "${RED}[-] Posible fuga DNS detectada${NC}"
        echo "$(date): Posible fuga DNS" >> "$LOG_FILE"
    fi
}

monitor_connection() {
    echo -e "${BLUE}[*] Iniciando monitor de conexión...${NC}"
    
    while true; do
        if ! check_connection; then
            echo -e "${RED}[!] VPN caída, activando contingencia...${NC}"
            
            # Intentar reconexión automática
            stop_vpn
            sleep 5
            
            # Obtener último servidor activo
            if [[ -f "$ACTIVE_SERVER_FILE" ]]; then
                IFS=':' read -r protocol config_path priority < "$ACTIVE_SERVER_FILE"
                case "$protocol" in
                    "ovpn") start_openvpn "$config_path" ;;
                    "wireguard") start_wireguard "$config_path" ;;
                esac
            fi
            
            # Forzar Kill Switch si es necesario
            kill_switch_enable
        fi
        
        sleep 30
    done
}

# ============================================
# FUNCIONES DE CONTROL PRINCIPAL
# ============================================

stop_vpn() {
    echo -e "${YELLOW}[*] Deteniendo todas las conexiones VPN...${NC}"
    
    # Detener OpenVPN
    if [[ -f "$CONFIG_DIR/openvpn.pid" ]]; then
        kill -TERM $(cat "$CONFIG_DIR/openvpn.pid") 2>/dev/null
        rm "$CONFIG_DIR/openvpn.pid"
    fi
    
    # Detener WireGuard
    wg-quick down $(ls "$CONFIG_DIR/configs/"*.conf 2>/dev/null | head -1) 2>/dev/null || true
    
    # Detener servicios de ofuscación
    if [[ -f "$CONFIG_DIR/ss.pid" ]]; then
        kill -TERM $(cat "$CONFIG_DIR/ss.pid") 2>/dev/null
        rm "$CONFIG_DIR/ss.pid"
    fi
    
    if [[ -f "$CONFIG_DIR/stunnel.pid" ]]; then
        kill -TERM $(cat "$CONFIG_DIR/stunnel.pid") 2>/dev/null
        rm "$CONFIG_DIR/stunnel.pid"
    fi
    
    echo "$(date): Todas las conexiones VPN detenidas" >> "$LOG_FILE"
    echo -e "${GREEN}[+] Conexiones VPN detenidas${NC}"
}

start_all() {
    local rotation_interval="$1"
    
    clear

if command -v chafa >/dev/null 2>&1 && [ -f "$IMG" ]; then
    chafa --center=on --size=60x30 "$IMG"
else
    echo -e "${RED}[!] No se pudo cargar la imagen o chafa no está instalado${NC}"
fi

echo
echo -e "${LRED}      [+] CREADOR : Andro_Os${NC}"
echo -e "${LRED}      [+] PROYECTO: VPN${NC}"
echo -e "${LRED}      [+] ESTADO  : ${GREEN}ACTIVO${NC}"
echo -e "${LRED}=================================================${NC}"
    
    # Inicializar
    init_setup
    
    # Iniciar ofuscación (opcional)
    if [[ -f "$CONFIG_DIR/configs/shadowsocks.json" ]]; then
        start_shadowsocks "$CONFIG_DIR/configs/shadowsocks.json"
    fi
    
    # Iniciar rotación en segundo plano
    rotate_server "$rotation_interval" &
    ROTATE_PID=$!
    
    # Iniciar monitor en segundo plano
    monitor_connection &
    MONITOR_PID=$!
    
    echo "$ROTATE_PID" > "$CONFIG_DIR/rotate.pid"
    echo "$MONITOR_PID" > "$CONFIG_DIR/monitor.pid"
    
    echo -e "${GREEN}[+] Sistema completamente operativo${NC}"
    echo -e "${YELLOW}[i] PIDs: Rotación=$ROTATE_PID, Monitor=$MONITOR_PID${NC}"
    echo -e "${YELLOW}[i] Ver logs: tail -f $LOG_FILE${NC}"
}

cleanup() {
    echo -e "${RED}[!] Limpiando y saliendo...${NC}"
    
    stop_vpn
    kill_switch_disable
    
    # Matar procesos en segundo plano
    for pid_file in "$CONFIG_DIR"/*.pid; do
        [[ -f "$pid_file" ]] && kill -TERM $(cat "$pid_file") 2>/dev/null
        rm -f "$pid_file"
    done
    
    echo "$(date): Sistema detenido" >> "$LOG_FILE"
    exit 0
}

# ============================================
# MENÚ INTERACTIVO
# ============================================

show_menu() {
    echo -e "\n${BLUE}=== VPN Client Manager ===${NC}"
    echo "1. Iniciar sistema completo (con rotación)"
    echo "2. Detener todo"
    echo "3. Test de fugas DNS"
    echo "4. Ver estado de conexión"
    echo "5. Ver logs"
    echo "6. Configurar servidores"
    echo "7. Activar/Desactivar Kill Switch"
    echo "8. Salir"
    echo -n "Seleccione opción: "
}

# ============================================
# MAIN
# ============================================

trap cleanup SIGINT SIGTERM

case "$1" in
    "start")
        start_all "${2:-300}"
        ;;
    "stop")
        cleanup
        ;;
    "menu")
        while true; do
            show_menu
            read choice
            case $choice in
                1) start_all "300" ;;
                2) cleanup ;;
                3) test_dns_leaks ;;
                4) check_connection ;;
                5) tail -f "$LOG_FILE" ;;
                6) nano "$ROTATE_FILE" ;;
                7) 
                    if $KILL_SWITCH_ACTIVE; then
                        kill_switch_disable
                    else
                        kill_switch_enable
                    fi
                    ;;
                8) cleanup ;;
                *) echo "Opción inválida" ;;
            esac
        done
        ;;
    *)
        echo "Uso: $0 {start|stop|menu}"
        echo "Ejemplo: $0 start 600  (rotación cada 10 minutos)"
        exit 1
        ;;
esac
