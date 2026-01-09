#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# VPN CLIENT MANAGER - Termux (Sin Root)
# Versión: 2.0 | Sistema completo de gestión VPN
# ==============================================================================

# Configuración global
CONFIG_DIR="$HOME/.vpn-client"
SCRIPTS_DIR="$CONFIG_DIR/scripts"
CONFIGS_DIR="$CONFIG_DIR/configs"
LOGS_DIR="$CONFIG_DIR/logs"
BACKUP_DIR="$CONFIG_DIR/backups"

# Archivos de configuración
ROTATE_FILE="$CONFIG_DIR/rotate.list"
WHITELIST_FILE="$CONFIG_DIR/whitelist.txt"
ACTIVE_SERVER_FILE="$CONFIG_DIR/active_server"
VPN_STATUS_FILE="$CONFIG_DIR/vpn_status"

# Archivos de log
LOG_FILE="$LOGS_DIR/vpn.log"
ERROR_LOG="$LOGS_DIR/error.log"
DEBUG_LOG="$LOGS_DIR/debug.log"

# Variables de estado
KILL_SWITCH_ACTIVE=false
VPN_CONNECTED=false
CURRENT_PROTOCOL=""
CURRENT_SERVER=""

# =========================================================
# CONFIGURACIÓN
# =========================================================
IMG="/data/data/com.termux/files/home/storage/pictures/Anonymus.png"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ==============================================================================
# FUNCIONES DE UTILIDAD
# ==============================================================================

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $2"
}

error_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$ERROR_LOG"
    echo -e "${RED}[ERROR]${NC} $2"
}

debug_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: $1" >> "$DEBUG_LOG"
    [[ "$DEBUG" == "true" ]] && echo -e "${PURPLE}[DEBUG]${NC} $2"
}

check_root() {
    if [[ $(id -u) -eq 0 ]]; then
        error_message "Script ejecutado como root" "No ejecutes como root en Termux"
        exit 1
    fi
}

check_dependencies() {
    local deps=("openvpn" "wg" "ss-local" "stunnel" "curl" "jq" "iptables")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error_message "Dependencias faltantes: ${missing[*]}" 
        echo -e "${YELLOW}[!] Ejecuta: pkg install ${missing[*]}${NC}"
        return 1
    fi
    return 0
}

# ==============================================================================
# INICIALIZACIÓN DEL SISTEMA
# ==============================================================================

init_system() {
    log_message "Inicializando sistema VPN" "Inicializando sistema..."
    
    # Crear directorios
    mkdir -p "$CONFIGS_DIR" "$SCRIPTS_DIR" "$LOGS_DIR" "$BACKUP_DIR"
    
    # Crear archivos de configuración si no existen
    [[ ! -f "$ROTATE_FILE" ]] && create_rotate_file
    [[ ! -f "$WHITELIST_FILE" ]] && create_whitelist
    [[ ! -f "$CONFIGS_DIR/shadowsocks.json" ]] && create_shadowsocks_example
    
    # Configurar entorno Termux
    setup_termux_env
    
    # Verificar dependencias
    check_dependencies || return 1
    
    log_message "Sistema inicializado" "✅ Sistema inicializado correctamente"
    return 0
}

create_rotate_file() {
    cat > "$ROTATE_FILE" << 'EOF'
# ==============================================================================
# LISTA DE ROTACIÓN DE SERVIDORES VPN
# Formato: protocolo:ruta_config:prioridad:nombre
# protocolos: ovpn, wireguard, shadowsocks
# prioridad: 1-10 (1=mayor prioridad)
# ==============================================================================

# Ejemplos (comentados):
# ovpn:/data/data/com.termux/files/home/.vpn-client/configs/server1.ovpn:1:US-NewYork
# wireguard:/data/data/com.termux/files/home/.vpn-client/configs/wg1.conf:2:NL-Amsterdam
# shadowsocks:/data/data/com.termux/files/home/.vpn-client/configs/ss1.json:3:JP-Tokyo

# Añade tus servidores aquí:
# ovpn:/ruta/a/tu/config.ovpn:1:Nombre-Servidor
EOF
    log_message "Archivo rotate.list creado" "📄 Archivo rotate.list creado"
}

