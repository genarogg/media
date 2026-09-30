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
# detenido. A diferencia de la versión anterior, esto YA NO requiere
# intervención manual: se guarda un registro de todo lo que estaba
# corriendo y, tras REINICIO_ESPERA_MINUTOS minutos, el propio script
# reinicia el servidor (vía `shutdown -r`) y, al arrancar de nuevo,
# restaura automáticamente los contenedores que se habían detenido.
#
# Cada incidente (Nivel 1 y, si escala, Nivel 2 + reinicio + restauración)
# queda documentado en su propio archivo dentro de DIR_INCIDENTES, además
# del log continuo en LOG_FILE.
#
# Freno contra reinicios en bucle: el proceso normal (Nivel 1 -> Nivel 2 ->
# reinicio -> restauración) sigue igual siempre. La única diferencia es
# cuando, en una hora, ya se acumularon MAX_REINICIOS_POR_HORA reinicios
# automáticos (por defecto 3): ahí se asume que el problema no se resuelve
# solo con reiniciar, así que esa vez NO se reinicia el servidor. En su
# lugar se activa un bloqueo temporal de BLOQUEO_ESPERA_MINUTOS minutos
# (por defecto 60) con todos los contenedores apagados. El servicio y su
# loop de monitoreo de CPU NUNCA se detienen durante ese bloqueo; solo se
# evita volver a actuar mientras dure. Pasada la hora, el propio script
# levanta de nuevo todos los contenedores automáticamente, sin intervención
# manual, y el ciclo continúa exactamente igual que siempre (si la CPU
# vuelve a dispararse, puede volver a pasar por Nivel 1, Nivel 2, etc., con
# normalidad). Para forzar la restauración antes de que se cumpla la hora,
# se puede borrar /var/lib/cpu-guard/bloqueado a mano en cualquier momento.
#
# Los contenedores que pertenecen a un mismo proyecto de docker compose
# (misma etiqueta com.docker.compose.project) se detienen y se vuelven a
# levantar siempre juntos, en un solo comando `docker start`, para que
# todos sus servicios queden arriba al mismo tiempo.
#
# Este script se auto-instala como servicio systemd la primera vez que se
# ejecuta manualmente, para que quede corriendo en segundo plano y arranque
# solo con el servidor. Las siguientes ejecuciones (las de systemd) saltan
# ese bloque y van directo a la lógica de monitoreo / restauración.

# para ejecutar
# curl -o cpu-guard.sh https://genarogg.github.io/media/server/cpu-guard.sh
# sudo bash cpu-guard.sh

# revisar
# sudo systemctl status cpu-guard
# tail -f /var/log/cpu-guard/cpu-guard.log          # log continuo
# ls /var/log/cpu-guard/incidentes/                 # un archivo por incidente
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

  mkdir -p /var/lib/cpu-guard /var/log/cpu-guard/incidentes

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
  echo "    Ver estado:    sudo systemctl status $SERVICE_NAME"
  echo "    Log continuo:  sudo tail -f /var/log/cpu-guard/cpu-guard.log"
  echo "    Incidentes:    ls /var/log/cpu-guard/incidentes/"
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
COOLDOWN_SEGUNDOS=600     # tras el Nivel 1, espera antes de poder volver a disparar

REINICIO_ESPERA_MINUTOS=5   # minutos de espera antes de reiniciar el servidor tras el Nivel 2
ESPERA_COOLIFY_SEGUNDOS=20  # segundos de margen tras levantar Coolify antes de levantar el resto
MAX_REINICIOS_POR_HORA=3    # tope de reinicios automáticos en 1 hora antes de deshabilitar el auto-recovery
BLOQUEO_ESPERA_MINUTOS=60   # minutos que permanece todo apagado tras el bloqueo antes de auto-restaurar

# Directorios de estado (persisten entre reinicios) y de logs
DIR_ESTADO="/var/lib/cpu-guard"
DIR_INCIDENTES="/var/log/cpu-guard/incidentes"
mkdir -p "$DIR_ESTADO" "$DIR_INCIDENTES"

