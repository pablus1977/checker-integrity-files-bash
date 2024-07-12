#!/bin/bash

# Directorio base de los archivos a ser monitoreados
BASEDIR_MONITOR="/var/www/"

# La estructura de archivos de backup (good) debe ser igual a la de archivos a monitorear
BASEBACKUPGOOD="/var/www/maintenance/checkfiles/good/"

# Directorio en el que se guardarán los archivos de los que se detectó modificacion para ser analizados posteriormente.
# Ningun archivo en bad se sobreescribe, sino que se crean archivos con sufijos numericos incrementales, para un mejor analisis posterior
BASEBACKUPBAD="/var/www/maintenance/checkfiles/bad/"

# Directorio base de esta aplicacion
BASEDIR="/var/www/maintenance/checkfiles/"

# Definir listas de archivos a monitorear y sus backups correspondientes (indentica estructura de directorios a partir del dir base).
# definir uno en cada fila, sin separar con comas
FILES_TO_MONITOR=(
  "require_js.phtml"
)

# log
LOG_FILE="${BASEDIR}monitor.log"

RESTORE_INTERVAL=10  # Intervalo mínimo entre restauraciones en segundos

# Función para monitorear y restaurar archivos
monitor_and_restore() {
  local file_to_monitor=$1
  local backup_file=$2
  local backup_badfile=$3

  # Bandera temporal para evitar bucles infinitos
  local restore_in_progress=false
  local last_restore_time=0

  inotifywait -m -e modify "$file_to_monitor" | while read -r directory events filename; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    current_time=$(date +%s)

    if [ "$restore_in_progress" = true ]; then
      echo "$TIMESTAMP - Skipping modification in $file_to_monitor due to restoration in progress" >> "$LOG_FILE"
      restore_in_progress=false
      continue
    fi

    if (( current_time - last_restore_time < RESTORE_INTERVAL )); then
      echo "$TIMESTAMP - Skipping modification in $file_to_monitor due to restore interval" >> "$LOG_FILE"
      continue
    fi

    echo "$TIMESTAMP - Detected modification in $file_to_monitor" >> "$LOG_FILE"

    # Asegurarse de que el directorio de destino exista antes de copiar el archivo malo
    mkdir -p "$(dirname "$backup_badfile")"

    # Verificar si el archivo de destino existe y agregar sufijo numérico si es necesario
    if [ -e "$backup_badfile" ]; then
      suffix=1
      while [ -e "${backup_badfile}.${suffix}" ]; do
        ((suffix++))
      done
      backup_badfile="${backup_badfile}.${suffix}"
    fi

    cp "$file_to_monitor" "$backup_badfile"
    if [ $? -eq 0 ]; then
      echo "$TIMESTAMP - Copied $file_to_monitor to $backup_badfile" >> "$LOG_FILE"
    else
      echo "$TIMESTAMP - Failed to copy $file_to_monitor to $backup_badfile" >> "$LOG_FILE"
    fi

    # Verificar si el archivo de respaldo existe antes de intentar restaurarlo
    if [ -e "$backup_file" ]; then
      restore_in_progress=true
      last_restore_time=$current_time
      cp "$backup_file" "$file_to_monitor"
      if [ $? -eq 0 ]; then
        echo "$TIMESTAMP - Restored $file_to_monitor from backup" >> "$LOG_FILE"
      else
        echo "$TIMESTAMP - Failed to restore $file_to_monitor from backup" >> "$LOG_FILE"
      fi
      sleep 1  # Añadir un pequeño retraso para evitar múltiples restauraciones rápidas
    else
      echo "$TIMESTAMP - Backup file $backup_file does not exist. Skipping restore." >> "$LOG_FILE"
    fi
  done
}

# Iterar sobre la lista de archivos y ejecutar la función en segundo plano para cada uno
for i in "${!FILES_TO_MONITOR[@]}"; do
  monitor_and_restore "${BASEDIR_MONITOR}${FILES_TO_MONITOR[i]}" "${BASEBACKUPGOOD}${FILES_TO_MONITOR[i]}" "${BASEBACKUPBAD}${FILES_TO_MONITOR[i]}" &
done

# Esperar a que todos los procesos en segundo plano terminen (si es necesario)
wait
