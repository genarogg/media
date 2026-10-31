#!/usr/bin/env bash
#
# securite-server.sh
# Script de endurecimiento basico para VPS (Ubuntu/Debian)
# Uso: sudo bash securite-server.sh
#
# Pasos:
#   1. apt update && apt upgrade
#   2. Instalar y configurar fail2ban (jail basico para SSH)
#   3. Instalar iptables y UFW, abrir solo 22/80/443 y activar
#   4. Instalar y configurar unattended-upgrades

# para ejecutar
# curl -o securite-server.sh https://genarogg.github.io/media/server/securite-server.sh
# sudo bash securite-server.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Este script debe ejecutarse como root (usa: sudo bash securite-server.sh)"
  exit 1
fi

echo "=============================================="
echo "  1. Actualizando el sistema"
echo "=============================================="
export DEBIAN_FRONTEND=noninteractive
apt update
apt upgrade -y

echo ""
echo "=============================================="
echo "  2. Instalando fail2ban"
echo "=============================================="
apt install -y fail2ban

echo ""
echo "=============================================="
echo "  3. Configurando jail basico para SSH"
echo "=============================================="
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
# Tiempo que una IP queda baneada (10 minutos)
bantime  = 10m
# Ventana de tiempo en la que se cuentan los intentos fallidos
findtime = 10m
# Cantidad de intentos fallidos antes de banear
maxretry = 5

[sshd]
enabled  = true
port     = ssh
backend  = systemd
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo ""
echo "=============================================="
echo "  4. Instalando iptables y UFW"
echo "=============================================="
apt install -y iptables ufw

echo ""
echo "=============================================="
echo "  5. Configurando UFW (solo SSH/HTTP/HTTPS)"
echo "=============================================="
# Reglas por defecto: negar entrante, permitir saliente
ufw default deny incoming
ufw default allow outgoing

# Abrir solo lo necesario
ufw allow 22/tcp   comment 'SSH'
ufw allow 80/tcp   comment 'HTTP'
ufw allow 443/tcp  comment 'HTTPS'

# --force evita el prompt interactivo de confirmacion
ufw --force enable

echo ""
echo "=============================================="
echo "  6. Instalando y configurando unattended-upgrades"
echo "=============================================="
apt install -y unattended-upgrades apt-listchanges

# Habilita el servicio de actualizaciones automaticas
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Configuracion de que se actualiza, reinicios y notificaciones.
# Se escribe completa para no depender del contenido por defecto
# que trae el paquete (que varia entre versiones de Ubuntu/Debian).
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}:${distro_codename}-updates";
};

// Paquetes que nunca se deben actualizar automaticamente (vacio por defecto)
Unattended-Upgrade::Package-Blacklist {
};

// Elimina dependencias huerfanas despues de actualizar
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Reinicia automaticamente el servidor si una actualizacion lo requiere
// (por ejemplo, un nuevo kernel). Cambia a "false" si prefieres reiniciar
// manualmente despues de revisar los cambios.
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

echo ""
echo "=============================================="
echo "  Resumen"
echo "=============================================="
systemctl --no-pager status fail2ban | head -n 5
echo ""
fail2ban-client status sshd || true
echo ""
ufw status verbose
echo ""
systemctl --no-pager status unattended-upgrades | head -n 5
echo ""
echo "Prueba en seco de unattended-upgrades (no instala nada):"
unattended-upgrade --dry-run --debug 2>&1 | tail -n 20 || true

echo ""
echo "✅ Listo. Sistema actualizado, fail2ban activo protegiendo SSH, UFW activo"
echo "   permitiendo solo los puertos 22 (SSH), 80 (HTTP) y 443 (HTTPS), y"
echo "   unattended-upgrades instalando parches de seguridad automaticamente"
echo "   (con reinicio automatico a las 04:00 si un kernel lo requiere)."
echo ""
echo "⚠️  IMPORTANTE: Docker administra sus propias reglas de iptables y puede"
echo "   saltarse UFW para los puertos que publiques con -p (ej: 8080 de Traefik)."
echo "   UFW protege los servicios del host (como SSH), pero si quieres que"
echo "   tambien bloquee un puerto publicado por un contenedor, hay que"
echo "   configurarlo aparte (o no publicarlo con 0.0.0.0, solo 127.0.0.1)."
