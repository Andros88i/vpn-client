#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# DETECTOR AVANZADO DE FUGAS DNS
# ==============================================================================

CONFIG_DIR="$HOME/.vpn-client"
LOG_FILE="$CONFIG_DIR/logs/dns_test.log"
RESULTS_FILE="$CONFIG_DIR/logs/dns_results.json"

# Servidores DNS de test
declare -A DNS_SERVERS=(
    ["Quad9"]="9.9.9.9"
    ["Cloudflare"]="1.1.1.1"
    ["Google"]="8.8.8.8"
    ["OpenDNS"]="208.67.222.222"
    ["Comodo"]="8.26.56.26"
)

# Dominios para test
TEST_DOMAINS=(
    "google.com"
    "facebook.com"
    "amazon.com"
    "microsoft.com"
    "cloudflare.com"
    "github.com"
    "reddit.com"
    "wikipedia.org"
)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

run_dns_test() {
    echo "🧪 Iniciando test de fugas DNS..."
    echo ""
    
    local results=()
    local leak_detected=false
    
    for domain in "${TEST_DOMAINS[@]}"; do
        echo -e "🔍 Probando: \033[1;34m$domain\033[0m"
        
        local dns_ips=()
        local unique_ips=()
        
        # Consultar a cada servidor DNS
        for dns_name in "${!DNS_SERVERS[@]}"; do
            local dns_ip="${DNS_SERVERS[$dns_name]}"
            local result=$(dig +short +time=2 +tries=1 "$domain" @"$dns_ip" 2>/dev/null | head -1)
            
            if [[ -n "$result" ]]; then
                dns_ips+=("$dns_name:$result")
                
                # Verificar si la IP ya fue resuelta por otro DNS
                if [[ ! " ${unique_ips[@]} " =~ " $result " ]]; then
                    unique_ips+=("$result")
                fi
            fi
        done
        
        # Analizar resultados
        if [[ ${#unique_ips[@]} -gt 1 ]]; then
            echo -e "  ❌ \033[0;31mFUGA DETECTADA!\033[0m"
            echo -e "  IPs diferentes encontradas:"
            for ip in "${unique_ips[@]}"; do
                echo -e "    • $ip"
            done
            leak_detected=true
        elif [[ ${#unique_ips[@]} -eq 1 ]]; then
            echo -e "  ✅ \033[0;32mSeguro\033[0m (${unique_ips[0]})"
        else
            echo -e "  ⚠️  \033[0;33mNo response\033[0m"
        fi
        
        echo ""
    done
    
    # Test de DNS propio
    echo "🌐 Test de DNS propio..."
    local my_dns=$(dig +short whoami.akamai.net @1.1.1.1 2>/dev/null)
    if [[ -n "$my_dns" ]]; then
        echo -e "  Tu DNS: \033[1;36m$my_dns\033[0m"
        
        # Verificar si es un DNS conocido de VPN
        if [[ "$my_dns" =~ (akamai|cloudflare|google) ]]; then
            echo -e "  ✅ \033[0;32mProbablemente usando DNS de VPN\033[0m"
        else
            echo -e "  ⚠️  \033[0;33mDNS personal detectado\033[0m"
        fi
    fi
    
    # Resumen
    echo ""
    echo "📊 RESUMEN:"
    if $leak_detected; then
        echo -e "  ❌ \033[0;31mSE DETECTARON FUGAS DNS\033[0m"
        echo "  Recomendación: Revisa la configuración de tu VPN"
    else
        echo -e "  ✅ \033[0;32mSIN FUGAS DETECTADAS\033[0m"
        echo "  Tu conexión DNS está segura"
    fi
    
    # Guardar resultados
    save_results "$leak_detected"
}

save_results() {
    local leak_detected=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$RESULTS_FILE" << EOF
{
    "timestamp": "$timestamp",
    "leak_detected": $leak_detected,
    "test_domains": ${#TEST_DOMAINS[@]},
    "dns_servers_tested": ${#DNS_SERVERS[@]},
    "recommendation": "$([[ $leak_detected == true ]] && echo 'Revisar configuración VPN' || echo 'Conexión segura')"
}
EOF
    
    log "Test completado - Fuga: $leak_detected"
}

quick_test() {
    echo "🚀 Test rápido de fugas..."
    
    local test_ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
    local vpn_ip=$(curl -s --connect-timeout 3 https://api.ipify.org 2>/dev/null)
    
    if [[ -n "$test_ip" && -n "$vpn_ip" ]]; then
        if [[ "$test_ip" != "$vpn_ip" ]]; then
            echo -e "  ❌ \033[0;31mFuga DNS detectada!\033[0m"
            echo -e "  IP DNS: $test_ip"
            echo -e "  IP VPN: $vpn_ip"
            return 1
        else
            echo -e "  ✅ \033[0;32mSin fugas\033[0m"
            echo -e "  IP: $vpn_ip"
            return 0
        fi
    fi
    
    echo "  ⚠️  No se pudo completar el test"
    return 2
}

continuous_monitor() {
    echo "👁️  Iniciando monitor continuo de DNS..."
    echo "  Presiona Ctrl+C para detener"
    echo ""
    
    local interval=60  # Segundos
    
    while true; do
        local timestamp=$(date '+%H:%M:%S')
        echo -n "[$timestamp] "
        
        if quick_test; then
            log "Monitor - Sin fugas detectadas"
        else
            log "Monitor - FUGA DETECTADA"
            echo -e "\n🚨 \033[0;31mALERTA: Fuga detectada!\033[0m"
        fi
        
        sleep "$interval"
    done
}

case "${1:-full}" in
    "full")
        run_dns_test
        ;;
    "quick")
        quick_test
        ;;
    "monitor")
        continuous_monitor
        ;;
    "help")
        echo "Uso: $0 {full|quick|monitor|help}"
        echo "  full     - Test completo de fugas DNS"
        echo "  quick    - Test rápido básico"
        echo "  monitor  - Monitoreo continuo"
        echo "  help     - Mostrar esta ayuda"
        ;;
    *)
        run_dns_test
        ;;
esac
