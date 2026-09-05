#!/bin/bash
#
# cpu-guard.sh
#
# Monitorea el uso de CPU del VPS.
#
# Nivel 1: si se mantiene en >= UMBRAL% durante SEGUNDOS_SOSTENIDOS segundos
# seguidos, detiene todos los contenedores Docker EXCEPTO los propios de
# Coolify (coolify, coolify-proxy, coolify-db, coolify-redis,
# coolify-realtime, coolify-sentinel).
#
# Nivel 2 (escalada): si, tras la acción del Nivel 1, la CPU se mantiene en
# >= UMBRAL% durante SEGUNDOS_ESCALADA segundos MÁS, se asume que el
# problema no eran los contenedores no-Coolify, y se detienen TAMBIÉN los
# contenedores de Coolify. En ese punto el servidor queda completamente
# detenido y requiere intervención manual por SSH para levantarlo de
# nuevo (sin Coolify arriba, su propio dashboard deja de responder).
#
# Este script se auto-instala como servicio systemd la primera vez que se
# ejecuta manualmente, para que quede corriendo en segundo plano y arranque
# solo con el servidor. Las siguientes ejecuciones (las de systemd) saltan
# este bloque y van directo a la lógica de monitoreo.

# para ejecutar
# curl -o cpu-guard.sh https://genarogg.github.io/media/server/cpu-guard.sh
# sudo bash cpu-guard.sh

# revisar
# sudo systemctl status cpu-guard
set -u

INSTALL_PATH="/usr/local/bin/cpu-guard.sh"
SERVICE_PATH="/etc/systemd/system/cpu-guard.service"
SERVICE_NAME="cpu-guard"

auto_instalar_servicio() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Este script necesita permisos de root. Ejecuta: sudo bash $0"
    exit 1
  fi

  echo "==> Instalando cpu-guard como servicio systemd..."

  # Copia el script a una ruta estable si no está ya ahí
  if [ "$(readlink -f "$0")" != "$INSTALL_PATH" ]; then
    cp "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
  fi

  # Crea la unidad systemd
  cat > "$SERVICE_PATH" << EOF
[Unit]
Description=CPU Guard - detiene contenedores no-Coolify si la CPU se sostiene alta
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/bin/bash $INSTALL_PATH
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"

  echo "==> Listo. El servicio quedó instalado, habilitado y corriendo."
  echo "    Ver estado: sudo systemctl status $SERVICE_NAME"
  echo "    Ver logs:   sudo tail -f /var/log/cpu-guard.log"
  exit 0
}

# Si no se está ejecutando como el propio servicio systemd, auto-instalarse.
# (systemd invoca este script con el mismo INSTALL_PATH; detectamos la
# ejecución manual comparando la variable de entorno que systemd no define).
if [ -z "${INVOCATION_ID:-}" ]; then
  auto_instalar_servicio
fi

# ---------------------- Configuración ----------------------
UMBRAL=97                 # % de uso de CPU que dispara la acción
INTERVALO=10              # segundos entre cada lectura
SEGUNDOS_SOSTENIDOS=90    # tiempo sostenido antes de actuar (Nivel 1)
SEGUNDOS_ESCALADA=60      # tiempo sostenido ADICIONAL tras el Nivel 1 antes de escalar (Nivel 2)
LECTURAS_NECESARIAS=$(( SEGUNDOS_SOSTENIDOS / INTERVALO ))
LECTURAS_ESCALADA=$(( SEGUNDOS_ESCALADA / INTERVALO ))
LOG_FILE="/var/log/cpu-guard.log"
COOLDOWN_SEGUNDOS=600     # tras el Nivel 1, espera antes de poder volver a disparar

# Contenedores de Coolify que el Nivel 1 NUNCA detiene.
# El Nivel 2 sí los detiene — es la escalada máxima.
EXCLUIDOS=(
  "coolify"
  "coolify-proxy"
  "coolify-db"
  "coolify-redis"
  "coolify-realtime"
  "coolify-sentinel"
)

# ---------------------- Funciones ----------------------
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

# Devuelve el % de uso de CPU actual (100 - idle), usando /proc/stat
obtener_uso_cpu() {
  read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat
  total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
  idle1=$idle
  sleep 1
  read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat
  total2=$((user + nice + system + idle + iowait + irq + softirq + steal))
  idle2=$idle
  total_diff=$((total2 - total1))
  idle_diff=$((idle2 - idle1))
  if [ "$total_diff" -le 0 ]; then
    echo 0
    return
  fi
  uso=$(( (100 * (total_diff - idle_diff)) / total_diff ))
  echo "$uso"
}