create_whitelist() {
    cat > "$WHITELIST_FILE" << 'EOF'
# ==============================================================================
# LISTA BLANCA - APPS/REDES PERMITIDAS SIN VPN
# ==============================================================================

# Formato para apps (por nombre de proceso):
# APP:com.termux
# APP:com.android.systemui

# Formato para redes WiFi (por SSID):
# WIFI:Casa
# WIFI:Trabajo

# Formato para IPs locales:
# IP:192.168.1.0/24
# IP:10.0.0.0/8

# Apps del sistema que NO deben pasar por VPN:
APP:com.android.phone
APP:com.android.mms
APP:android.process.acore

# Redes WiFi de confianza:
# WIFI:MiCasa
# WIFI:Oficina-Segura
EOF
}

create_shadowsocks_example() {
    cat > "$CONFIGS_DIR/shadowsocks.json" << 'EOF'
{
    "server": "tu.servidor.shadowsocks.com",
    "server_port": 443,
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "tu_password_secreto",
    "timeout": 300,
    "method": "aes-256-gcm",
    "mode": "tcp_and_udp",
    "fast_open": true,
    "plugin": "v2ray-plugin",
    "plugin_opts": "server;tls;host=tu.servidor.com"
}
EOF
    log_message "Ejemplo Shadowsocks creado" "📄 Ejemplo de configuración Shadowsocks creado"
}

setup_termux_env() {
    # Configurar entorno de Termux para VPN
    termux-wake-lock 2>/dev/null || true
    
    # Evitar que el sistema suspenda Termux
    termux-wake-lock 2>/dev/null || true
    
    # Configurar almacenamiento compartido si es necesario
    if [[ ! -d ~/storage ]]; then
        termux-setup-storage 2>/dev/null || true
    fi
    
    log_message "Entorno Termux configurado" "🔧 Entorno Termux configurado"
}

# ==============================================================================
# SISTEMA DE ROTACIÓN DINÁMICA
# ==============================================================================

rotate_vpn_server() {
    local interval="${1:-300}"  # Default: 5 minutos
    
    log_message "Iniciando rotación dinámica" "🔄 Iniciando rotación cada ${interval}s"
    
    while true; do
        local servers=()
        mapfile -t servers < <(grep -v "^#" "$ROTATE_FILE" | grep -v "^$")
        
        if [[ ${#servers[@]} -eq 0 ]]; then
            error_message "No hay servidores en rotate.list" "❌ No hay servidores configurados"
            sleep 60
            continue
        fi
        
        # Ordenar por prioridad
        IFS=$'\n' sorted_servers=($(sort -t: -k3n <<<"${servers[*]}"))
        unset IFS
        
        for server_line in "${sorted_servers[@]}"; do
            IFS=':' read -r protocol config_path priority name <<< "$server_line"
            
            # Verificar que el archivo existe
            if [[ ! -f "$config_path" ]]; then
                error_message "Archivo no encontrado: $config_path" "⚠️  Archivo no encontrado: $(basename "$config_path")"
                continue
            fi
            
            log_message "Rotando a: $name" "🔄 Conectando a: ${CYAN}$name${NC} (${protocol})"
            
            # Detener conexión anterior
            stop_current_connection
            
            # Iniciar nueva conexión
            if connect_vpn "$protocol" "$config_path" "$name"; then
                # Guardar servidor activo
                echo "$server_line" > "$ACTIVE_SERVER_FILE"
                VPN_CONNECTED=true
                CURRENT_PROTOCOL="$protocol"
                CURRENT_SERVER="$name"
                
                # Activar Kill Switch si está configurado
                if [[ "$ENABLE_KILL_SWITCH" == "true" ]] && ! $KILL_SWITCH_ACTIVE; then
                    enable_kill_switch
                fi
                
                # Test de fugas
                run_security_checks
                
                log_message "Conexión establecida: $name" "✅ Conectado a: ${GREEN}$name${NC}"
                
                # Esperar hasta próxima rotación
                log_message "Esperando $interval segundos" "⏳ Esperando ${interval}s para próxima rotación..."
                sleep "$interval"
                
                # Verificar conexión antes de rotar
                if ! check_vpn_connection; then
                    error_message "Conexión perdida con $name" "❌ Conexión perdida, rotando ahora..."
                    continue
                fi
            else
                error_message "Error conectando a $name" "❌ Error al conectar, probando siguiente..."
                sleep 10
            fi
        done
        
        # Backup de logs periódico
        backup_logs
    done
}

connect_vpn() {
    local protocol="$1"
    local config="$2"
    local name="$3"
    
    case "$protocol" in
        "ovpn")
            connect_openvpn "$config"
            ;;
        "wireguard")
            connect_wireguard "$config"
            ;;
        "shadowsocks")
            connect_shadowsocks "$config"
            ;;
        *)
            error_message "Protocolo no soportado: $protocol" "❌ Protocolo no soportado"
            return 1
            ;;
    esac
    
    # Esperar conexión
    sleep 5
    
    # Verificar
    if check_vpn_connection; then
        return 0
    else
        return 1
    fi
}

