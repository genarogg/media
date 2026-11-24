#!/bin/bash
#
# cpu-guard-light.sh
#
# Versión simplificada de cpu-guard: monitorea el uso de CPU del VPS y,
# si se mantiene sostenidamente alto, identifica el stack de docker
# compose (excluyendo siempre Coolify) que más CPU está consumiendo y lo
# detiene. Nunca toca Coolify ni sus contenedores propios.
#
# Flujo:
#   1. Monitoreo: cada INTERVALO segundos revisa el uso de CPU.
#   2. Disparo: si está en >= UMBRAL% durante SEGUNDOS_SOSTENIDOS seguidos,
#      toma un snapshot de los contenedores corriendo e identifica, con
#      `docker stats`, qué stack (proyecto de docker compose) no-Coolify
#      consume más CPU sumado entre sus contenedores. Detiene ESE stack.
#      Si no hay ningún contenedor no-Coolify perteneciente a un stack
#      (todos sueltos), no hace nada ese ciclo.
#   3. Ventana de verificación: vigila VENTANA_VERIFICACION segundos.
#        - Si la CPU baja del umbral en algún momento, restaura el stack
#          que se había detenido.
#        - Si la CPU se mantiene >= UMBRAL% toda la ventana, el stack
#          queda apagado y el script espera ESPERA_RESTAURACION_MINUTOS
#          minutos fijos (sin seguir monitoreando la CPU durante esa
#          espera) y luego lo restaura automáticamente de todas formas.
#          Si al reactivarse la CPU vuelve a dispararse, se trata como un
#          incidente nuevo y se repite el mismo flujo desde el paso 2
#          (puede identificar el mismo stack u otro distinto).
#   4. Cooldown: tras cada incidente (se haya restaurado antes o después
#      de la espera de ESPERA_RESTAURACION_MINUTOS), espera
#      COOLDOWN_SEGUNDOS antes de poder disparar otra vez.
#   5. Red de seguridad: en cada vuelta del loop principal (cada
#      INTERVALO segundos) se revisa si algún stack detenido por este
#      script lleva más de MAX_HORAS_APAGADO horas apagado. Si es así, se
#      reactiva de inmediato, sin esperar a que termine la espera de
#      ESPERA_RESTAURACION_MINUTOS ni depender de que esa lógica haya
#      funcionado (por ejemplo, si el script se reinició a medio camino).
#
# Este script se auto-instala como servicio systemd la primera vez que se
# ejecuta manualmente, para quedar corriendo en segundo plano y arrancar
# solo con el servidor. Las siguientes ejecuciones (las de systemd) saltan
# ese bloque y van directo al loop de monitoreo.

# para ejecutar
# curl -o cpu-guard-light.sh https://genarogg.github.io/media/server/cpu-guard-light.sh
# sudo bash cpu-guard-light.sh

# revisar
# sudo systemctl status cpu-guard-light
# tail -f /var/log/cpu-guard-light/cpu-guard-light.log   # log continuo
# ls /var/log/cpu-guard-light/incidentes/                # un archivo por incidente

set -u

INSTALL_PATH="/usr/local/bin/cpu-guard-light.sh"
SERVICE_PATH="/etc/systemd/system/cpu-guard-light.service"
SERVICE_NAME="cpu-guard-light"

auto_instalar_servicio() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Este script necesita permisos de root. Ejecuta: sudo bash $0"
    exit 1
  fi

  echo "==> Instalando cpu-guard-light como servicio systemd..."

  mkdir -p /var/lib/cpu-guard-light /var/log/cpu-guard-light/incidentes

  if [ "$(readlink -f "$0")" != "$INSTALL_PATH" ]; then
    cp "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
  fi

  cat > "$SERVICE_PATH" << EOF
[Unit]
Description=CPU Guard Light - detiene solo el stack docker compose mas pesado si la CPU se sostiene alta
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
  echo "    Ver estado:    sudo systemctl status $SERVICE_NAME"
  echo "    Log continuo:  sudo tail -f /var/log/cpu-guard-light/cpu-guard-light.log"
  echo "    Incidentes:    ls /var/log/cpu-guard-light/incidentes/"
  exit 0
}

