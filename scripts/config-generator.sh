#!/data/data/com.termux/files/usr/bin/bash
# Generador de configuraciones VPN REALES

echo "🔧 GENERADOR DE CONFIGURACIONES VPN REALES"
echo "=========================================="

# 1. Generar rotate.list con servidores REALES
read -p "¿Cuántos servidores VPN tienes? " server_count

> ~/.vpn-client/rotate.list
for ((i=1; i<=$server_count; i++)); do
    echo ""
    echo "📡 Servidor $i:"
    read -p "  Protocolo (ovpn/wireguard/shadowsocks): " proto
    read -p "  Ruta del archivo de configuración: " config_path
    read -p "  Prioridad (1-10): " priority
    read -p "  Nombre descriptivo: " name
    
    echo "${proto}:${config_path}:${priority}:${name}" >> ~/.vpn-client/rotate.list
done

# 2. Generar whitelist REAL
echo ""
echo "📱 CONFIGURAR WHITELIST"
cat > ~/.vpn-client/whitelist.txt << 'EOF'
# Redes locales PERMITIDAS (sin VPN)
IP:192.168.0.0/16
IP:10.0.0.0/8
IP:172.16.0.0/12

# DNS locales
IP:192.168.1.1
IP:10.0.0.1
EOF

read -p "¿Añadir WiFi de confianza? (s/n): " add_wifi
if [[ "$add_wifi" == "s" ]]; then
    read -p "SSID del WiFi de casa: " wifi_home
    echo "WIFI:${wifi_home}" >> ~/.vpn-client/whitelist.txt
fi

# 3. Crear scripts de inicio automático
cat > ~/.vpn-client/start-vpn.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Inicio automático REAL de VPN

echo "🚀 Iniciando VPN Client..."
cd ~/.vpn-client/scripts

# Activar Kill Switch
./kill-switch.sh start

# Iniciar rotación cada 10 minutos
./vpn-manager.sh start 600 &

echo "✅ VPN iniciada en segundo plano"
echo "📊 Monitor: tail -f ~/.vpn-client/logs/vpn.log"
EOF

chmod +x ~/.vpn-client/start-vpn.sh

# 4. Crear script de parada
cat > ~/.vpn-client/stop-vpn.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Parada completa REAL

echo "🛑 Deteniendo VPN..."
cd ~/.vpn-client/scripts

# Detener todo
./vpn-manager.sh stop
./kill-switch.sh stop

pkill -f openvpn
pkill -f wg-quick
pkill -f ss-local

echo "✅ VPN detenida completamente"
EOF

chmod +x ~/.vpn-client/stop-vpn.sh

echo ""
echo "✅ CONFIGURACIONES GENERADAS"
echo ""
echo "ARCHIVOS CREADOS:"
echo "1. ~/.vpn-client/rotate.list      (Tus servidores reales)"
echo "2. ~/.vpn-client/whitelist.txt    (Redes permitidas)"
echo "3. ~/.vpn-client/start-vpn.sh     (Inicio automático)"
echo "4. ~/.vpn-client/stop-vpn.sh      (Parada completa)"
echo ""
echo "📌 PASOS FINALES:"
echo "1. Copia tus .ovpn/.conf REALES a ~/.vpn-client/configs/"
echo "2. Verifica las rutas en rotate.list"
echo "3. Ejecuta: ~/.vpn-client/start-vpn.sh"
