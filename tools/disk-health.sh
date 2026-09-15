#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# Загрузка вспомогательных библиотек и функций Proxmox VE Helper Scripts
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/refs/heads/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func) 2>/dev/null || true
load_functions
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "disk-health" "pve"

# Вывод графического ASCII-логотипа в терминале
function header_info {
  clear
  cat <<"EOF"
    ____  _      __      __  __           ____  __
   / __ \(_)____/ /__   / / / /__  ____ _/ / /_/ /_
  / / / / / ___/ //_/  / /_/ / _ \/ __ `/ / __/ __ \
 / /_/ / (__  ) ,<    / __  /  __/ /_/ / / /_/ / / /
/_____/_/____/_/|_|  /_/ /_/\___/\__,_/_/\__/_/ /_/

EOF
}

header_info

# Проверка запуска с правами суперпользователя (root)
if [ "$(id -u)" -ne 0 ]; then
  msg_error "Этот скрипт должен быть запущен от имени root."
  exit 1
fi

# Проверка наличия среды Proxmox VE
if ! command -v pveversion >/dev/null 2>&1; then
  msg_error "Среда Proxmox VE не обнаружена!"
  exit 1
fi

# Проверка и автоматическая установка необходимых утилит
if ! command -v smartctl >/dev/null 2>&1; then
  msg_info "Установка пакета smartmontools..."
  apt-get update &>/dev/null
  if apt-get install -y smartmontools &>/dev/null; then
    msg_ok "Пакет smartmontools успешно установлен"
  else
    msg_error "Не удалось установить smartmontools"
    exit 1
  fi
fi
if ! command -v nvme >/dev/null 2>&1; then
  msg_info "Установка пакета nvme-cli..."
  if apt-get install -y nvme-cli &>/dev/null; then
    msg_ok "Пакет nvme-cli успешно установлен"
  else
    msg_error "nvme-cli недоступен (сведения о накопителях NVMe могут быть ограничены)"
  fi
fi

# Сбор списка физических накопителей (исключаем loop, zram и device-mapper)
mapfile -t DISKS < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1}' | grep -vE '^(loop|zram|dm-)' | sort)

if [ "${#DISKS[@]}" -eq 0 ]; then
  msg_error "Физические накопители не найдены."
  exit 0
fi

# Функция извлечения значения конкретного SMART-атрибута для SATA/SAS накопителей
sata_attr() {
  local output="$1" name="$2"
  echo "$output" | awk -v n="$name" '$2==n {print $10; exit}'
}

