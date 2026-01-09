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