if [ -z "${INVOCATION_ID:-}" ]; then
  auto_instalar_servicio
fi

# ---------------------- Configuración ----------------------
UMBRAL=97                   # % de uso de CPU que dispara la acción
INTERVALO=10                # segundos entre cada lectura
SEGUNDOS_SOSTENIDOS=120     # tiempo sostenido antes de actuar
VENTANA_VERIFICACION=30     # segundos que se vigila tras apagar el stack
ESPERA_RESTAURACION_MINUTOS=30   # si sigue alto tras la ventana, minutos fijos antes de restaurar igual
MAX_HORAS_APAGADO=3         # red de seguridad: tope de horas que un stack puede quedar apagado por este script
LECTURAS_NECESARIAS=$(( SEGUNDOS_SOSTENIDOS / INTERVALO ))
LECTURAS_VERIFICACION=$(( VENTANA_VERIFICACION / INTERVALO ))
COOLDOWN_SEGUNDOS=60        # espera tras cada incidente antes de poder disparar otra vez

DIR_ESTADO="/var/lib/cpu-guard-light"
DIR_INCIDENTES="/var/log/cpu-guard-light/incidentes"
mkdir -p "$DIR_ESTADO" "$DIR_INCIDENTES"

LOG_FILE="/var/log/cpu-guard-light/cpu-guard-light.log"
SNAPSHOT_ACTUAL="${DIR_ESTADO}/snapshot-actual.list"
REGISTRO_APAGADOS="${DIR_ESTADO}/apagados.list"   # proyecto|timestamp_epoch de cada stack detenido por este script
INCIDENTE_ACTUAL=""

# Contenedores propios de Coolify: nunca se tocan, y nunca se eligen como
# "stack más pesado" aunque tuvieran etiqueta de compose.
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
  local linea
  linea="$(date '+%Y-%m-%d %H:%M:%S') | $1"
  echo "$linea" >> "$LOG_FILE"
  if [ -n "${INCIDENTE_ACTUAL:-}" ]; then
    echo "$linea" >> "$INCIDENTE_ACTUAL"
  fi
}

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

iniciar_incidente() {
  local id
  id="$(date +%Y%m%d-%H%M%S)"
  INCIDENTE_ACTUAL="${DIR_INCIDENTES}/incidente-${id}.log"
  {
    echo "===================================================="
    echo " Incidente cpu-guard-light - $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Umbral sostenido: ${UMBRAL}% durante ${SEGUNDOS_SOSTENIDOS}s"
    echo "===================================================="
  } > "$INCIDENTE_ACTUAL"
}

cerrar_incidente() {
  INCIDENTE_ACTUAL=""
}

capturar_snapshot_actual() {
  docker ps --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.service"}}' > "$SNAPSHOT_ACTUAL"
}

