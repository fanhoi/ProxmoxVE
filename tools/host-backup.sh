#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info {
  clear
  cat <<"EOF"
   __ __         __    ___           __
  / // /__  ___ / /_  / _ )___ _____/ /____ _____
 / _  / _ \(_-</ __/ / _  / _ `/ __/  '_/ // / _ \
/_//_/\___/___/\__/ /____/\_,_/\__/_/\_\\_,_/ .__/
                                           /_/

 Резервное копирование файлов и конфигураций хоста Proxmox VE
EOF
}

# Telemetry
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func) 2>/dev/null || true
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "host-backup" "pve"

# Function to perform backup
function perform_backup {
  local BACKUP_PATH
  local DIR
  local DIR_DASH
  local BACKUP_FILE
  local selected_directories=()

  # Get backup path from user
  BACKUP_PATH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "\nПо умолчанию: /root/\nнапример: /mnt/backups/" 11 68 --title "Директория для сохранения бэкапа:" 3>&1 1>&2 2>&3) || return

  # Default to /root/ if no input
  BACKUP_PATH="${BACKUP_PATH:-/root/}"

  # Get directory to work in from user
  DIR=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "\nПо умолчанию: /etc/\nнапример: /root/, /var/lib/pve-cluster/ и т.д." 11 68 --title "Исходная директория для бэкапа:" 3>&1 1>&2 2>&3) || return

  # Default to /etc/ if no input
  DIR="${DIR:-/etc/}"

  DIR_DASH=$(echo "$DIR" | tr '/' '-')
  BACKUP_FILE="$(hostname)${DIR_DASH}backup"

  # Build a list of directories for backup
  local CTID_MENU=()
  CTID_MENU=("ALL" "Архивировать все папки" "OFF")
  while read -r dir; do
    CTID_MENU+=("$(basename "$dir")" "$dir " "OFF")
  done < <(ls -d "${DIR}"*)

  # Allow the user to select directories
  local HOST_BACKUP
  while [ -z "${HOST_BACKUP:+x}" ]; do
    HOST_BACKUP=$(whiptail --backtitle "Резервное копирование хоста Proxmox VE" --title "Работа в директории ${DIR} " --checklist \
      "\nВыберите файлы/директории для бэкапа:\n" 16 78 6 "${CTID_MENU[@]}" 3>&1 1>&2 2>&3) || return

    for selected_dir in ${HOST_BACKUP//\"/}; do
      if [[ "$selected_dir" == "ALL" ]]; then
        # if ALL was chosen, secure all folders
        selected_directories=("${DIR}"*/)
        break
      else
        selected_directories+=("${DIR}$selected_dir")
      fi
    done
  done

  # Perform the backup
  header_info
  echo -e "Будет создан архив в\e[1;33m $BACKUP_PATH \e[0mдля следующих файлов и директорий:\e[1;33m ${selected_directories[*]} \e[0m"
  read -p "Нажмите ENTER для продолжения..."
  header_info
  echo "Создание бэкапа..."
  tar -czf "$BACKUP_PATH$BACKUP_FILE-$(date +%Y_%m_%dT%H_%M).tar.gz" --absolute-names "${selected_directories[@]}"
  header_info
  echo -e "\nЗавершено"
  echo -e "\e[1;33m \nРезервная копия не защитит систему, если остается только на самом хосте.\n \e[0m"
  sleep 2
}

# Main script execution loop
while true; do
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Резервное копирование хоста Proxmox VE" --yesno "Будут созданы резервные копии выбранных файлов и директорий в указанной папке. Продолжить?" 10 88); then
    perform_backup
  else
    break
  fi
done
