#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# Вывод ASCII-логотипа утилиты
function header_info {
  clear
  cat <<"EOF"
   __ __         __    ___           __
  / // /__  ___ / /_  / _ )___ _____/ /____ _____
 / _  / _ \(_-</ __/ / _  / _ `/ __/  '_/ // / _ \
/_//_/\___/___/\__/ /____/\_,_/\__/_/\_\\_,_/ .__/
                                           /_/

 Резервное копирование конфигураций и файлов хоста Proxmox VE
EOF
}

# Инициализация телеметрии (если поддерживается)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func) 2>/dev/null || true
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "host-backup" "pve"

# Проверка запуска от имени суперпользователя (root)
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\n❌ Ошибка: этот скрипт должен быть запущен от имени root.\n"
  exit 1
fi

# Функция выполнения резервного копирования
function perform_backup {
  local BACKUP_PATH
  local DIR
  local DIR_DASH
  local BACKUP_FILE
  local selected_directories=()

  # Запрос пути для сохранения резервной копии
  BACKUP_PATH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "\nУкажите путь для сохранения архива.\nПо умолчанию: /root/\nПример: /mnt/backups/ или /mnt/pve/storage/" 11 68 --title "Куда сохранить резервную копию:" 3>&1 1>&2 2>&3) || return

  BACKUP_PATH="${BACKUP_PATH:-/root/}"
  [[ "$BACKUP_PATH" != */ ]] && BACKUP_PATH="${BACKUP_PATH}/"

  # Проверка существования директории назначения
  if [ ! -d "$BACKUP_PATH" ]; then
    mkdir -p "$BACKUP_PATH" 2>/dev/null || {
      whiptail --title "Ошибка" --msgbox "Не удалось создать целевую директорию: $BACKUP_PATH" 10 60
      return
    }
  fi

  # Запрос рабочей директории для архивации
  DIR=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "\nУкажите исходную директорию для бэкапа.\nПо умолчанию: /etc/\nПримеры: /etc/, /root/, /var/lib/pve-cluster/" 11 68 --title "Исходная директория для архивации:" 3>&1 1>&2 2>&3) || return

  DIR="${DIR:-/etc/}"
  [[ "$DIR" != */ ]] && DIR="${DIR}/"

  if [ ! -d "$DIR" ]; then
    whiptail --title "Ошибка" --msgbox "Директория не существует: $DIR" 10 60
    return
  fi

  DIR_DASH=$(echo "$DIR" | tr '/' '-')
  BACKUP_FILE="$(hostname)${DIR_DASH}backup"

  # Формирование списка объектов для архивации
  local CTID_MENU=()
  CTID_MENU=("ALL" "Архивировать ВСЕ папки в ${DIR}" "OFF")
  while read -r dir; do
    [ -z "$dir" ] && continue
    CTID_MENU+=("$(basename "$dir")" "$dir " "OFF")
  done < <(ls -d "${DIR}"* 2>/dev/null)

  if [ ${#CTID_MENU[@]} -le 3 ]; then
    whiptail --title "Внимание" --msgbox "В директории $DIR не найдено файлов или подпапок." 10 60
    return
  fi

  # Меню выбора папок
  local HOST_BACKUP
  while [ -z "${HOST_BACKUP:+x}" ]; do
    HOST_BACKUP=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Выбор файлов в ${DIR}" --checklist \
      "\nОтметьте пробелом файлы и папки для резервного копирования:\n" 18 80 8 "${CTID_MENU[@]}" 3>&1 1>&2 2>&3) || return

    for selected_dir in ${HOST_BACKUP//\"/}; do
      if [[ "$selected_dir" == "ALL" ]]; then
        selected_directories=("${DIR}"*/)
        break
      else
        selected_directories+=("${DIR}$selected_dir")
      fi
    done
  done

  # Подтверждение и выполнение архивации
  header_info
  echo -e "Архив будет сохранен в: \e[1;33m${BACKUP_PATH}\e[0m"
  echo -e "Объекты для архивации:   \e[1;33m${selected_directories[*]}\e[0m\n"
  read -p "Нажмите ENTER для запуска архивации..."

  header_info
  echo -e "⏳ Создание резервной копии (tar.gz)..."
  local ARCHIVE_NAME="${BACKUP_PATH}${BACKUP_FILE}-$(date +%Y_%m_%dT%H_%M).tar.gz"

  if tar -czf "$ARCHIVE_NAME" --absolute-names "${selected_directories[@]}" 2>/dev/null; then
    header_info
    echo -e "✅ Резервное копирование успешно завершено!\n"
    echo -e "📦 Создан архив: \e[1;32m${ARCHIVE_NAME}\e[0m"
    echo -e "📏 Размер архива: \e[1;33m$(du -h "$ARCHIVE_NAME" | awk '{print $1}')\e[0m\n"
    echo -e "\e[1;33m💡 Совет: Не храните резервные копии только на хосте. Перенесите архив на внешнее хранилище, NFS/SMB или PBS.\e[0m\n"
  else
    echo -e "❌ Ошибка при создании архива!\n"
  fi

  read -p "Нажмите ENTER для продолжения..."
}

# Основной цикл работы
while true; do
  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Резервное копирование хоста Proxmox VE" \
    --yesno "Этот мастер позволяет создать тар-архив (tar.gz) важных конфигураций и файлов хоста Proxmox VE.\n\nПродолжить?" 11 75; then
    perform_backup
  else
    break
  fi
done

header_info
echo -e "Работа мастера завершена.\n"
