#!/data/data/com.termux/files/usr/bin/bash
# Inicia TODO AHORA MISMO

echo "🚀 INICIO INMEDIATO VPN"
echo "======================="

# Matar procesos existentes
pkill -f openvpn 2>/dev/null
pkill -f wg-quick 2>/dev/null
pkill -f ss-local 2>/dev/null

# Limpiar iptables
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT

# Crear estructura si no existe
mkdir -p ~/.vpn-client/{configs,logs}

# Verificar archivos
if [[ ! -f ~/.vpn-client/rotate.list ]]; then
    echo "❌ ERROR: No hay rotate.list"
    echo "Crea ~/.vpn-client/rotate.list con este contenido:"
    echo ""
    echo "ovpn:/data/data/com.termux/files/home/.vpn-client/configs/TUSERVER.ovpn:1:MiVPN"
    echo ""
    exit 1
fi

# Contar servidores
server_count=$(grep -v "^#" ~/.vpn-client/rotate.list | grep -v "^$" | wc -l)
if [[ $server_count -eq 0 ]]; then
    echo "❌ ERROR: No hay servidores en rotate.list"
    echo "Añade al menos UN servidor REAL"
    exit 1
fi

echo "✅ $server_count servidores configurados"

# Obtener primer servidor
first_server=$(grep -v "^#" ~/.vpn-client/rotate.list | head -1)
IFS=':' read -r protocol config_path priority name <<< "$first_server"

echo "🔗 Conectando a: $name ($protocol)"

# Conectar según protocolo
case $protocol in
    ovpn)
        if [[ -f "$config_path" ]]; then
            echo "📁 Usando: $(basename "$config_path")"
            openvpn --config "$config_path" --daemon
        else
            echo "❌ Archivo no encontrado: $config_path"
            exit 1
        fi
        ;;
    wireguard)
        if [[ -f "$config_path" ]]; then
            echo "📁 Usando: $(basename "$config_path")"
            wg-quick up "$config_path"
        else
            echo "❌ Archivo no encontrado: $config_path"
            exit 1
        fi
        ;;
    *)
        echo "❌ Protocolo no soportado: $protocol"
        exit 1
        ;;
esac

# Esperar conexión
echo "⏳ Esperando conexión..."
sleep 5

# Verificar
if curl -s --connect-timeout 5 https://api.ipify.org >/dev/null; then
    ip=$(curl -s https://api.ipify.org)
    echo "✅ CONECTADO - IP: $ip"
    
    # Activar Kill Switch básico
    echo "🛡️  Activando Kill Switch básico..."
    iptables -P OUTPUT DROP
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -A OUTPUT -o tun0 -j ACCEPT
    iptables -A OUTPUT -o wg0 -j ACCEPT
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    echo "🎉 VPN ACTIVA Y SEGURA"
else
    echo "❌ No se pudo conectar"
fi