LOG_FILE="/var/log/cpu-guard/cpu-guard.log"
SNAPSHOT_ACTUAL="${DIR_ESTADO}/snapshot-actual.list"     # foto de "docker ps" al inicio del incidente actual
REGISTRO_RESTAURAR="${DIR_ESTADO}/restaurar.list"        # qué restaurar tras el reinicio o el bloqueo
MARCADOR_RESTAURAR="${DIR_ESTADO}/restaurar.pending"     # existe => hay que restaurar al arrancar
ARCHIVO_INCIDENTE_ACTUAL="${DIR_ESTADO}/incidente-actual.txt"  # ruta del .log del incidente en curso
REGISTRO_REINICIOS="${DIR_ESTADO}/reinicios.log"         # timestamps (epoch) de cada reinicio automático
BLOQUEADO="${DIR_ESTADO}/bloqueado"                      # si existe, el auto-recovery está deshabilitado (temporalmente)
INCIDENTE_ACTUAL=""

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

# Escribe en el log continuo y, si hay un incidente abierto, también en su
# archivo dedicado.
log() {
  local linea
  linea="$(date '+%Y-%m-%d %H:%M:%S') | $1"
  echo "$linea" >> "$LOG_FILE"
  if [ -n "${INCIDENTE_ACTUAL:-}" ]; then
    echo "$linea" >> "$INCIDENTE_ACTUAL"
  fi
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

# Abre un nuevo archivo de incidente y lo deja apuntado tanto en la
# variable en memoria como en disco (para sobrevivir a un reinicio).
iniciar_incidente() {
  local id
  id="$(date +%Y%m%d-%H%M%S)"
  INCIDENTE_ACTUAL="${DIR_INCIDENTES}/incidente-${id}.log"
  {
    echo "===================================================="
    echo " Incidente cpu-guard - $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Umbral sostenido: ${UMBRAL}% durante ${SEGUNDOS_SOSTENIDOS}s"
    echo "===================================================="
  } > "$INCIDENTE_ACTUAL"
  echo "$INCIDENTE_ACTUAL" > "$ARCHIVO_INCIDENTE_ACTUAL"
}

# Cierra el incidente actual sin haber llegado al Nivel 2 (la CPU se
# normalizó durante la ventana de escalada).
cerrar_incidente() {
  rm -f "$ARCHIVO_INCIDENTE_ACTUAL"
  INCIDENTE_ACTUAL=""
}

# Guarda una foto de todos los contenedores corriendo ANTES de tocar nada,
# incluyendo su proyecto/servicio de docker compose si aplica. Esta foto es
# la única fuente de verdad para todo el incidente (qué se detiene en el
# Nivel 1, qué se detiene en el Nivel 2, y qué se restaura después).
capturar_snapshot_actual() {
  docker ps --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.service"}}' > "$SNAPSHOT_ACTUAL"
}

# Nivel 1: detiene todos los contenedores del snapshot EXCEPTO los de Coolify.
# Un solo `docker stop id1 id2 ...` al final -> los detiene en paralelo.
detener_contenedores_no_coolify() {
  log "NIVEL 1: umbral sostenido detectado. Deteniendo contenedores no-Coolify..."

  if [ ! -s "$SNAPSHOT_ACTUAL" ]; then
    log "No hay contenedores corriendo. Nada que hacer."
    return
  fi

  local a_detener=()
  while IFS='|' read -r id nombre imagen proyecto servicio; do
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
      local extra=""
      [ -n "$proyecto" ] && extra=" [compose: ${proyecto}/${servicio}]"
      log "  se detendrá: $nombre ($id) imagen=$imagen${extra}"
      a_detener+=("$id")
    fi
  done < "$SNAPSHOT_ACTUAL"

  if [ "${#a_detener[@]}" -eq 0 ]; then
    log "No había contenedores no-Coolify que detener."
    return
  fi

  docker stop "${a_detener[@]}" >> "$LOG_FILE" 2>&1
  log "Listo. ${#a_detener[@]} contenedor(es) no-Coolify detenidos en paralelo."
}

# Nivel 2 (escalada máxima): detiene también los contenedores de Coolify
# (los no-Coolify ya están detenidos desde el Nivel 1). Guarda el registro
# completo del snapshot y programa el reinicio automático del servidor.
detener_todos_los_contenedores() {
  log "NIVEL 2 (ESCALADA MÁXIMA): la CPU sigue en ${UMBRAL}%+ tras el Nivel 1. Deteniendo también los contenedores de Coolify."

  local ids_coolify=()
  while IFS='|' read -r id nombre imagen proyecto servicio; do
    [ -z "$id" ] && continue
    for ex in "${EXCLUIDOS[@]}"; do
      if [ "$nombre" == "$ex" ]; then
        ids_coolify+=("$id")
        break
      fi
    done
  done < "$SNAPSHOT_ACTUAL"

  if [ "${#ids_coolify[@]}" -gt 0 ]; then
    log "  deteniendo Coolify: ${ids_coolify[*]}"
    docker stop "${ids_coolify[@]}" >> "$LOG_FILE" 2>&1
  fi

  log "Listo. TODOS los contenedores están detenidos, incluido Coolify."

  programar_reinicio
}

# Cuenta cuántos reinicios automáticos se registraron en la última hora.
reinicios_recientes() {
  local ahora limite count=0
  ahora=$(date +%s)
  limite=$((ahora - 3600))
  if [ -f "$REGISTRO_REINICIOS" ]; then
    while read -r ts; do
      [ -z "$ts" ] && continue
      if [ "$ts" -ge "$limite" ]; then
        count=$((count + 1))
      fi
    done < "$REGISTRO_REINICIOS"
  fi
  echo "$count"
}

# Registra un reinicio nuevo (timestamp actual) y de paso poda las entradas
# de más de 24h para que el archivo no crezca sin límite.
registrar_reinicio() {
  local ahora limite tmp
  ahora=$(date +%s)
  limite=$((ahora - 86400))
  tmp="${REGISTRO_REINICIOS}.tmp"
  : > "$tmp"
  if [ -f "$REGISTRO_REINICIOS" ]; then
    while read -r ts; do
      [ -z "$ts" ] && continue
      [ "$ts" -ge "$limite" ] && echo "$ts" >> "$tmp"
    done < "$REGISTRO_REINICIOS"
  fi
  echo "$ahora" >> "$tmp"
  mv "$tmp" "$REGISTRO_REINICIOS"
}

# Guarda el registro de todo lo que había corriendo (para restaurarlo tras
# el reinicio) y programa el reinicio del servidor con `shutdown -r`.
# Si ya se acumularon MAX_REINICIOS_POR_HORA reinicios en la última hora,
# NO reinicia el servidor: en vez de eso activa el bloqueo temporal (ver
# activar_bloqueo), que deja los contenedores apagados una hora mientras el
# script sigue corriendo y monitoreando con normalidad.
programar_reinicio() {
  local recientes
  recientes=$(reinicios_recientes)
  if [ "$recientes" -ge "$MAX_REINICIOS_POR_HORA" ]; then
    log "Se alcanzó el máximo de ${MAX_REINICIOS_POR_HORA} reinicios automáticos en la última hora."
    log "No se reiniciará el servidor esta vez. Se activa el bloqueo temporal en su lugar."
    activar_bloqueo
    return
  fi

  cp "$SNAPSHOT_ACTUAL" "$REGISTRO_RESTAURAR"
  touch "$MARCADOR_RESTAURAR"
  registrar_reinicio

  local total
  total=$(wc -l < "$REGISTRO_RESTAURAR")
  log "Registro guardado: ${total} contenedor(es) para restaurar tras el reinicio."
  log "Reinicios automáticos en la última hora (contando este): $((recientes + 1))/${MAX_REINICIOS_POR_HORA}"
  log "Programando reinicio del servidor en ${REINICIO_ESPERA_MINUTOS} minuto(s)."
  log "(si necesitas intervenir manualmente antes, cancela con: sudo shutdown -c)"

  shutdown -r "+${REINICIO_ESPERA_MINUTOS}" \
    "cpu-guard: reinicio automatico tras detener todos los contenedores (CPU sostenida >= ${UMBRAL}%)" \
    >> "$LOG_FILE" 2>&1
}

# Activa el bloqueo temporal: guarda el registro de lo que hay que
# restaurar y crea el archivo BLOQUEADO con la hora en que se creó (su
# mtime es la referencia para saber cuándo se cumple BLOQUEO_ESPERA_MINUTOS).
# El script NO se detiene ni deja de monitorear: el loop principal sigue su
# curso normal, simplemente no vuelve a actuar mientras BLOQUEADO exista.
activar_bloqueo() {
  cp "$SNAPSHOT_ACTUAL" "$REGISTRO_RESTAURAR"
  touch "$BLOQUEADO"
  log "Bloqueo activado. Los contenedores quedan apagados durante ${BLOQUEO_ESPERA_MINUTOS} minuto(s)."
  log "El monitoreo de CPU sigue activo; pasado ese tiempo se restaurará todo automáticamente y el ciclo continuará normal."
  log "(para forzar la restauración antes, borra ${BLOQUEADO} a mano)"
  cerrar_incidente
}

# Tras el Nivel 1, vigila SEGUNDOS_ESCALADA segundos más. Si la CPU se
# mantiene en >= UMBRAL% durante toda la ventana, escala al Nivel 2.
# Si baja del umbral en cualquier lectura, cancela la escalada y cierra
# el incidente (los contenedores no-Coolify quedan detenidos para revisión
# manual; Coolify sigue arriba para poder levantarlos desde su panel).
verificar_escalada() {
  log "Iniciando ventana de escalada (~${SEGUNDOS_ESCALADA}s) tras el Nivel 1."
  local i uso_actual
  for (( i=0; i<LECTURAS_ESCALADA; i++ )); do
    sleep "$INTERVALO"
    uso_actual=$(obtener_uso_cpu)
    if [ "$uso_actual" -lt "$UMBRAL" ]; then
      log "CPU bajó a ${uso_actual}% durante la ventana de escalada. Se cancela el Nivel 2."
      log "Incidente cerrado. Los contenedores no-Coolify siguen detenidos; revísalos manualmente en Coolify."
      cerrar_incidente
      return
    fi
  done
  detener_todos_los_contenedores
}

# Se ejecuta al arrancar el script (típicamente tras el reinicio automático
# del Nivel 2). Espera a que Docker esté listo y restaura los contenedores
# guardados: primero Coolify, después el resto agrupado por proyecto de
# docker compose (todos los servicios de un mismo proyecto en un solo
# `docker start`, para que suban juntos), y por último los sueltos.
restaurar_contenedores() {
  log "=== Restaurando contenedores detenidos... ==="

  local intentos=0
  until docker info >/dev/null 2>&1; do
    sleep 3
    intentos=$((intentos + 1))
    if [ "$intentos" -ge 40 ]; then
      log "ERROR: Docker no respondió tras ~120s. Se aborta la restauración automática, requiere revisión manual."
      return 1
    fi
  done

  if [ ! -s "$REGISTRO_RESTAURAR" ]; then
    log "No hay registro de contenedores para restaurar."
    rm -f "$MARCADOR_RESTAURAR"
    return
  fi

  # Paso 1: Coolify primero, para que el dashboard y el proxy estén arriba
  # antes que el resto de las apps.
  local ids_coolify=()
  while IFS='|' read -r id nombre imagen proyecto servicio; do
    [ -z "$id" ] && continue
    for ex in "${EXCLUIDOS[@]}"; do
      if [ "$nombre" == "$ex" ]; then
        ids_coolify+=("$id")
        break
      fi
    done
  done < "$REGISTRO_RESTAURAR"

  if [ "${#ids_coolify[@]}" -gt 0 ]; then
    log "Levantando primero Coolify: ${ids_coolify[*]}"
    docker start "${ids_coolify[@]}" >> "$LOG_FILE" 2>&1
    log "Esperando ${ESPERA_COOLIFY_SEGUNDOS}s a que Coolify quede operativo..."
    sleep "$ESPERA_COOLIFY_SEGUNDOS"
  fi

  # Paso 2: el resto, agrupado por proyecto de docker compose para que
  # todos los servicios de un mismo proyecto se levanten juntos.
  local -A grupos
  local sueltos=()
  while IFS='|' read -r id nombre imagen proyecto servicio; do
    [ -z "$id" ] && continue
    local es_coolify=false
    for ex in "${EXCLUIDOS[@]}"; do
      [ "$nombre" == "$ex" ] && es_coolify=true && break
    done
    [ "$es_coolify" = true ] && continue

    if [ -n "$proyecto" ]; then
      grupos["$proyecto"]="${grupos[$proyecto]:-}${grupos[$proyecto]:+ }$id"
    else
      sueltos+=("$id")
    fi
  done < "$REGISTRO_RESTAURAR"

  for proyecto in "${!grupos[@]}"; do
    log "Levantando proyecto docker compose '${proyecto}': ${grupos[$proyecto]}"
    docker start ${grupos[$proyecto]} >> "$LOG_FILE" 2>&1
  done

  if [ "${#sueltos[@]}" -gt 0 ]; then
    log "Levantando contenedores independientes: ${sueltos[*]}"
    docker start "${sueltos[@]}" >> "$LOG_FILE" 2>&1
  fi

  log "=== Restauración completada. ==="
  mv "$REGISTRO_RESTAURAR" "${REGISTRO_RESTAURAR}.$(date +%Y%m%d%H%M%S).bak"
  rm -f "$MARCADOR_RESTAURAR" "$ARCHIVO_INCIDENTE_ACTUAL"
  INCIDENTE_ACTUAL=""
}

# Revisa si el bloqueo temporal (activado por exceso de reinicios) ya
# cumplió su tiempo, o si alguien lo borró a mano. En cualquiera de los dos
# casos, restaura todos los contenedores y limpia el estado de bloqueo.
# Se llama en cada vuelta del loop principal mientras BLOQUEADO exista, así
# que el monitoreo de CPU nunca se detiene mientras se espera.
verificar_fin_bloqueo() {
  if [ ! -f "$BLOQUEADO" ]; then
    return
  fi

  local creado ahora limite
  creado=$(stat -c %Y "$BLOQUEADO" 2>/dev/null || echo 0)
  ahora=$(date +%s)
  limite=$((creado + BLOQUEO_ESPERA_MINUTOS * 60))

  if [ "$ahora" -ge "$limite" ]; then
    log "Se cumplieron ${BLOQUEO_ESPERA_MINUTOS} minuto(s) de bloqueo. Restaurando todos los contenedores automáticamente."
    rm -f "$BLOQUEADO"
    restaurar_contenedores
    log "Bloqueo levantado. El ciclo de monitoreo continúa normal."
  fi
}

# ---------------------- Restauración tras reinicio ----------------------
# Si al arrancar existe el marcador, significa que en el arranque anterior
# se llegó al Nivel 2 y se programó este reinicio. Restauramos antes de
# entrar al loop de monitoreo normal.
if [ -f "$MARCADOR_RESTAURAR" ]; then
  if [ -f "$ARCHIVO_INCIDENTE_ACTUAL" ]; then
    INCIDENTE_ACTUAL="$(cat "$ARCHIVO_INCIDENTE_ACTUAL")"
  fi
  restaurar_contenedores
fi

# ---------------------- Loop principal ----------------------
log "cpu-guard iniciado. Umbral=${UMBRAL}% sostenido ${SEGUNDOS_SOSTENIDOS}s (Nivel 1) / ${SEGUNDOS_ESCALADA}s adicionales (Nivel 2, incluye Coolify + reinicio automático)."
contador=0
ultimo_disparo=0
while true; do
  # Si hay un bloqueo temporal activo (por exceso de reinicios), el
  # monitoreo de CPU sigue leyendo con normalidad, pero no se dispara
  # ninguna acción nueva hasta que se cumpla la hora de espera (o alguien
  # borre el bloqueo a mano). verificar_fin_bloqueo se encarga de eso y,
  # en cuanto se cumple, restaura los contenedores y el ciclo sigue igual
  # que siempre.
  verificar_fin_bloqueo

  uso=$(obtener_uso_cpu)
  ahora=$(date +%s)

  if [ "$uso" -ge "$UMBRAL" ]; then
    contador=$((contador + 1))
  else
    contador=0
  fi

  if [ "$contador" -ge "$LECTURAS_NECESARIAS" ] && [ ! -f "$BLOQUEADO" ]; then
    tiempo_desde_ultimo=$((ahora - ultimo_disparo))
    if [ "$tiempo_desde_ultimo" -ge "$COOLDOWN_SEGUNDOS" ]; then
      iniciar_incidente
      capturar_snapshot_actual
      detener_contenedores_no_coolify
      ultimo_disparo=$ahora
      verificar_escalada
    fi
    contador=0
  fi

  sleep "$INTERVALO"
done