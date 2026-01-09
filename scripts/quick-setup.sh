#!/data/data/com.termux/files/usr/bin/bash
# Setup RÁPIDO sin preguntas pendejas

echo "⚡ CONFIGURACIÓN RÁPIDA VPN"
echo "============================"

# Configuración por DEFECTO que FUNCIONA
CONFIG_DIR="$HOME/.vpn-client"

# 1. Configurar rotate.list MÍNIMO
cat > "$CONFIG_DIR/rotate.list" << 'EOF'
# CONFIGURACIÓN MÍNIMA FUNCIONAL
# Cambia estas líneas por TUS servidores:

# ovpn:/data/data/com.termux/files/home/.vpn-client/configs/tuserver.ovpn:1:MiVPN

# wireguard:/data/data/com.termux/files/home/.vpn-client/configs/tuserver.conf:2:MiWG

# shadowsocks:/data/data/com.termux/files/home/.vpn-client/configs/tuserver.json:3:MiSS
EOF

# 2. Whitelist MÍNIMA
cat > "$CONFIG_DIR/whitelist.txt" << 'EOF'
# CONFIGURACIÓN MÍNIMA - NO TOCAR
IP:192.168.0.0/16
IP:10.0.0.0/8
IP:172.16.0.0/12
EOF

# 3. Script de prueba CONEXIÓN REAL
cat > "$CONFIG_DIR/test-connection.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Test REAL de conexión VPN

echo "🔍 TEST DE CONEXIÓN REAL"
echo "========================"

# 1. Test DNS
echo "1. Test DNS..."
dns_leak=$(dig +short whoami.akamai.net @1.1.1.1)
if [[ -n "$dns_leak" ]]; then
    echo "   ⚠️  DNS: $dns_leak"
else
    echo "   ✅ DNS seguro"
fi

# 2. Test IP
echo "2. Test IP..."
vpn_ip=$(curl -s --connect-timeout 5 https://api.ipify.org)
if [[ -n "$vpn_ip" ]]; then
    echo "   🌍 IP VPN: $vpn_ip"
    
    # Test de fuga
    direct_ip=$(curl -s --interface wlan0 https://api.ipify.org 2>/dev/null || echo "N/A")
    if [[ "$vpn_ip" != "$direct_ip" ]]; then
        echo "   ✅ Sin fugas detectadas"
    else
        echo "   ❌ POSIBLE FUGA - IPs iguales"
    fi
else
    echo "   ❌ No hay conexión"
fi

# 3. Test velocidad
echo "3. Test velocidad básico..."
time curl -s -o /dev/null https://speedtest.net 2>&1 | grep real
EOF

chmod +x "$CONFIG_DIR/test-connection.sh"

# 4. Configurar atajos REALES
cat >> ~/.bashrc << 'EOF'
# ========== VPN ALIASES REALES ==========
alias vpn='cd ~/.vpn-client/scripts && ./vpn-manager.sh'
alias vpn-start='~/.vpn-client/scripts/vpn-manager.sh start 300'
alias vpn-stop='~/.vpn-client/scripts/vpn-manager.sh stop'
alias vpn-test='~/.vpn-client/test-connection.sh'
alias vpn-logs='tail -f ~/.vpn-client/logs/vpn.log'
alias vpn-status='~/.vpn-client/scripts/vpn-manager.sh status'
EOF

source ~/.bashrc

echo ""
echo "✅ CONFIGURACIÓN RÁPIDA COMPLETADA"
echo ""
echo "COMANDOS DISPONIBLES:"
echo "  vpn-start    - Inicia VPN (5 min rotación)"
echo "  vpn-stop     - Detiene todo"
echo "  vpn-test     - Test de conexión REAL"
echo "  vpn-logs     - Ver logs en tiempo real"
echo "  vpn-status   - Estado del sistema"
echo ""
echo "⚠️  AHORA:"
echo "1. Copia tus archivos .ovpn a ~/.vpn-client/configs/"
echo "2. Edita ~/.vpn-client/rotate.list con TUS servidores REALES"
echo "3. Usa: vpn-start"