# Функция форматирования и отображения отчёта о состоянии накопителя
report_disk() {
  local dev="$1"
  local path="/dev/${dev}"
  local model size health
  model=$(lsblk -dn -o MODEL "$path" 2>/dev/null | sed 's/[[:space:]]*$//')
  size=$(lsblk -dn -o SIZE "$path" 2>/dev/null | tr -d ' ')

  echo -e "\n${BL}======================================================${CL}"
  echo -e "${GN}${path}${CL}  ${YW}${size:-?}${CL}  ${model:-Неизвестная модель}"
  echo -e "${BL}======================================================${CL}"

  # Оценка общего состояния накопителя (SMART Health Status)
  health=$(smartctl -H "$path" 2>/dev/null | grep -iE "SMART overall-health|SMART Health Status" | sed 's/.*: *//')
  if [ -z "$health" ]; then
    echo -e "  Состояние:                   ${YW}SMART недоступен для этого устройства${CL}"
  elif echo "$health" | grep -qiE "PASSED|OK"; then
    echo -e "  Состояние:                   ${GN}Исправен (${health})${CL}"
  else
    echo -e "  Состояние:                   ${RD}Внимание: ${health}${CL}"
  fi

  if [[ "$dev" == nvme* ]]; then
    local a
    a=$(smartctl -A "$path" 2>/dev/null)
    
    # Парсинг и локализация ключевых показателей NVMe
    local temp spare used written poh shutdowns errors
    temp=$(echo "$a" | grep -i "Temperature:" | sed 's/.*Temperature:[[:space:]]*//')
    spare=$(echo "$a" | grep -i "Available Spare:" | sed 's/.*Available Spare:[[:space:]]*//')
    used=$(echo "$a" | grep -i "Percentage Used:" | sed 's/.*Percentage Used:[[:space:]]*//')
    written=$(echo "$a" | grep -i "Data Units Written:" | sed 's/.*Data Units Written:[[:space:]]*//')
    poh=$(echo "$a" | grep -i "Power On Hours:" | sed 's/.*Power On Hours:[[:space:]]*//')
    shutdowns=$(echo "$a" | grep -i "Unsafe Shutdowns:" | sed 's/.*Unsafe Shutdowns:[[:space:]]*//')
    errors=$(echo "$a" | grep -i "Media and Data Integrity Errors:" | sed 's/.*Media and Data Integrity Errors:[[:space:]]*//')

    [ -n "$temp" ] && echo -e "  Температура:                 ${temp}"
    [ -n "$spare" ] && echo -e "  Доступный резерв:            ${spare}"
    [ -n "$used" ] && echo -e "  Использованный ресурс:       ${used}"
    [ -n "$written" ] && echo -e "  Записано данных:             ${written}"
    [ -n "$poh" ] && echo -e "  Время работы (часы):         ${poh}"
    [ -n "$shutdowns" ] && echo -e "  Небезопасных отключений:     ${shutdowns}"
    if [ -n "$errors" ]; then
      if [ "$errors" -gt 0 ] 2>/dev/null; then
        echo -e "  Ошибки целостности данных:   ${RD}${errors}${CL}"
      else
        echo -e "  Ошибки целостности данных:   ${GN}${errors}${CL}"
      fi
    fi
  else
    local a poh temp realloc pending offline crc wear
    a=$(smartctl -A "$path" 2>/dev/null)
    poh=$(sata_attr "$a" "Power_On_Hours")
    temp=$(sata_attr "$a" "Temperature_Celsius")
    realloc=$(sata_attr "$a" "Reallocated_Sector_Ct")
    pending=$(sata_attr "$a" "Current_Pending_Sector")
    offline=$(sata_attr "$a" "Offline_Uncorrectable")
    crc=$(sata_attr "$a" "UDMA_CRC_Error_Count")
    wear=$(sata_attr "$a" "Wear_Leveling_Count")
    [ -z "$wear" ] && wear=$(sata_attr "$a" "Media_Wearout_Indicator")

    [ -n "$temp" ] && echo -e "  Температура:                 ${temp} °C"
    [ -n "$poh" ] && echo -e "  Время работы (часы):         ${poh}"
    [ -n "$wear" ] && echo -e "  Износ накопителя (%):        ${wear}"
    print_attr() {
      local label="$1" val="$2"
      [ -z "$val" ] && return
      if [ "$val" -gt 0 ] 2>/dev/null; then
        echo -e "  ${label} ${RD}${val}${CL}"
      else
        echo -e "  ${label} ${GN}${val}${CL}"
      fi
    }
    print_attr "Переназначенные секторы:    " "$realloc"
    print_attr "Нестабильные секторы:       " "$pending"
    print_attr "Неисправимые ошибки:        " "$offline"
    print_attr "Ошибки UDMA CRC:            " "$crc"
  fi
}

header_info
echo -e "${YW}Сканирование состояния SMART для ${#DISKS[@]} накопител(я/ей)...${CL}"
for d in "${DISKS[@]}"; do
  report_disk "$d"
done
echo

# Диалог для запуска короткого теста самодиагностики SMART
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Самодиагностика SMART" \
  --yesno "Отчёт о состоянии накопителей сформирован.\n\nЗапустить короткий безопасный тест самодиагностики (SHORT SMART self-test) для одного из накопителей?\n\n(Тест выполняется в фоновом режиме. Результаты можно проверить позже командой: smartctl -a /dev/XXX)" 14 70; then
  TEST_MENU=()
  for d in "${DISKS[@]}"; do
    TEST_MENU+=("$d" "/dev/$d" "OFF")
  done
  sel=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Выбор накопителя для короткого теста SMART" \
    --radiolist "\nВыберите накопитель:\n" 16 60 6 "${TEST_MENU[@]}" 3>&1 1>&2 2>&3 | tr -d '"')
  if [ -n "$sel" ]; then
    msg_info "Запуск короткого теста самодиагностики на /dev/$sel..."
    if smartctl -t short "/dev/$sel" &>/dev/null; then
      msg_ok "Короткий тест самодиагностики запущен на /dev/$sel"
      echo -e "${YW}Проверить ход выполнения и результат: ${GN}smartctl -a /dev/$sel${CL}"
    else
      msg_error "Не удалось запустить тест самодиагностики на /dev/$sel"
    fi
  fi
fi

echo -e "\n${GN}Проверка состояния дисков успешно завершена.${CL}\n"