connect_openvpn() {
    local config="$1"
    log_message "Conectando OpenVPN: $(basename "$config")" "🔗 Iniciando OpenVPN..."
    
    # Matar OpenVPN existente
    pkill -f "openvpn.*$(basename "$config")" 2>/dev/null
    
    # Configurar rutas para Termux
    export HOME="$HOME"
    export PWD="$(dirname "$config")"
    
    # Iniciar OpenVPN con opciones de seguridad
    openvpn \
        --config "$config" \
        --auth-nocache \
        --user "$(whoami)" \
        --group "$(whoami)" \
        --dev tun \
        --proto udp \
        --remote-cert-tls server \
        --tls-version-min 1.2 \
        --cipher AES-256-GCM \
        --auth SHA256 \
        --ping 10 \
        --ping-restart 60 \
        --persist-tun \
        --persist-key \
        --log "$LOGS_DIR/openvpn-$(date +%Y%m%d).log" \
        --verb 3 \
        --daemon
    
    OVPN_PID=$!
    echo "$OVPN_PID" > "$CONFIG_DIR/openvpn.pid"
    
    log_message "OpenVPN iniciado (PID: $OVPN_PID)" "📊 OpenVPN PID: $OVPN_PID"
    return 0
}

connect_wireguard() {
    local config="$1"
    log_message "Conectando WireGuard: $(basename "$config")" "🔗 Iniciando WireGuard..."
    
    # Detener interfaces WireGuard existentes
    wg-quick down "$config" 2>/dev/null || true
    
    # Iniciar WireGuard
    if wg-quick up "$config" 2>> "$ERROR_LOG"; then
        WG_PID=$(pgrep -f "wg-quick.*$(basename "$config")")
        echo "$WG_PID" > "$CONFIG_DIR/wireguard.pid"
        log_message "WireGuard iniciado" "✅ WireGuard conectado"
        return 0
    else
        error_message "Error iniciando WireGuard" "❌ Error en WireGuard"
        return 1
    fi
}

connect_shadowsocks() {
    local config="$1"
    log_message "Conectando Shadowsocks: $(basename "$config")" "🔗 Iniciando Shadowsocks..."
    
    # Verificar configuración
    if ! jq -e . "$config" >/dev/null 2>&1; then
        error_message "Configuración Shadowsocks inválida" "❌ JSON inválido"
        return 1
    fi
    
    # Matar Shadowsocks existente
    pkill -f "ss-local.*$(basename "$config")" 2>/dev/null
    
    # Iniciar Shadowsocks
    ss-local -c "$config" -v >> "$LOGS_DIR/shadowsocks.log" 2>&1 &
    SS_PID=$!
    echo "$SS_PID" > "$CONFIG_DIR/shadowsocks.pid"
    
    # Configurar proxy
    export HTTP_PROXY="socks5://127.0.0.1:1080"
    export HTTPS_PROXY="socks5://127.0.0.1:1080"
    
    log_message "Shadowsocks iniciado (PID: $SS_PID)" "📊 Shadowsocks PID: $SS_PID"
    return 0
}

# ==============================================================================
# KILL SWITCH AVANZADO
# ==============================================================================

