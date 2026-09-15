#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# Вывод ASCII-логотипа утилиты
function header_info {
  clear
  cat <<"EOF"
   ______                __     ____       __     __
  / ____/_  _____  _____/ /_   / __ \___  / /__  / /____
 / / __/ / / / _ \/ ___/ __/  / / / / _ \/ / _ \/ __/ _ \
/ /_/ / /_/ /  __(__  ) /_   / /_/ /  __/ /  __/ /_/  __/
\____/\__,_/\___/____/\__/  /_____/\___/_/\___/\__/\___/ 

 Массовое удаление LXC-контейнеров и ВМ Proxmox VE
EOF
}

# Анимация ожидания завершения фонового процесса
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while ps -p $pid >/dev/null; do
    printf " [%c]  " "$spinstr"
    spinstr=${spinstr#?}${spinstr%"${spinstr#?}"}
    sleep $delay
    printf "\r"
  done
  printf "    \r"
}

set -eEuo pipefail
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
TAB="  "
CM="${TAB}✔️${TAB}${CL}"

# Инициализация телеметрии (если поддерживается)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func) 2>/dev/null || true
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "guest-delete" "pve"

GUEST_LOG=$(mktemp)
trap 'rm -f "$GUEST_LOG"' EXIT

# Остановка гостевой системы (LXC контейнера или виртуальной машины)
stop_guest() {
  local type=$1 id=$2 pid
  if [ "$type" == "ct" ]; then
    pct stop "$id" >"$GUEST_LOG" 2>&1 &
  else
    qm stop "$id" >"$GUEST_LOG" 2>&1 &
  fi
  pid=$!
  spinner "$pid"
  wait "$pid" || true
}

# Полное удаление и очистка дисков гостевой системы
destroy_guest() {
  local type=$1 id=$2 pid
  if [ "$type" == "ct" ]; then
    pct destroy "$id" -f >"$GUEST_LOG" 2>&1 &
  else
    qm destroy "$id" --purge --destroy-unreferenced-disks >"$GUEST_LOG" 2>&1 &
  fi
  pid=$!
  spinner "$pid"
  wait "$pid"
}

header_info
echo "Загрузка списка гостевых систем..."
whiptail --backtitle "Proxmox VE Helper Scripts" --title "Удаление гостевых систем Proxmox VE" \
  --yesno "Внимание! Этот скрипт позволяет массово удалить LXC-контейнеры и/или виртуальные машины (ВМ).\n\nВы действительно хотите продолжить?" 11 65

NODE=$(hostname)
containers=$(pct list 2>/dev/null | tail -n +2 || true)
vms=$(qm list 2>/dev/null | tail -n +2 || true)

if [ -z "$containers" ] && [ -z "$vms" ]; then
  whiptail --title "Удаление гостевых систем" --msgbox "В системе не найдено ни одного LXC-контейнера или виртуальной машины!" 10 65
  exit 234
fi

declare -A GUEST_TYPE=()
menu_items=()
FORMAT="%-4s %-20s %-10s"

# Сбор списка доступных LXC контейнеров
if [ -n "$containers" ]; then
  menu_items+=("ALL-CT" "$(printf "$FORMAT" "CT" "Удалить ВСЕ контейнеры" "")" "OFF")
  while read -r line; do
    [ -z "$line" ] && continue
    container_id=$(awk '{print $1}' <<<"$line")
    container_status=$(awk '{print $2}' <<<"$line")
    container_name=$(awk '{print $NF}' <<<"$line")
    GUEST_TYPE[$container_id]="ct"
    menu_items+=("$container_id" "$(printf "$FORMAT" "CT" "$container_name" "$container_status")" "OFF")
  done <<<"$containers"
fi