# Nivel 1: detiene todos los contenedores EXCEPTO los de Coolify.
# Un solo `docker stop id1 id2 ...` al final -> los detiene en paralelo.
detener_contenedores_no_coolify() {
  log "NIVEL 1: umbral sostenido detectado. Deteniendo contenedores no-Coolify..."
  local todos
  todos=$(docker ps -q --format '{{.ID}} {{.Names}}')
  if [ -z "$todos" ]; then
    log "No hay contenedores corriendo. Nada que hacer."
    return
  fi

  local a_detener=()
  while IFS=' ' read -r id nombre; do
    [ -z "$id" ] && continue
    local excluido=false
    for ex in "${EXCLUIDOS[@]}"; do
      if [ "$nombre" == "$ex" ]; then
        excluido=true
        break
      fi
    done
    if [ "$excluido" = true ]; then
      log "  omitido (Coolify): $nombre ($id)"
    else
      log "  se detendrá: $nombre ($id)"
      a_detener+=("$id")
    fi
  done <<< "$todos"

  if [ "${#a_detener[@]}" -eq 0 ]; then
    log "No había contenedores no-Coolify que detener."
    return
  fi

  docker stop "${a_detener[@]}" >> "$LOG_FILE" 2>&1
  log "Listo. ${#a_detener[@]} contenedor(es) no-Coolify detenidos en paralelo."
}

# Nivel 2 (escalada máxima): detiene absolutamente todo, incluidos los
# contenedores de Coolify. También en un solo `docker stop` en paralelo.
detener_todos_los_contenedores() {
  log "NIVEL 2 (ESCALADA MÁXIMA): la CPU sigue en ${UMBRAL}%+ tras el Nivel 1. Deteniendo TODOS los contenedores, incluido Coolify."
  local todos
  todos=$(docker ps -q --format '{{.ID}} {{.Names}}')
  if [ -z "$todos" ]; then
    log "No hay contenedores corriendo. Nada que hacer."
    return
  fi

  local ids=()
  while IFS=' ' read -r id nombre; do
    [ -z "$id" ] && continue
    log "  deteniendo: $nombre ($id)"
    ids+=("$id")
  done <<< "$todos"

  docker stop "${ids[@]}" >> "$LOG_FILE" 2>&1
  log "Listo. TODOS los contenedores detenidos, incluido Coolify. Requiere intervención manual por SSH para levantar los servicios de nuevo."
}

# Tras el Nivel 1, vigila SEGUNDOS_ESCALADA segundos más. Si la CPU se
# mantiene en >= UMBRAL% durante toda la ventana, escala al Nivel 2.
# Si baja del umbral en cualquier lectura, cancela la escalada.
verificar_escalada() {
  log "Iniciando ventana de escalada (~${SEGUNDOS_ESCALADA}s) tras el Nivel 1."
  local i uso_actual
  for (( i=0; i<LECTURAS_ESCALADA; i++ )); do
    sleep "$INTERVALO"
    uso_actual=$(obtener_uso_cpu)
    if [ "$uso_actual" -lt "$UMBRAL" ]; then
      log "CPU bajó a ${uso_actual}% durante la ventana de escalada. Se cancela el Nivel 2."
      return
    fi
  done
  detener_todos_los_contenedores
}

# ---------------------- Loop principal ----------------------
log "cpu-guard iniciado. Umbral=${UMBRAL}% sostenido ${SEGUNDOS_SOSTENIDOS}s (Nivel 1) / ${SEGUNDOS_ESCALADA}s adicionales (Nivel 2, incluye Coolify)."
contador=0
ultimo_disparo=0
while true; do
  uso=$(obtener_uso_cpu)
  ahora=$(date +%s)

  if [ "$uso" -ge "$UMBRAL" ]; then
    contador=$((contador + 1))
  else
    contador=0
  fi

  if [ "$contador" -ge "$LECTURAS_NECESARIAS" ]; then
    tiempo_desde_ultimo=$((ahora - ultimo_disparo))
    if [ "$tiempo_desde_ultimo" -ge "$COOLDOWN_SEGUNDOS" ]; then
      detener_contenedores_no_coolify
      ultimo_disparo=$ahora
      verificar_escalada
    fi
    contador=0
  fi

  sleep "$INTERVALO"
done