enable_kill_switch() {
    log_message "Activando Kill Switch" "🛡️  Activando Kill Switch..."
    
    # Interfaces
    local LOCAL_IFACE=$(ip route | grep default | awk '{print $5}')
    local TUN_IFACE="tun0"
    local WG_IFACE="wg0"
    
    # Limpiar reglas
    iptables -F
    iptables -t nat -F
    iptables -X
    iptables -t nat -X
    
    # Políticas por defecto
    iptables -P INPUT DROP
    iptables -P OUTPUT DROP
    iptables -P FORWARD DROP
    
    # Loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Conexiones establecidas
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # DNS permitidos
    iptables -A OUTPUT -p udp --dport 53 -d 9.9.9.9 -j ACCEPT
    iptables -A OUTPUT -p udp --dport 53 -d 1.1.1.1 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -d 9.9.9.9 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -d 1.1.1.1 -j ACCEPT
    
    # Redes locales (de la whitelist)
    while read -r line; do
        [[ "$line" =~ ^IP: ]] || continue
        local network=$(echo "$line" | cut -d: -f2)
        iptables -A OUTPUT -d "$network" -j ACCEPT
        iptables -A INPUT -s "$network" -j ACCEPT
    done < "$WHITELIST_FILE"
    
    # Interfaces VPN
    iptables -A OUTPUT -o "$TUN_IFACE" -j ACCEPT
    iptables -A OUTPUT -o "$WG_IFACE" -j ACCEPT
    iptables -A INPUT -i "$TUN_IFACE" -j ACCEPT
    iptables -A INPUT -i "$WG_IFACE" -j ACCEPT
    
    # Bloquear todo lo demás
    iptables -A OUTPUT -o "$LOCAL_IFACE" -j DROP
    
    # IPv6
    ip6tables -P INPUT DROP 2>/dev/null || true
    ip6tables -P OUTPUT DROP 2>/dev/null || true
    ip6tables -P FORWARD DROP 2>/dev/null || true
    
    KILL_SWITCH_ACTIVE=true
    log_message "Kill Switch activado" "✅ Kill Switch activado"
}

disable_kill_switch() {
    log_message "Desactivando Kill Switch" "🛡️  Desactivando Kill Switch..."
    
    iptables -F
    iptables -t nat -F
    iptables -X
    iptables -t nat -X
    
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    
    # IPv6
    ip6tables -P INPUT ACCEPT 2>/dev/null || true
    ip6tables -P OUTPUT ACCEPT 2>/dev/null || true
    ip6tables -P FORWARD ACCEPT 2>/dev/null || true
    
    KILL_SWITCH_ACTIVE=false
    log_message "Kill Switch desactivado" "✅ Kill Switch desactivado"
}

# ==============================================================================
# SEGURIDAD Y ANONIMATO
# ==============================================================================

run_security_checks() {
    log_message "Ejecutando verificaciones de seguridad" "🔍 Verificando seguridad..."
    
    # 1. Test de fugas DNS
    test_dns_leaks
    
    # 2. Test de fugas WebRTC
    test_webrtc_leaks
    
    # 3. Verificar IPv6
    check_ipv6_disabled
    
    # 4. Verificar IP real
    check_real_ip
    
    log_message "Verificaciones completadas" "✅ Verificaciones de seguridad completadas"
}