# Сбор списка доступных виртуальных машин
if [ -n "$vms" ]; then
  menu_items+=("ALL-VM" "$(printf "$FORMAT" "VM" "Удалить ВСЕ виртуальные машины" "")" "OFF")
  while read -r line; do
    [ -z "$line" ] && continue
    vm_id=$(awk '{print $1}' <<<"$line")
    vm_name=$(awk '{print $2}' <<<"$line")
    vm_status=$(awk '{print $3}' <<<"$line")
    GUEST_TYPE[$vm_id]="vm"
    menu_items+=("$vm_id" "$(printf "$FORMAT" "VM" "$vm_name" "$vm_status")" "OFF")
  done <<<"$vms"
fi

# Интерактивное меню выбора объектов для удаления
CHOICES=$(whiptail --title "Выбор гостевых систем" \
  --checklist "Отметьте пробелом LXC-контейнеры и виртуальные машины для удаления:" 25 75 13 \
  "${menu_items[@]}" 3>&2 2>&1 1>&3 || true)

if [ -z "$CHOICES" ]; then
  whiptail --title "Удаление гостевых систем" \
    --msgbox "Ни одной гостевой системы не выбрано. Выход." 10 60
  exit 0
fi

read -p "Режим удаления: с подтверждением каждого (m) или автоматически все выбранные (a)? (По умолчанию: m) [m/a]: " DELETE_MODE
DELETE_MODE=${DELETE_MODE:-m}

# Раскрытие пунктов ALL-CT и ALL-VM с защитой от дублирования ID
expanded_ids=""
for choice in $(echo "$CHOICES" | tr -d '"' | tr -s ' ' '\n'); do
  case "$choice" in
  ALL-CT) expanded_ids+=$'\n'$(awk '{print $1}' <<<"$containers") ;;
  ALL-VM) expanded_ids+=$'\n'$(awk '{print $1}' <<<"$vms") ;;
  *) expanded_ids+=$'\n'"$choice" ;;
  esac
done
selected_ids=$(echo "$expanded_ids" | sed '/^$/d' | awk '!seen[$0]++')

# Итерация по выбранным системам и выполнение удаления
for guest_id in $selected_ids; do
  guest_type="${GUEST_TYPE[$guest_id]:-}"
  if [ -z "$guest_type" ]; then
    echo -e "${BL}[Инфо]${RD} Пропуск неизвестного объекта $guest_id...${CL}"
    continue
  fi

  if [ "$guest_type" == "ct" ]; then
    label="LXC-контейнер $guest_id"
  else
    label="ВМ $guest_id"
  fi

  if [[ "$DELETE_MODE" == "a" ]]; then
    echo -e "${BL}[Инфо]${GN} Автоматическое удаление: $label...${CL}"
  else
    read -p "Удалить $label? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
      echo -e "${BL}[Инфо]${RD} Пропуск: $label...${CL}"
      continue
    fi
    echo -e "${BL}[Инфо]${GN} Удаление: $label...${CL}"
  fi

  # Проверка статуса: если система работает, сначала останавливаем её
  if [ "$guest_type" == "ct" ]; then
    status=$(pct status "$guest_id" 2>/dev/null || echo "unknown")
  else
    status=$(qm status "$guest_id" 2>/dev/null || echo "unknown")
  fi

  if [ "$status" == "status: running" ]; then
    echo -e "${BL}[Инфо]${GN} Остановка: $label...${CL}"
    stop_guest "$guest_type" "$guest_id"
    echo -e "${BL}[Инфо]${GN} $label успешно остановлен(а).${CL}"
  fi

  # Окончательное уничтожение конфигурации и очистка дисков
  if destroy_guest "$guest_type" "$guest_id"; then
    echo -e "${CM}${GN}$label успешно удален(а).${CL}"
  else
    whiptail --title "Ошибка удаления" --msgbox "Не удалось удалить ${label}.\n\n$(tail -n 5 "$GUEST_LOG")" 15 70
  fi
done

header_info
echo -e "${GN}Процесс удаления гостевых систем успешно завершен.${CL}\n"