# Identifica, entre los contenedores no-Coolify del snapshot que
# pertenezcan a un proyecto de docker compose, cuál stack consume más CPU
# sumado (usando `docker stats`). Devuelve el nombre del proyecto por
# stdout, o nada si no hay ningún candidato.
identificar_stack_mas_pesado() {
  if [ ! -s "$SNAPSHOT_ACTUAL" ]; then
    return
  fi

  local ids_no_coolify=()
  local -A proyecto_de_id
  while IFS='|' read -r id nombre imagen proyecto servicio; do
    [ -z "$id" ] && continue
    local es_coolify=false
    for ex in "${EXCLUIDOS[@]}"; do
      [ "$nombre" == "$ex" ] && es_coolify=true && break
    done
    [ "$es_coolify" = true ] && continue
    [ -z "$proyecto" ] && continue
    ids_no_coolify+=("$id")
    proyecto_de_id["$id"]="$proyecto"
  done < "$SNAPSHOT_ACTUAL"

  if [ "${#ids_no_coolify[@]}" -eq 0 ]; then
    log "Ningún contenedor no-Coolify pertenece a un proyecto docker compose. Nada que aislar este ciclo."
    return
  fi

  local -A suma_cpu_por_proyecto
  local id cpu_str cpu_num proyecto
  while IFS='|' read -r id cpu_str; do
    [ -z "$id" ] && continue
    proyecto="${proyecto_de_id[$id]:-}"
    [ -z "$proyecto" ] && continue
    cpu_num="${cpu_str%\%}"
    cpu_num="${cpu_num%%.*}"
    [[ "$cpu_num" =~ ^[0-9]+$ ]] || cpu_num=0
    suma_cpu_por_proyecto["$proyecto"]=$(( ${suma_cpu_por_proyecto[$proyecto]:-0} + cpu_num ))
  done < <(docker stats --no-stream --format '{{.ID}}|{{.CPUPerc}}' "${ids_no_coolify[@]}" 2>>"$LOG_FILE")

  local mejor_proyecto="" mejor_cpu=-1
  for proyecto in "${!suma_cpu_por_proyecto[@]}"; do
    log "Stack '${proyecto}' consume ${suma_cpu_por_proyecto[$proyecto]}% de CPU sumado."
    if [ "${suma_cpu_por_proyecto[$proyecto]}" -gt "$mejor_cpu" ]; then
      mejor_cpu="${suma_cpu_por_proyecto[$proyecto]}"
      mejor_proyecto="$proyecto"
    fi
  done

  if [ -n "$mejor_proyecto" ]; then
    log "Stack identificado como más pesado: '${mejor_proyecto}' (${mejor_cpu}% sumado)."
    echo "$mejor_proyecto"
  fi
}

# Archivo de lock para serializar toda escritura/lectura de
# REGISTRO_APAGADOS entre el loop principal (verificar_tope_apagado) y el
# subproceso en segundo plano que restaura tras ESPERA_RESTAURACION_MINUTOS,
# ya que ambos pueden correr al mismo tiempo.
LOCK_APAGADOS="${DIR_ESTADO}/apagados.lock"

# Registra en REGISTRO_APAGADOS que el proyecto indicado fue detenido por
# este script ahora mismo. Es la fuente de verdad para la red de
# seguridad de MAX_HORAS_APAGADO: si se cae a medio camino la lógica
# normal de restauración (30s / 30min), esto permite igual detectarlo y
# reactivarlo.
marcar_apagado() {
  local proyecto="$1"
  (
    flock -x 200
    grep -v "^${proyecto}|" "$REGISTRO_APAGADOS" 2>/dev/null > "${REGISTRO_APAGADOS}.tmp"
    mv "${REGISTRO_APAGADOS}.tmp" "$REGISTRO_APAGADOS"
    echo "${proyecto}|$(date +%s)" >> "$REGISTRO_APAGADOS"
  ) 200>"$LOCK_APAGADOS"
}

# Quita al proyecto indicado del registro de apagados (porque ya se
# restauró, por el motivo que sea).
quitar_de_registro_apagados() {
  local proyecto="$1"
  [ -f "$REGISTRO_APAGADOS" ] || return
  (
    flock -x 200
    grep -v "^${proyecto}|" "$REGISTRO_APAGADOS" 2>/dev/null > "${REGISTRO_APAGADOS}.tmp"
    mv "${REGISTRO_APAGADOS}.tmp" "$REGISTRO_APAGADOS"
  ) 200>"$LOCK_APAGADOS"
}

# Detiene únicamente los contenedores del snapshot que pertenezcan al
# proyecto indicado. Devuelve 0 si detuvo algo, 1 si no encontró nada.
detener_stack() {
  local proyecto_objetivo="$1"
  local a_detener=()
  while IFS='|' read -r id nombre imagen proyecto servicio; do
    [ -z "$id" ] && continue
    [ "$proyecto" == "$proyecto_objetivo" ] || continue
    log "  se detendrá: $nombre ($id) imagen=$imagen [servicio: ${servicio}]"
    a_detener+=("$id")
  done < "$SNAPSHOT_ACTUAL"

  if [ "${#a_detener[@]}" -eq 0 ]; then
    return 1
  fi

  docker stop "${a_detener[@]}" >> "$LOG_FILE" 2>&1
  marcar_apagado "$proyecto_objetivo"
  log "Listo. ${#a_detener[@]} contenedor(es) del stack '${proyecto_objetivo}' detenidos."
  return 0
}

