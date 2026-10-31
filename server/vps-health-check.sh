#!/usr/bin/env bash
#
# vps_health_check.sh
# Script de diagnostico de salud para VPS (solo lectura, no modifica nada)
# Uso: sudo bash vps_health_check.sh
# Genera un archivo: vps_report_<hostname>_<fecha>.txt

# para ejecutar
# curl -o vps-health-check.sh https://genarogg.github.io/media/server/vps-health-check.sh
# sudo bash vps-health-check.sh

set -u

OUT="vps_report_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"

sep() {
  echo "" >> "$OUT"
  echo "==================================================================" >> "$OUT"
  echo "  $1" >> "$OUT"
  echo "==================================================================" >> "$OUT"
}

run() {
  # Ejecuta un comando y lo anota en el reporte, incluso si falla
  echo "" >> "$OUT"
  echo "--- \$ $*" >> "$OUT"
  eval "$@" >> "$OUT" 2>&1 || echo "[comando no disponible o fallo: $*]" >> "$OUT"
}

echo "REPORTE DE SALUD DEL VPS" > "$OUT"
echo "Generado: $(date)" >> "$OUT"
echo "Host: $(hostname)" >> "$OUT"

# -------------------------------------------------------------------
sep "1. INFORMACION GENERAL DEL SISTEMA"
run "uname -a"
run "cat /etc/os-release"
run "uptime"
run "who -b 2>/dev/null"
run "hostnamectl 2>/dev/null"
run "timedatectl 2>/dev/null"

# -------------------------------------------------------------------
sep "2. CPU"
run "nproc --all"
run "lscpu"
run "cat /proc/loadavg"
run "mpstat 1 3 2>/dev/null"
run "top -bn1 | head -n 20"

# -------------------------------------------------------------------
sep "3. MEMORIA Y SWAP"
run "free -h"
run "cat /proc/meminfo | head -n 20"
run "swapon --show 2>/dev/null"

# -------------------------------------------------------------------
sep "4. DISCO"
run "df -hT"
run "df -i"
run "lsblk -f 2>/dev/null"
run "du -sh /var/log 2>/dev/null"
run "iostat -xz 1 3 2>/dev/null"
run "find / -xdev -type f -size +200M -exec ls -lh {} \; 2>/dev/null | sort -k5 -rh | head -n 20"

# -------------------------------------------------------------------
sep "5. RED"
run "ip a"
run "ip route"
run "cat /etc/resolv.conf"
run "ss -tulnp"
run "ss -s"
run "netstat -i 2>/dev/null"
run "cat /proc/net/dev"

# -------------------------------------------------------------------
sep "6. PROCESOS"
run "ps aux --sort=-%cpu | head -n 15"
run "ps aux --sort=-%mem | head -n 15"
run "ps aux | wc -l"

# -------------------------------------------------------------------
sep "7. SERVICIOS (systemd)"
run "systemctl list-units --type=service --state=running --no-pager"
run "systemctl --failed --no-pager"
run "systemctl is-system-running 2>/dev/null"

# -------------------------------------------------------------------
sep "8. LOGS RECIENTES Y ERRORES"
run "journalctl -p err -b --no-pager | tail -n 100"
run "dmesg --level=err,warn 2>/dev/null | tail -n 60"
run "tail -n 50 /var/log/syslog 2>/dev/null"
run "tail -n 50 /var/log/messages 2>/dev/null"

# -------------------------------------------------------------------
sep "9. SEGURIDAD BASICA"
run "last -n 20"
run "lastb -n 20 2>/dev/null"
run "who"
run "w"
run "grep -i 'Failed password' /var/log/auth.log 2>/dev/null | tail -n 30"
run "grep -i 'Failed password' /var/log/secure 2>/dev/null | tail -n 30"
run "cat /etc/passwd | awk -F: '\$3 >= 1000 {print \$1, \$3, \$6, \$7}'"
run "find / -xdev -perm -4000 -type f 2>/dev/null"
run "iptables -L -n -v 2>/dev/null"
run "ufw status verbose 2>/dev/null"
run "fail2ban-client status 2>/dev/null"

# -------------------------------------------------------------------
sep "10. ACTUALIZACIONES PENDIENTES"
run "apt list --upgradable 2>/dev/null"
run "yum check-update 2>/dev/null"
run "dnf check-update 2>/dev/null"
run "needs-restarting -r 2>/dev/null"

# -------------------------------------------------------------------
sep "11. CRON Y TAREAS PROGRAMADAS"
run "crontab -l 2>/dev/null"
run "ls -la /etc/cron.d/ 2>/dev/null"
run "cat /etc/crontab 2>/dev/null"

# -------------------------------------------------------------------
sep "12. TEMPERATURA / HARDWARE (si aplica)"
run "sensors 2>/dev/null"
run "smartctl -a /dev/sda 2>/dev/null"
run "dmidecode -t system 2>/dev/null | head -n 20"

# -------------------------------------------------------------------
sep "13. DOCKER (si esta instalado)"
run "docker ps -a 2>/dev/null"
run "docker stats --no-stream 2>/dev/null"
run "docker system df 2>/dev/null"

# -------------------------------------------------------------------
sep "FIN DEL REPORTE"
echo "" >> "$OUT"
echo "Reporte guardado en: $(pwd)/$OUT" >> "$OUT"

echo ""
echo "✅ Reporte generado: $OUT"
echo "Pasa el contenido de ese archivo para que lo analice."
