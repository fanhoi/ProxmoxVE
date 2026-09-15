#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# Вывод ASCII-логотипа утилиты
function header_info {
  clear
  cat <<"EOF"
    ____                                          ________                    ____             __                         __   __ _    ____  ___    
   / __ \_________  _  ______ ___  ____  _  __   / ____/ /__  ____ _____     / __ \_________  / /_  ____ _____  ___  ____/ /  / /| |  / /  |/  /____
  / /_/ / ___/ __ \| |/_/ __ `__ \/ __ \| |/_/  / /   / / _ \/ __ `/ __ \   / / / / ___/ __ \/ __ \/ __ `/ __ \/ _ \/ __  /  / / | | / / /|_/ / ___/
 / ____/ /  / /_/ />  </ / / / / / /_/ />  <   / /___/ /  __/ /_/ / / / /  / /_/ / /  / /_/ / / / / /_/ / / / /  __/ /_/ /  / /__| |/ / /  / (__  ) 
/_/   /_/   \____/_/|_/_/ /_/ /_/\____/_/|_|   \____/_/\___/\__,_/_/ /_/   \____/_/  / .___/_/ /_/\__,_/_/ /_/\___/\__,_/  /_____/___/_/  /_/____/  
                                                                                    /_/                                                             
 Очистка неиспользуемых (осиротевших) LVM-томов Proxmox VE
EOF
}

# Инициализация телеметрии (если поддерживается)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func) 2>/dev/null || true
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "clean-orphaned-lvm" "pve"

# Проверка прав суперпользователя (root)
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\n❌ Ошибка: этот скрипт должен быть запущен от имени root.\n"
  exit 1
fi

# Поиск неиспользуемых LVM-томов, оставшихся после удаления виртуальных машин или контейнеров
function find_orphaned_lvm {
  echo -e "\n🔍 Сканирование системы на наличие осиротевших LVM-томов...\n"

  orphaned_volumes=()
  while read -r lv vg size seg_type; do
    # Исключаем системные разделы и OSD Ceph
    if [[ "$lv" == "data" || "$lv" == "root" || "$lv" == "swap" || "$lv" =~ ^osd-block- ]]; then
      continue
    fi

    # Исключаем пулы тонких томов (thin-pool)
    if [[ "$seg_type" == "thin-pool" ]]; then
      continue
    fi

    container_id=$(echo "$lv" | grep -oE "[0-9]+" | head -1)
    
    # Если в имени тома нет числового ID — пропускаем
    if [[ -z "$container_id" ]]; then
      continue
    fi

    # Проверяем наличие конфигурационного файла на любой ноде кластера PVE
    if compgen -G "/etc/pve/nodes/*/lxc/${container_id}.conf" >/dev/null 2>&1 ||
      compgen -G "/etc/pve/nodes/*/qemu-server/${container_id}.conf" >/dev/null 2>&1; then
      continue
    fi

    orphaned_volumes+=("$lv" "$vg" "$size")
  done < <(lvs --noheadings -o lv_name,vg_name,lv_size,seg_type --separator ' ' 2>/dev/null | awk '{print $1, $2, $3, $4}')

  # Вывод найденных осиротевших томов
  if [ "${#orphaned_volumes[@]}" -eq 0 ]; then
    echo -e "✅ Осиротевших LVM-томов не обнаружено. Все тома привязаны к существующим ВМ и контейнерам.\n"
    return 0
  fi

  echo -e "❗ Обнаружены следующие неиспользуемые (осиротевшие) LVM-тома:\n"
  printf "%-30s %-15s %-10s\n" "Имя LVM-тома (LV)" "Группа (VG)" "Размер"
  printf "%-30s %-15s %-10s\n" "------------------------------" "---------------" "----------"

  for ((i = 0; i < ${#orphaned_volumes[@]}; i += 3)); do
    printf "%-30s %-15s %-10s\n" "${orphaned_volumes[i]}" "${orphaned_volumes[i + 1]}" "${orphaned_volumes[i + 2]}"
  done
  echo ""
}

# Функция удаления выбранных пользователем томов
function delete_orphaned_lvm {
  if [ "${#orphaned_volumes[@]}" -eq 0 ]; then
    return 0
  fi

  for ((i = 0; i < ${#orphaned_volumes[@]}; i += 3)); do
    lv="${orphaned_volumes[i]}"
    vg="${orphaned_volumes[i + 1]}"
    size="${orphaned_volumes[i + 2]}"

    read -p "❓ Удалить LVM-том $lv (VG: $vg, Размер: $size)? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo -e "🗑️  Удаление тома $lv из группы $vg..."
      if lvremove -f "$vg/$lv"; then
        echo -e "✅ Том $lv успешно удален.\n"
      else
        echo -e "❌ Не удалось удалить том $lv.\n"
      fi
    else
      echo -e "⚠️  Пропуск тома $lv.\n"
    fi
  done
}

# Основной поток выполнения
header_info
find_orphaned_lvm
delete_orphaned_lvm

echo -e "✅ Процесс проверки и очистки LVM завершен!\n"
