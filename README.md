# VPN Client para Termux (Sin Root)

Sistema avanzado de gestión VPN para Android/Termux sin necesidad de root.

## 🚀 Características Principales

- ✅ **Sin Root** - Funciona completamente sin privilegios de superusuario
- 🛡️ **Kill Switch** - Bloquea tráfico si la VPN cae
- 🔄 **Rotación Dinámica** - Cambia automáticamente entre servidores
- 🌐 **Ofuscación** - Soporte para Shadowsocks y Stunnel
- 🔒 **Sin Fugas** - DNS seguro y bloqueo de IPv6
- 📊 **Monitoreo** - Verificación continua de conexión

## 📁 Estructura de Archivos

~/.vpn-client/
├── configs/ # Configuraciones de servidores
│ ├── server1.ovpn
│ ├── server1.conf
│ └── shadowsocks.json
├── scripts/ # Scripts del sistema
│ ├── vpn-manager.sh # Principal
│ ├── kill-switch.sh # Kill Switch
│ └── dns-leak-test.sh # Test de fugas
├── logs/ # Logs del sistema
│ ├── vpn.log
│ ├── error.log
│ └── debug.log
├── backups/ # Backups automáticos
├── rotate.list # Lista de rotación
└── whitelist.txt # Apps/redes permitidas


## ⚙️ Instalación Rápida

```bash
# 1. Descargar instalador
curl -O https://raw.githubusercontent.com/tu-repo/vpn-client/main/install.sh

# 2. Dar permisos y ejecutar
chmod +x install.sh
./install.sh

# 3. Configurar servidores
nano ~/.vpn-client/rotate.list

# 4. Iniciar sistema
vpn-menu

## 🎮 Uso Básico

# Menú interactivo
vpn-menu

# Iniciar sistema completo
vpn-start 300  # Rotación cada 5 minutos

# Detener todo
vpn-stop

# Ver estado
vpn-status

# Test de fugas DNS
~/.vpn-client/scripts/dns-leak-test.sh full
