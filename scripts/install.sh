#!/data/data/com.termux/files/usr/bin/bash

echo "╔════════════════════════════════════════╗"
echo "║   INSTALADOR VPN CLIENT - TERMUX       ║"
echo "║      (Sin Root - Configuración Avanzada)║"
echo "╚════════════════════════════════════════╝"

# Crear estructura de directorios
echo "[*] Creando estructura de directorios..."
mkdir -p ~/.vpn-client/{configs,scripts,logs,backups}

# Instalar dependencias
echo "[*] Instalando dependencias..."
pkg update -y && pkg upgrade -y
pkg install -y python nodejs golang termux-api
pkg install -y iptables net-tools dnsutils curl wget
pkg install -y openvpn wireguard-tools shadowsocks-libev stunnel
pkg install -y jq git tmux proot resolvconf nano

# Python modules
pip install --upgrade pip
pip install requests psutil dnspython

# Descargar archivos del proyecto
echo "[*] Descargando archivos de configuración..."

# Archivo principal
curl -o ~/.vpn-client/scripts/vpn-manager.sh \
https://raw.githubusercontent.com/termux-vpn/vpn-client/main/vpn-manager.sh

# Scripts auxiliares
curl -o ~/.vpn-client/scripts/kill-switch.sh \
https://raw.githubusercontent.com/termux-vpn/vpn-client/main/kill-switch.sh

curl -o ~/.vpn-client/scripts/dns-leak-test.sh \
https://raw.githubusercontent.com/termux-vpn/vpn-client/main/dns-leak-test.sh

# Configuraciones de ejemplo
curl -o ~/.vpn-client/rotate.list \
https://raw.githubusercontent.com/termux-vpn/vpn-client/main/rotate.list

curl -o ~/.vpn-client/whitelist.txt \
https://raw.githubusercontent.com/termux-vpn/vpn-client/main/whitelist.txt

# Configuración de Shadowsocks ejemplo
curl -o ~/.vpn-client/configs/shadowsocks.json \
https://raw.githubusercontent.com/termux-vpn/vpn-client/main/shadowsocks-example.json

# Configuración WireGuard ejemplo
curl -o ~/.vpn-client/configs/wireguard-example.conf \
https://raw.githubusercontent.com/termux-vpn/vpn-client/main/wireguard-example.conf

# Configuración OpenVPN ejemplo
curl -o ~/.vpn-client/configs/openvpn-example.ovpn \
https://raw.githubusercontent.com/termux-vpn/vpn-client/main/openvpn-example.ovpn

# Dar permisos de ejecución
chmod +x ~/.vpn-client/scripts/*.sh

# Crear alias para fácil acceso
echo "alias vpn-start='~/.vpn-client/scripts/vpn-manager.sh start'" >> ~/.bashrc
echo "alias vpn-stop='~/.vpn-client/scripts/vpn-manager.sh stop'" >> ~/.bashrc
echo "alias vpn-menu='~/.vpn-client/scripts/vpn-manager.sh menu'" >> ~/.bashrc
echo "alias vpn-status='~/.vpn-client/scripts/vpn-manager.sh status'" >> ~/.bashrc

source ~/.bashrc

echo ""
echo "✅ INSTALACIÓN COMPLETADA"
echo ""
echo "📂 Estructura creada en: ~/.vpn-client/"
echo "⚡ Comandos disponibles:"
echo "   vpn-start    - Iniciar sistema VPN"
echo "   vpn-stop     - Detener todo"
echo "   vpn-menu     - Menú interactivo"
echo "   vpn-status   - Ver estado"
echo ""
echo "⚠️  IMPORTANTE: Edita los archivos de configuración:"
echo "   1. ~/.vpn-client/rotate.list"
echo "   2. ~/.vpn-client/configs/ con tus configuraciones reales"
echo ""
echo "Para comenzar: 'vpn-menu'"