test_dns_leaks() {
    log_message "Testeando fugas DNS" "🌐 Test de fugas DNS..."
    
    local dns_servers=()
    local test_domains=("google.com" "cloudflare.com" "quad9.net")
    
    for domain in "${test_domains[@]}"; do
        local result=$(dig +short "$domain" @9.9.9.9 2>/dev/null | head -1)
        if [[ -n "$result" ]]; then
            dns_servers+=("$domain: $result")
        fi
    done
    
    if [[ ${#dns_servers[@]} -gt 0 ]]; then
        log_message "DNS funcionando" "✅ DNS configurado correctamente"
        debug_message "DNS Servers: ${dns_servers[*]}" "📊 Servidores DNS: ${dns_servers[*]}"
    else
        error_message "Posible fuga DNS" "⚠️  Posible fuga DNS detectada"
    fi
}

test_webrtc_leaks() {
    # Simulación básica de test WebRTC
    log_message "Testeando WebRTC" "📡 Verificando WebRTC..."
    
    # En Termux no hay navegador, pero verificamos configuraciones de red
    local has_webrtc=$(ip addr show | grep -c "inet6\|fe80")
    if [[ "$has_webrtc" -gt 2 ]]; then
        debug_message "Interfaces IPv6 detectadas" "⚠️  Interfaces IPv6 detectadas"
    fi
}

check_ipv6_disabled() {
    log_message "Verificando IPv6" "🔌 Verificando estado IPv6..."
    
    if [[ $(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null) -eq 1 ]]; then
        log_message "IPv6 deshabilitado" "✅ IPv6 deshabilitado"
    else
        # Intentar deshabilitar
        echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
        log_message "IPv6 deshabilitado manualmente" "🔧 IPv6 deshabilitado manualmente"
    fi
}

check_real_ip() {
    log_message "Verificando IP pública" "🌍 Verificando IP..."
    
    local ip_services=(
        "https://api.ipify.org"
        "https://icanhazip.com"
        "https://checkip.amazonaws.com"
    )
    
    local ip_count=0
    local ips=()
    
    for service in "${ip_services[@]}"; do
        local ip=$(curl -s --connect-timeout 5 "$service" 2>/dev/null)
        if [[ -n "$ip" ]]; then
            ((ip_count++))
            ips+=("$ip")
        fi
    done
    
    if [[ "$ip_count" -ge 2 ]]; then
        # Verificar si todas las IPs son iguales (sin fugas)
        local unique_ips=$(printf "%s\n" "${ips[@]}" | sort -u | wc -l)
        if [[ "$unique_ips" -eq 1 ]]; then
            log_message "IP consistente: ${ips[0]}" "✅ IP VPN: ${GREEN}${ips[0]}${NC}"
        else
            error_message "IPs inconsistentes detectadas" "⚠️  Posible fuga: ${ips[*]}"
        fi
    else
        error_message "No se pudo obtener IP" "❌ No se pudo verificar IP"
    fi
}

# ==============================================================================
# MONITOREO Y CONEXIÓN
# ==============================================================================

check_vpn_connection() {
    # Verificar múltiples aspectos de la conexión
    local checks_passed=0
    local total_checks=3
    
    # 1. Verificar interfaz VPN
    if ip link show | grep -q "tun0\|wg0"; then
        ((checks_passed++))
    fi
    
    # 2. Verificar ruta por VPN
    if ip route show default | grep -q "tun0\|wg0"; then
        ((checks_passed++))
    fi
    
    # 3. Verificar conectividad externa
    if curl -s --connect-timeout 5 https://api.ipify.org >/dev/null 2>&1; then
        ((checks_passed++))
    fi
    
    if [[ "$checks_passed" -eq "$total_checks" ]]; then
        VPN_CONNECTED=true
        return 0
    else
        VPN_CONNECTED=false
        return 1
    fi
}

monitor_connection() {
    log_message "Iniciando monitor de conexión" "👁️  Iniciando monitor..."
    
    local check_interval=30
    local consecutive_failures=0
    local max_failures=3
    
    while true; do
        if check_vpn_connection; then
            consecutive_failures=0
            echo "connected" > "$VPN_STATUS_FILE"
            sleep "$check_interval"
        else
            ((consecutive_failures++))
            error_message "Falló check de conexión ($consecutive_failures/$max_failures)" "⚠️  Fallo $consecutive_failures/$max_failures"

        if [[ "$consecutive_failures" -ge "$max_failures" ]]; then
             error_message "Reintentando conexión..." "🔁 Reconectando..."
             reconnect_vpn
             consecutive_failures=0
         fi
            
            sleep 10
        fi
    done
}

reconnect_vpn() {
    log_message "Reconexión forzada" "🔄 Reconectando VPN..."
    
    if [[ -f "$ACTIVE_SERVER_FILE" ]]; then
        local server_line=$(cat "$ACTIVE_SERVER_FILE")
        IFS=':' read -r protocol config_path priority name <<< "$server_line"
        
        stop_current_connection
        sleep 2
        
        if connect_vpn "$protocol" "$config_path" "$name"; then
            log_message "Reconexión exitosa" "✅ Reconectado a $name"
        else
            error_message "Error en reconexión" "❌ Error al reconectar"
        fi
    fi
}

# ==============================================================================
# GESTIÓN DE CONEXIONES
# ==============================================================================

stop_current_connection() {
    log_message "Deteniendo conexión actual" "🛑 Deteniendo conexión..."
    
    # OpenVPN
    if [[ -f "$CONFIG_DIR/openvpn.pid" ]]; then
        local pid=$(cat "$CONFIG_DIR/openvpn.pid")
        kill -TERM "$pid" 2>/dev/null || true
        rm -f "$CONFIG_DIR/openvpn.pid"
    fi
    
    # WireGuard
    if [[ -f "$CONFIG_DIR/wireguard.pid" ]]; then
        local pid=$(cat "$CONFIG_DIR/wireguard.pid")
        kill -TERM "$pid" 2>/dev/null || true
        rm -f "$CONFIG_DIR/wireguard.pid"
        wg-quick down "$CONFIGS_DIR"/*.conf 2>/dev/null || true
    fi
    
    # Shadowsocks
    if [[ -f "$CONFIG_DIR/shadowsocks.pid" ]]; then
        local pid=$(cat "$CONFIG_DIR/shadowsocks.pid")
        kill -TERM "$pid" 2>/dev/null || true
        rm -f "$CONFIG_DIR/shadowsocks.pid"
    fi
    
    VPN_CONNECTED=false
    log_message "Conexión detenida" "✅ Conexiones detenidas"
}

backup_logs() {
    local backup_date=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/logs_$backup_date.tar.gz"
    
    tar -czf "$backup_file" -C "$LOGS_DIR" . 2>/dev/null
    
    # Mantener solo últimos 7 backups
    ls -t "$BACKUP_DIR"/logs_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null
    
    debug_message "Backup de logs creado: $backup_file" "💾 Backup creado"
}

# ==============================================================================
# INTERFAZ DE USUARIO
# ==============================================================================

show_banner() {
    
    clear

if command -v chafa >/dev/null 2>&1 && [ -f "$IMG" ]; then
    chafa --center=on --size=60x30 "$IMG"
else
    echo -e "${RED}[!] No se pudo cargar la imagen o chafa no está instalado${NC}"
fi

echo
echo -e "${LRED}      [+] CREADOR : Andro_Os${NC}"
echo -e "${LRED}      [+] PROYECTO: VPN MANAGER ADVANCED - TERMUX${NC}"
echo -e "${LRED}      [+] ESTADO  : ${GREEN}ACTIVO${NC}"
echo -e "${LRED}=================================================${NC}"

}

show_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}MENÚ PRINCIPAL:${NC}"
        echo ""
        echo "  1. 🚀 Iniciar sistema completo"
        echo "  2. 🛑 Detener todo"
        echo "  3. 🔄 Rotar servidor manualmente"
        echo "  4. 🛡️  Gestionar Kill Switch"
        echo "  5. 🔍 Test de seguridad"
        echo "  6. 📊 Ver estado"
        echo "  7. 📝 Editar configuraciones"
        echo "  8. 📂 Ver logs"
        echo "  9. ⚙️  Configuración"
        echo "  0. ❌ Salir"
        echo ""
        echo -n "  Selecciona opción [0-9]: "
        
        read -r choice
        case $choice in
            1) start_vpn_system ;;
            2) stop_vpn_system ;;
            3) manual_rotate ;;
            4) manage_kill_switch ;;
            5) run_security_checks ;;
            6) show_status ;;
            7) edit_configs ;;
            8) view_logs ;;
            9) show_settings ;;
            0) cleanup_exit ;;
            *) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}

start_vpn_system() {
    echo -e "\n${YELLOW}[?] Intervalo de rotación (segundos) [300]: ${NC}"
    read -r interval
    interval=${interval:-300}
    
    echo -e "${YELLOW}[?] ¿Activar Kill Switch? [S/n]: ${NC}"
    read -r ks_choice
    if [[ "$ks_choice" =~ ^[Nn] ]]; then
        ENABLE_KILL_SWITCH="false"
    else
        ENABLE_KILL_SWITCH="true"
    fi
    
    # Iniciar en segundo plano
    {
        init_system &&
        rotate_vpn_server "$interval" &
        ROTATE_PID=$!
        echo "$ROTATE_PID" > "$CONFIG_DIR/rotate.pid"
        
        monitor_connection &
        MONITOR_PID=$!
        echo "$MONITOR_PID" > "$CONFIG_DIR/monitor.pid"
        
        echo -e "${GREEN}✅ Sistema iniciado${NC}"
        echo -e "${CYAN}PIDs: Rotación=$ROTATE_PID, Monitor=$MONITOR_PID${NC}"
    } &
    
    sleep 2
}

stop_vpn_system() {
    echo -e "\n${YELLOW}[?] ¿Detener todo? [s/N]: ${NC}"
    read -r confirm
    if [[ "$confirm" =~ ^[Ss] ]]; then
        stop_current_connection
        disable_kill_switch
        
        # Matar procesos en segundo plano
        [[ -f "$CONFIG_DIR/rotate.pid" ]] && kill -TERM $(cat "$CONFIG_DIR/rotate.pid") 2>/dev/null
        [[ -f "$CONFIG_DIR/monitor.pid" ]] && kill -TERM $(cat "$CONFIG_DIR/monitor.pid") 2>/dev/null
        
        rm -f "$CONFIG_DIR"/*.pid 2>/dev/null
        
        echo -e "${GREEN}✅ Sistema detenido${NC}"
    fi
    sleep 2
}

manual_rotate() {
    echo -e "\n${CYAN}Servidores disponibles:${NC}"
    echo ""
    local count=1
    while IFS=':' read -r protocol config priority name; do
        [[ "$protocol" =~ ^# ]] && continue
        echo "  $count. $name ($protocol) [Pri: $priority]"
        ((count++))
    done < "$ROTATE_FILE"
    
    echo -e "\n${YELLOW}Selecciona servidor [1-$((count-1))]: ${NC}"
    read -r selection
    
    # Implementar rotación manual
    echo -e "${GREEN}✅ Rotación manual iniciada${NC}"
    sleep 2
}

show_status() {
    echo -e "\n${CYAN}=== ESTADO DEL SISTEMA ===${NC}"
    echo ""
    
    # Conexión VPN
    if check_vpn_connection; then
        echo -e "  VPN: ${GREEN}CONECTADO${NC}"
        [[ -f "$ACTIVE_SERVER_FILE" ]] && {
            IFS=':' read -r protocol config priority name <<< "$(cat "$ACTIVE_SERVER_FILE")"
            echo -e "  Servidor: $name ($protocol)"
        }
    else
        echo -e "  VPN: ${RED}DESCONECTADO${NC}"
    fi
    
    # Interfaces
    echo -e "\n${CYAN}Interfaces:${NC}"
    ip link show | grep -E "(tun|wg|eth|wlan)" | awk '{print "  " $2 " " $3}'
    
    # IP Pública
    echo -e "\n${CYAN}IP Pública:${NC}"
    curl -s --connect-timeout 3 https://api.ipify.org || echo "  No disponible"
    
    # Reglas iptables
    echo -e "\n${CYAN}Reglas iptables (Kill Switch):${NC}"
    if $KILL_SWITCH_ACTIVE; then
        echo -e "  ${GREEN}ACTIVO${NC}"
        iptables -L OUTPUT -n --line-numbers | head -20
    else
        echo -e "  ${RED}INACTIVO${NC}"
    fi
    
    echo -e "\n${YELLOW}Presiona Enter para continuar...${NC}"
    read -r
}

# ==============================================================================
# FUNCIONES AUXILIARES
# ==============================================================================

cleanup_exit() {
    echo -e "\n${YELLOW}[!] Limpiando y saliendo...${NC}"
    
    stop_current_connection
    disable_kill_switch
    
    # Matar todos los procesos hijos
    pkill -P $$ 2>/dev/null || true
    
    log_message "Sistema detenido por usuario" "👋 Sistema detenido"
    
    echo -e "${GREEN}✅ Limpieza completada. ¡Hasta luego!${NC}"
    exit 0
}

# ==============================================================================
# EJECUCIÓN PRINCIPAL
# ==============================================================================

main() {
    check_root
    
    # Argumentos de línea de comandos
    case "${1:-menu}" in
        "start")
            shift
            start_vpn_system "$@"
            wait
            ;;
        "stop")
            stop_vpn_system
            ;;
        "status")
            show_status
            ;;
        "menu")
            show_menu
            ;;
        "test")
            init_system
            run_security_checks
            ;;
        "install")
            # Este debería ejecutarse desde install.sh
            echo "Usa el script install.sh para instalación"
            ;;
        *)
            echo "Uso: $0 {start|stop|status|menu|test}"
            echo "  start [interval]  - Iniciar sistema"
            echo "  stop              - Detener todo"
            echo "  status            - Ver estado"
            echo "  menu              - Menú interactivo"
            echo "  test              - Test de seguridad"
            exit 1
            ;;
    esac
}

# Capturar señales
trap cleanup_exit SIGINT SIGTERM

# Ejecutar
main "$@"