# Restaura, en un solo `docker start`, los contenedores del snapshot que
# pertenezcan al proyecto indicado.
restaurar_stack() {
  local proyecto_objetivo="$1"
  local ids=()
  while IFS='|' read -r id nombre imagen proyecto servicio; do
    [ -z "$id" ] && continue
    [ "$proyecto" == "$proyecto_objetivo" ] || continue
    ids+=("$id")
  done < "$SNAPSHOT_ACTUAL"

  if [ "${#ids[@]}" -eq 0 ]; then
    log "No se encontraron contenedores del stack '${proyecto_objetivo}' en el snapshot. Nada que restaurar."
    quitar_de_registro_apagados "$proyecto_objetivo"
    return
  fi

  log "  levantando stack '${proyecto_objetivo}': ${ids[*]}"
  docker start "${ids[@]}" >> "$LOG_FILE" 2>&1
  quitar_de_registro_apagados "$proyecto_objetivo"
}

# Red de seguridad: revisa REGISTRO_APAGADOS y, si algún stack lleva más
# de MAX_HORAS_APAGADO horas apagado por este script, lo reactiva ahora
# mismo usando `docker start` directo sobre sus contenedores detenidos
# (identificados por la etiqueta com.docker.compose.project, ya que el
# snapshot del incidente que lo detuvo pudo haberse sobreescrito por otro
# incidente posterior). No depende del flujo normal ni de que
# SNAPSHOT_ACTUAL siga teniendo esos datos.
verificar_tope_apagado() {
  [ -s "$REGISTRO_APAGADOS" ] || return

  local ahora limite_epoch proyecto marcado
  ahora=$(date +%s)
  local vencidos=()

  (
    flock -x 200
    local tmp="${REGISTRO_APAGADOS}.tmp"
    : > "$tmp"
    while IFS='|' read -r proyecto marcado; do
      [ -z "$proyecto" ] && continue
      limite_epoch=$(( marcado + MAX_HORAS_APAGADO * 3600 ))
      if [ "$ahora" -ge "$limite_epoch" ]; then
        echo "$proyecto" >> "${REGISTRO_APAGADOS}.vencidos"
      else
        echo "${proyecto}|${marcado}" >> "$tmp"
      fi
    done < "$REGISTRO_APAGADOS"
    mv "$tmp" "$REGISTRO_APAGADOS"
  ) 200>"$LOCK_APAGADOS"

  [ -f "${REGISTRO_APAGADOS}.vencidos" ] || return
  while IFS= read -r proyecto; do
    [ -z "$proyecto" ] && continue
    log "RED DE SEGURIDAD: el stack '${proyecto}' lleva más de ${MAX_HORAS_APAGADO}h apagado por este script. Reactivando..."
    local ids_detenidos=()
    while IFS='|' read -r id nombre_c; do
      [ -z "$id" ] && continue
      ids_detenidos+=("$id")
    done < <(docker ps -a --filter "status=exited" --filter "label=com.docker.compose.project=${proyecto}" --format '{{.ID}}|{{.Names}}')

    if [ "${#ids_detenidos[@]}" -gt 0 ]; then
      docker start "${ids_detenidos[@]}" >> "$LOG_FILE" 2>&1
      log "RED DE SEGURIDAD: stack '${proyecto}' reactivado (${#ids_detenidos[@]} contenedor(es))."
    else
      log "RED DE SEGURIDAD: no se encontraron contenedores detenidos del stack '${proyecto}' (puede que ya estuviera arriba)."
    fi
  done < "${REGISTRO_APAGADOS}.vencidos"
  rm -f "${REGISTRO_APAGADOS}.vencidos"
}

# Se lanza en segundo plano (un subshell aparte) cuando el stack queda
# apagado tras la ventana de verificación. Espera ESPERA_RESTAURACION_MINUTOS
# minutos fijos y restaura el stack, SIN bloquear el loop principal: así
# el monitoreo de CPU y la red de seguridad (verificar_tope_apagado) del
# proceso principal siguen funcionando con normalidad durante esa espera.
# Si para cuando despierta el stack ya fue reactivado por la red de
# seguridad (MAX_HORAS_APAGADO), restaurar_stack/quitar_de_registro ya no
# encuentra contenedores detenidos y no hace nada.
esperar_y_restaurar_en_segundo_plano() {
  local stack="$1"
  sleep "$(( ESPERA_RESTAURACION_MINUTOS * 60 ))"
  log "Se cumplieron ${ESPERA_RESTAURACION_MINUTOS} minuto(s) de espera para '${stack}'. Restaurando (si sigue apagado)..."
  restaurar_stack "$stack"
  log "Stack '${stack}' restaurado tras la espera de ${ESPERA_RESTAURACION_MINUTOS} minuto(s)."
}

# Tras detener el stack, vigila VENTANA_VERIFICACION segundos.
#   - Si la CPU baja del umbral en cualquier lectura, restaura el stack.
#   - Si se mantiene >= UMBRAL% toda la ventana, lo deja apagado y lanza
#     en segundo plano la espera de ESPERA_RESTAURACION_MINUTOS, para no
#     bloquear el loop principal (que debe seguir monitoreando CPU y
#     corriendo la red de seguridad de MAX_HORAS_APAGADO).
verificar_y_resolver() {
  local stack="$1"
  log "Iniciando ventana de verificación (~${VENTANA_VERIFICACION}s) tras apagar '${stack}'."
  local i uso_actual
  for (( i=0; i<LECTURAS_VERIFICACION; i++ )); do
    sleep "$INTERVALO"
    uso_actual=$(obtener_uso_cpu)
    if [ "$uso_actual" -lt "$UMBRAL" ]; then
      log "CPU bajó a ${uso_actual}% durante la ventana de verificación. Restaurando stack '${stack}'..."
      restaurar_stack "$stack"
      log "Incidente cerrado. Stack '${stack}' restaurado."
      cerrar_incidente
      return
    fi
  done
  log "La CPU se mantuvo en ${UMBRAL}%+ durante toda la ventana de verificación."
  log "El stack '${stack}' queda apagado. Se restaurará automáticamente en ${ESPERA_RESTAURACION_MINUTOS} minuto(s) (en segundo plano; el monitoreo de CPU y la red de seguridad siguen activos mientras tanto)."
  # Se lanza ANTES de cerrar_incidente a propósito: el subshell hereda el
  # valor actual de INCIDENTE_ACTUAL y sus logs seguirán cayendo en el
  # archivo de este mismo incidente.
  esperar_y_restaurar_en_segundo_plano "$stack" &
  disown
  cerrar_incidente
}

# ---------------------- Loop principal ----------------------
log "cpu-guard-light iniciado. Umbral=${UMBRAL}% sostenido ${SEGUNDOS_SOSTENIDOS}s -> apaga solo el stack más pesado (nunca Coolify) -> verifica ${VENTANA_VERIFICACION}s -> restaura, o si sigue alto espera ${ESPERA_RESTAURACION_MINUTOS}min y restaura igual. Red de seguridad: tope de ${MAX_HORAS_APAGADO}h apagado."
contador=0
ultimo_disparo=0
while true; do
  # Red de seguridad: reactiva cualquier stack que este script haya
  # detenido y que ya supere MAX_HORAS_APAGADO horas apagado, sin
  # importar en qué paso del flujo normal se haya quedado.
  verificar_tope_apagado

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
      iniciar_incidente
      capturar_snapshot_actual
      ultimo_disparo=$ahora

      stack="$(identificar_stack_mas_pesado)"
      if [ -z "$stack" ]; then
        log "No hay stack candidato que aislar este ciclo. Incidente cerrado sin acción."
        cerrar_incidente
      elif detener_stack "$stack"; then
        verificar_y_resolver "$stack"
      else
        log "El stack '${stack}' ya no tenía contenedores corriendo. Incidente cerrado sin acción."
        cerrar_incidente
      fi
    fi
    contador=0
  fi

  sleep "$INTERVALO"
done
