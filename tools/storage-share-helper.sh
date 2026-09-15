#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# Загрузка вспомогательных библиотек Proxmox VE Helper Scripts
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/refs/heads/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func) 2>/dev/null || true
load_functions
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "storage-share-helper" "pve"

set -eEuo pipefail

# Вывод графического заголовка утилиты
function header_info() {
  clear
  cat <<"EOF"
    _____ __                                 ___    _________ 
   / ___// /_____  _________ _____ ____     /   |  /  _/ __ \
   \__ \/ __/ __ \/ ___/ __ `/ __ `/ _ \   / /| |  / // / / /
  ___/ / /_/ /_/ / /  / /_/ / /_/ /  __/  / ___ |_/ // /_/ / 
 /____/\__/\____/_/   \__,_/\__, /\___/  /_/  |_/___/_____/  
                            /____/                            

 Управление хранилищами и общими ресурсами Proxmox VE
 SMB | NFS | iSCSI | LVM-на-iSCSI | Точки монтирования LXC | Ресурсы хоста
EOF
}

pause() {
  read -r -p "Нажмите Enter для продолжения..." _
}

# Проверка наличия необходимых утилит Proxmox VE
require_pve() {
  if ! command -v pct >/dev/null 2>&1 || ! command -v pvesm >/dev/null 2>&1; then
    msg_error "Этот скрипт должен быть запущен на хосте Proxmox VE (утилиты pct/pvesm не найдены)."
    exit 1
  fi
}

# Проверка и установка необходимых пакетов
ensure_packages() {
  local packages=()

  command -v whiptail >/dev/null 2>&1 || packages+=("whiptail")
  command -v mount.cifs >/dev/null 2>&1 || packages+=("cifs-utils")
  command -v showmount >/dev/null 2>&1 || packages+=("nfs-common")
  command -v iscsiadm >/dev/null 2>&1 || packages+=("open-iscsi")

  if [[ ${#packages[@]} -gt 0 ]]; then
    msg_info "Установка необходимых пакетов: ${packages[*]}"
    apt update >/dev/null 2>&1
    apt install -y "${packages[@]}" >/dev/null 2>&1
    msg_ok "Зависимости успешно установлены"
  fi
}

confirm_start() {
  whiptail --backtitle "Proxmox VE Helper Scripts" --title "Мастер хранилищ и общих ресурсов" \
    --yesno "Этот мастер позволяет тестировать и подключать SMB/NFS/iSCSI, создавать и удалять хранилища Proxmox, настраивать точки монтирования (bind mount) для LXC и создавать общие папки на хосте.\n\nПродолжить?" 13 100
}

read_input() {
  local title="$1"
  local prompt="$2"
  local default_value="${3:-}"

  whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" \
    --inputbox "$prompt" 11 100 "$default_value" 3>&1 1>&2 2>&3
}

read_password() {
  local title="$1"
  local prompt="$2"

  whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" \
    --passwordbox "$prompt" 11 100 3>&1 1>&2 2>&3
}

confirm_yes_no() {
  local title="$1"
  local prompt="$2"
  local height="${3:-11}"
  local width="${4:-100}"

  whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" \
    --yesno "$prompt" "$height" "$width"
}

confirm_danger() {
  local title="$1"
  local prompt="$2"
  local height="${3:-15}"
  local width="${4:-100}"

  whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" \
    --defaultno --yesno "$prompt" "$height" "$width"
}

show_loading() {
  echo -e "${YW}Загрузка... сбор данных, это может занять несколько секунд (CTRL+C для отмены)${CL}" >&2
}

notice_box() {
  local title="$1"
  local text="$2"
  whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" \
    --msgbox "$text" 10 80 1>&2
}

# Интерактивный выбор одного контейнера
pick_container() {
  local title="$1"
  local -a rows=()
  local ctid status name label

  show_loading
  while IFS=$'\t' read -r ctid status name; do
    [[ -z "$ctid" ]] && continue
    label=$(printf '%-58s' "${name:-<без-имени>} [${status}]")
    rows+=("$ctid" "$label")
  done < <(pct list 2>/dev/null | awk 'NR>1 {print $1"\t"$2"\t"$NF}')

  if [[ ${#rows[@]} -eq 0 ]]; then
    notice_box "$title" "На этом хосте не найдено ни одного LXC-контейнера."
    return 1
  fi

  whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" \
    --menu "Выберите контейнер:" 24 80 16 "${rows[@]}" 3>&1 1>&2 2>&3
}

# Множественный выбор точек монтирования по всем контейнерам
pick_all_mountpoints_multi() {
  local title="$1"
  local -a rows=()
  local conf ctid name line key def label

  show_loading
  for conf in /etc/pve/lxc/*.conf; do
    [[ -e "$conf" ]] || continue
    ctid="$(basename "$conf" .conf)"
    name=$(awk '/^\[/{exit} $1=="hostname:"{print $2; exit}' "$conf")
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      key="${line%%:*}"
      def="${line#*: }"
      label=$(printf '%-86s' "CT ${ctid} ${name:-<без-имени>} | ${key}: ${def}")
      rows+=("${ctid}:${key}" "$label" "OFF")
    done < <(awk '/^\[/{exit} /^mp[0-9]+:/{print}' "$conf")
  done

  if [[ ${#rows[@]} -eq 0 ]]; then
    notice_box "$title" "Точек монтирования не найдено ни в одном контейнере."
    return 1
  fi

  whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" \
    --checklist "Выберите точку(и) монтирования для удаления (Пробел — выбор, Enter — подтвердить):" \
    24 112 16 "${rows[@]}" 3>&1 1>&2 2>&3
}

# Множественный выбор хранилищ Proxmox
pick_storages_multi() {
  local title="$1"
  local -a rows=()
  local stype sid label

  show_loading
  while read -r stype sid; do
    [[ -z "$sid" ]] && continue
    label=$(printf '%-58s' "[${stype}]")
    rows+=("$sid" "$label" "OFF")
  done < <(awk -F': ' '/^[a-z]+: /{print $1, $2}' /etc/pve/storage.cfg 2>/dev/null)

  if [[ ${#rows[@]} -eq 0 ]]; then
    notice_box "$title" "В /etc/pve/storage.cfg не найдено настроенных хранилищ."
    return 1
  fi

  whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" \
    --checklist "Выберите хранилище(а) для удаления (Пробел — выбор, Enter — подтвердить):" \
    24 80 16 "${rows[@]}" 3>&1 1>&2 2>&3
}

# Множественный выбор контейнеров
pick_containers_multi() {
  local title="$1"
  local -a rows=()
  local ctid status name label

  show_loading
  while IFS=$'\t' read -r ctid status name; do
    [[ -z "$ctid" ]] && continue
    label=$(printf '%-58s' "${name:-<без-имени>} [${status}]")
    rows+=("$ctid" "$label" "OFF")
  done < <(pct list 2>/dev/null | awk 'NR>1 {print $1"\t"$2"\t"$NF}')

  if [[ ${#rows[@]} -eq 0 ]]; then
    notice_box "$title" "На этом хосте не найдено ни одного LXC-контейнера."
    return 1
  fi

  whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" \
    --checklist "Выберите один или несколько контейнеров (Пробел — выбор, Enter — подтвердить):" \
    24 80 16 "${rows[@]}" 3>&1 1>&2 2>&3
}

# Тестирование подключения SMB/CIFS
manual_smb_test() {
  header_info
  local server share username password domain vers mount_dir mount_opts

  server=$(read_input "Тест SMB" "IP или имя SMB-сервера (например, 10.0.1.9)") || return
  share=$(read_input "Тест SMB" "Имя общего ресурса/шары (без ведущих //)" "Proxmox") || return
  username=$(read_input "Тест SMB" "Имя пользователя" "proxmox") || return
  password=$(read_password "Тест SMB" "Пароль для ${username}") || return
  domain=$(read_input "Тест SMB" "Домен/Рабочая группа (необязательно, оставьте пустым если не требуется)") || return
  vers=$(read_input "Тест SMB" "Версия протокола SMB (например, 3.0, 3.1.1)" "3.1.1") || return
  mount_dir="/mnt/test-smb"

  mkdir -p "$mount_dir"

  mount_opts="username=${username},password=${password},vers=${vers},sec=ntlmssp"
  if [[ -n "$domain" ]]; then
    mount_opts+=";domain=${domain}"
  fi

  msg_info "Тестирование монтирования SMB в ${mount_dir}..."
  if mount -t cifs "//${server}/${share}" "$mount_dir" -o "${mount_opts//;/,}" >/dev/null 2>&1; then
    touch "${mount_dir}/smb-test-$(date +%s)" >/dev/null 2>&1 || true
    umount "$mount_dir" >/dev/null 2>&1 || true
    msg_ok "Тест SMB успешно пройден"
  else
    msg_error "Ошибка теста SMB. Проверьте сеть, файрвол, логин/пароль и права доступа к ресурсу."
  fi

  pause
}

# Тестирование подключения NFS
manual_nfs_test() {
  header_info
  local server export_path mount_dir

  server=$(read_input "Тест NFS" "IP или имя NFS-сервера (например, 10.0.6.159)") || return
  export_path=$(read_input "Тест NFS" "Путь NFS-экспорта (например, /srv/proxmox-nfs)") || return
  mount_dir="/mnt/test-nfs"

  mkdir -p "$mount_dir"

  msg_info "Тестирование монтирования NFS в ${mount_dir}..."
  if mount -t nfs "${server}:${export_path}" "$mount_dir" >/dev/null 2>&1; then
    touch "${mount_dir}/nfs-test-$(date +%s)" >/dev/null 2>&1 || true
    umount "$mount_dir" >/dev/null 2>&1 || true
    msg_ok "Тест NFS успешно пройден"
  else
    msg_error "Ошибка теста NFS. Проверьте права экспорта, файрвол и сетевое соединение."
  fi

  pause
}

# Поиск iSCSI таргетов
manual_iscsi_discovery() {
  header_info
  local portal

  portal=$(read_input "Поиск iSCSI" "IP или FQDN iSCSI портала (например, 10.0.1.20)") || return
  msg_info "Запуск поиска iSCSI таргетов на ${portal}..."
  if iscsiadm -m discovery -t sendtargets -p "$portal"; then
    msg_ok "Поиск iSCSI таргетов успешно завершен"
  else
    msg_error "Ошибка при поиске iSCSI таргетов"
  fi

  pause
}

# Добавление SMB/CIFS хранилища в Proxmox VE
add_smb_storage() {
  header_info
  local storage_id server share username password content nodes options

  storage_id=$(read_input "Добавление SMB/CIFS хранилища" "ID хранилища (уникальный, например smb-media)") || return
  server=$(read_input "Добавление SMB/CIFS хранилища" "IP или имя SMB-сервера") || return
  share=$(read_input "Добавление SMB/CIFS хранилища" "Имя общего ресурса/шары (без //)") || return
  username=$(read_input "Добавление SMB/CIFS хранилища" "Имя пользователя") || return
  password=$(read_password "Добавление SMB/CIFS хранилища" "Пароль для ${username}") || return
  content=$(read_input "Добавление SMB/CIFS хранилища" "Типы контента (через запятую)" "backup,iso,vztmpl,snippets") || return
  nodes=$(read_input "Добавление SMB/CIFS хранилища" "Ноды (необязательно, через запятую)") || return
  options=$(read_input "Добавление SMB/CIFS хранилища" "Опции монтирования (необязательно, например vers=3.1.1,domain=WORKGROUP)") || return

  local cmd=(pvesm add cifs "$storage_id" --server "$server" --share "$share" --username "$username" --password "$password" --content "$content")
  [[ -n "$nodes" ]] && cmd+=(--nodes "$nodes")
  [[ -n "$options" ]] && cmd+=(--options "$options")

  if "${cmd[@]}" >/dev/null 2>&1; then
    msg_ok "SMB-хранилище '${storage_id}' успешно добавлено"
  else
    msg_error "Не удалось добавить SMB-хранилище '${storage_id}'"
  fi

  pause
}

# Добавление NFS хранилища в Proxmox VE
add_nfs_storage() {
  header_info
  local storage_id server export_path content nodes options

  storage_id=$(read_input "Добавление NFS хранилища" "ID хранилища (уникальный, например nfs-vmdata)") || return
  server=$(read_input "Добавление NFS хранилища" "IP или имя NFS-сервера") || return
  export_path=$(read_input "Добавление NFS хранилища" "Путь экспорта") || return
  content=$(read_input "Добавление NFS хранилища" "Типы контента (через запятую)" "images,rootdir") || return
  nodes=$(read_input "Добавление NFS хранилища" "Ноды (необязательно, через запятую)") || return
  options=$(read_input "Добавление NFS хранилища" "Опции монтирования (необязательно)") || return

  local cmd=(pvesm add nfs "$storage_id" --server "$server" --export "$export_path" --content "$content")
  [[ -n "$nodes" ]] && cmd+=(--nodes "$nodes")
  [[ -n "$options" ]] && cmd+=(--options "$options")

  if "${cmd[@]}" >/dev/null 2>&1; then
    msg_ok "NFS-хранилище '${storage_id}' успешно добавлено"
  else
    msg_error "Не удалось добавить NFS-хранилище '${storage_id}'"
  fi

  pause
}

# Добавление iSCSI хранилища в Proxmox VE
add_iscsi_storage() {
  header_info
  local storage_id portal target nodes

  storage_id=$(read_input "Добавление iSCSI хранилища" "ID хранилища (уникальный, например iscsi-synology)") || return
  portal=$(read_input "Добавление iSCSI хранилища" "IP или FQDN портала") || return
  target=$(read_input "Добавление iSCSI хранилища" "IQN таргета (например, iqn.2000-01.com.synology:...)") || return
  nodes=$(read_input "Добавление iSCSI хранилища" "Ноды (необязательно, через запятую)") || return

  local cmd=(pvesm add iscsi "$storage_id" --portal "$portal" --target "$target")
  [[ -n "$nodes" ]] && cmd+=(--nodes "$nodes")

  if "${cmd[@]}" >/dev/null 2>&1; then
    msg_ok "iSCSI-хранилище '${storage_id}' успешно добавлено"
  else
    msg_error "Не удалось добавить iSCSI-хранилище '${storage_id}'"
  fi

  pause
}

# Добавление LVM на базе iSCSI
add_lvm_on_base_storage() {
  header_info
  local storage_id base_storage vgname content shared

  storage_id=$(read_input "Добавление LVM хранилища" "ID LVM-хранилища (уникальный, например lvm-iscsi01)") || return
  base_storage=$(read_input "Добавление LVM хранилища" "ID базового хранилища (обычно ID iSCSI хранилища)") || return
  vgname=$(read_input "Добавление LVM хранилища" "Имя группы томов (Volume Group) на таргете") || return
  content=$(read_input "Добавление LVM хранилища" "Типы контента (через запятую)" "images,rootdir") || return
  shared=$(read_input "Добавление LVM хранилища" "Общий доступ между нодами? 1=да, 0=нет" "1") || return

  local cmd=(pvesm add lvm "$storage_id" --base "$base_storage" --vgname "$vgname" --content "$content" --shared "$shared")
  if "${cmd[@]}" >/dev/null 2>&1; then
    msg_ok "LVM-хранилище '${storage_id}' успешно добавлено"
  else
    msg_error "Не удалось добавить LVM-хранилище '${storage_id}'"
  fi

  pause
}

# Удаление описания хранилища из конфигурации Proxmox VE
remove_storage() {
  header_info
  local selection storage_id
  local -a results=()

  selection=$(pick_storages_multi "Удаление хранилища") || return
  if [[ -z "$selection" ]]; then
    msg_warn "Хранилище не выбрано."
    pause
    return
  fi

  for storage_id in $selection; do
    storage_id="${storage_id//\"/}"
    [[ -z "$storage_id" ]] && continue

    if confirm_danger "Удаление хранилища" \
      "Действительно удалить хранилище '${storage_id}' из конфигурации Proxmox?\n\nВнимание: удаляется только запись о хранилище в Proxmox.\nДанные на удаленном сервере или таргете НЕ удаляются."; then
      if pvesm remove "$storage_id" >/dev/null 2>&1; then
        results+=("Удалено : ${storage_id}")
      else
        results+=("ОШИБКА  : ${storage_id}")
      fi
    else
      results+=("Пропуск : ${storage_id}")
    fi
  done

  header_info
  echo -e "${BL}Результаты удаления хранилищ:${CL}\n"
  printf '  %s\n' "${results[@]}"
  echo
  pause
}

# Определение следующего свободного слота точки монтирования mpX
find_next_mp_slot() {
  local ctid="$1"
  local used

  used=$(pct config "$ctid" | awk -F: '/^mp[0-9]+:/ {gsub("mp", "", $1); print $1}')
  for i in $(seq 0 255); do
    if ! grep -qx "$i" <<<"$used"; then
      echo "$i"
      return
    fi
  done

  echo ""
}

# Добавление bind mount точки монтирования в LXC контейнер
add_lxc_mountpoint() {
  header_info
  local ctid host_path ct_path mp_slot

  ctid=$(pick_container "LXC: Добавить точку монтирования") || return
  host_path=$(read_input "Точка монтирования LXC" "Путь на хосте Proxmox (должен существовать, например /mnt/pve/smb-media)") || return
  ct_path=$(read_input "Точка монтирования LXC" "Путь внутри контейнера (например, /mnt/media)") || return

  if [[ ! -d "$host_path" ]]; then
    msg_error "Указанный путь на хосте не существует: ${host_path}"
    pause
    return
  fi

  mp_slot=$(find_next_mp_slot "$ctid")
  if [[ -z "$mp_slot" ]]; then
    msg_error "Нет свободных слотов mpX для контейнера ${ctid}"
    pause
    return
  fi

  confirm_yes_no "LXC: Добавить точку монтирования" \
    "Добавить точку монтирования mp${mp_slot} в контейнер CT ${ctid}?\n\n  ${host_path}  ->  ${ct_path}" 13 100 || return

  if pct set "$ctid" -mp"$mp_slot" "$host_path",mp="$ct_path" >/dev/null 2>&1; then
    msg_ok "Добавлена точка mp${mp_slot}: ${host_path} -> ${ct_path} для контейнера CT ${ctid}"
    msg_warn "Если контейнер непривилегированный (unprivileged), убедитесь в правильной настройке прав доступа и маппинга UID/GID."
  else
    msg_error "Не удалось добавить точку монтирования в контейнер CT ${ctid}"
  fi

  pause
}

# Удаление точки монтирования из LXC контейнера
remove_lxc_mountpoint() {
  header_info
  local selection entry ctid mp_key mp_def
  local -a results=()

  selection=$(pick_all_mountpoints_multi "LXC: Удалить точку монтирования") || return
  if [[ -z "$selection" ]]; then
    msg_warn "Точка монтирования не выбрана."
    pause
    return
  fi

  for entry in $selection; do
    entry="${entry//\"/}"
    [[ -z "$entry" ]] && continue
    ctid="${entry%%:*}"
    mp_key="${entry#*:}"
    mp_def=$(pct config "$ctid" | awk -F': ' -v k="$mp_key" '$1==k{print $2}')

    if confirm_danger "LXC: Удалить точку монтирования" \
      "Удалить ${mp_key} из контейнера CT ${ctid}?\n\n  ${mp_key}: ${mp_def}\n\nТочка монтирования будет отключена от контейнера.\nДанные на хосте НЕ удаляются."; then
      if pct set "$ctid" -delete "$mp_key" >/dev/null 2>&1; then
        results+=("Удалено : CT ${ctid}  ${mp_key}")
      else
        results+=("ОШИБКА  : CT ${ctid}  ${mp_key}")
      fi
    else
      results+=("Пропуск : CT ${ctid}  ${mp_key}")
    fi
  done

  header_info
  echo -e "${BL}Результаты удаления точек монтирования:${CL}\n"
  printf '  %s\n' "${results[@]}"
  echo
  pause
}

# Просмотр точек монтирования LXC контейнеров
list_lxc_mountpoints() {
  header_info
  local selection ctid mps

  selection=$(pick_containers_multi "LXC: Список точек монтирования") || return
  if [[ -z "$selection" ]]; then
    msg_warn "Контейнер не выбран."
    pause
    return
  fi

  for ctid in $selection; do
    ctid="${ctid//\"/}"
    [[ -z "$ctid" ]] && continue
    echo -e "${BL}Точки монтирования для контейнера CT ${ctid}:${CL}"
    mps=$(pct config "$ctid" | awk '/^mp[0-9]+:/{print}')
    if [[ -n "$mps" ]]; then
      echo "$mps"
    else
      echo "  (точки монтирования не настроены)"
    fi
    echo
  done

  pause
}

# Создание общей папки Samba непосредственно на хосте
host_create_samba_share() {
  header_info
  local share_name share_path user_name user_pass

  share_name=$(read_input "Samba на хосте" "Имя общего ресурса (например, data)") || return
  share_path=$(read_input "Samba на хосте" "Путь к папке на хосте (например, /srv/samba/data)" "/srv/samba/${share_name}") || return
  user_name=$(read_input "Samba на хосте" "Имя пользователя Linux/Samba") || return
  user_pass=$(read_password "Samba на хосте" "Пароль для пользователя ${user_name}") || return

  msg_info "Установка Samba на хост (при необходимости)..."
  apt update >/dev/null 2>&1
  apt install -y samba >/dev/null 2>&1

  mkdir -p "$share_path"
  getent group sambashare >/dev/null 2>&1 || groupadd sambashare
  id "$user_name" >/dev/null 2>&1 || useradd -M -s /usr/sbin/nologin -G sambashare "$user_name"
  usermod -aG sambashare "$user_name"
  chown -R root:sambashare "$share_path"
  chmod 2775 "$share_path"

  if ! (
    echo "$user_pass"
    echo "$user_pass"
  ) | smbpasswd -s -a "$user_name" >/dev/null 2>&1; then
    msg_error "Не удалось установить пароль Samba для ${user_name}"
    pause
    return
  fi

  if ! grep -q "^\[${share_name}\]" /etc/samba/smb.conf; then
    cat <<EOF >>/etc/samba/smb.conf

[${share_name}]
   comment = Proxmox Host Share (${share_name})
   path = ${share_path}
   browseable = yes
   read only = no
   guest ok = no
   create mask = 0664
   directory mask = 2775
   valid users = @sambashare
EOF
  fi

  testparm -s >/dev/null 2>&1 || {
    msg_error "Ошибка проверки конфигурации Samba (testparm). Проверьте файл /etc/samba/smb.conf"
    pause
    return
  }

  systemctl enable --now smbd nmbd >/dev/null 2>&1
  systemctl restart smbd nmbd >/dev/null 2>&1

  msg_ok "Общий ресурс SMB на хосте создан: //$(hostname -I | awk '{print $1}')/${share_name}"
  msg_warn "Рекомендация: для лучшей изоляции хоста рекомендуется запускать Samba в отдельном LXC-контейнере или ВМ."

  pause
}

# Создание NFS экспорта непосредственно на хосте
host_create_nfs_export() {
  header_info
  local export_path subnet options

  export_path=$(read_input "NFS на хосте" "Путь экспорта на хосте (например, /srv/proxmox-nfs)" "/srv/proxmox-nfs") || return
  subnet=$(read_input "NFS на хосте" "Разрешенная подсеть/CIDR (например, 10.0.0.0/16)") || return
  options=$(read_input "NFS на хосте" "Опции экспорта" "rw,sync,no_subtree_check,no_root_squash") || return

  msg_info "Установка NFS-сервера на хост (при необходимости)..."
  apt update >/dev/null 2>&1
  apt install -y nfs-kernel-server >/dev/null 2>&1

  mkdir -p "$export_path"
  chmod 0770 "$export_path"

  if ! grep -qE "^${export_path//\//\/}[[:space:]]+${subnet//\//\/}\(" /etc/exports; then
    echo "${export_path} ${subnet}(${options})" >>/etc/exports
  fi

  exportfs -ra >/dev/null 2>&1
  systemctl enable --now nfs-kernel-server >/dev/null 2>&1

  msg_ok "Экспорт NFS на хосте создан: ${export_path} ${subnet}(${options})"
  msg_warn "Рекомендация: используйте экспорт с хоста осмотрительно; выделенный LXC/ВМ для сетевого хранилища безопаснее."
  pause
}

# Отображение сводного статуса хранилищ и подключений
show_status() {
  header_info
  echo -e "${BL}Статус хранилищ (pvesm status):${CL}"
  pvesm status || true
  echo
  echo -e "${BL}Смонтированные пути в /mnt/pve:${CL}"
  mount | grep /mnt/pve || true
  echo
  echo -e "${BL}Смонтированные пути CIFS/NFS:${CL}"
  mount | grep -E ' type (cifs|nfs|nfs4)' || true
  echo
  echo -e "${BL}Активные сессии iSCSI:${CL}"
  iscsiadm -m session 2>/dev/null || true
  echo
  pause
}

# Главное интерактивное меню утилиты
main_menu() {
  while true; do
    local choice
    choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Мастер хранилищ и общих ресурсов" \
      --menu "Выберите действие (чтение и тесты безопасны; изменение и удаление запрашивают подтверждение):" 30 116 22 \
      " " "──────────  ДИАГНОСТИКА И ЧТЕНИЕ (безопасно)  ──────────" \
      "1" "Тест    | SMB: ручной тест монтирования" \
      "2" "Тест    | NFS: ручной тест монтирования" \
      "3" "Тест    | iSCSI: поиск таргетов (discovery)" \
      "4" "Чтение  | LXC: список точек монтирования" \
      "5" "Чтение  | Показать статус хранилищ / монтирований / iSCSI" \
      "  " "──────────  НАСТРОЙКА И ЗАПИСЬ (изменение конфигурации)  ──────────" \
      "6" "Запись  | Proxmox: добавить SMB/CIFS хранилище" \
      "7" "Запись  | Proxmox: добавить NFS хранилище" \
      "8" "Запись  | Proxmox: добавить iSCSI хранилище" \
      "9" "Запись  | Proxmox: добавить LVM поверх базового хранилища (iSCSI)" \
      "10" "Запись  | LXC: добавить bind точку монтирования (pct set -mpX)" \
      "11" "Запись  | Хост: установить Samba и создать SMB-шару" \
      "12" "Запись  | Хост: установить NFS-сервер и создать экспорт" \
      "   " "──────────  УДАЛЕНИЕ (деструктивно, по умолчанию 'Нет')  ──────────" \
      "13" "Удалить | Proxmox: удалить конфигурацию хранилища" \
      "14" "Удалить | LXC: удалить точку монтирования (pct set -delete mpX)" \
      "0" "Выход" 3>&1 1>&2 2>&3) || break

    case "$choice" in
    1) manual_smb_test || true ;;
    2) manual_nfs_test || true ;;
    3) manual_iscsi_discovery || true ;;
    4) list_lxc_mountpoints || true ;;
    5) show_status || true ;;
    6) add_smb_storage || true ;;
    7) add_nfs_storage || true ;;
    8) add_iscsi_storage || true ;;
    9) add_lvm_on_base_storage || true ;;
    10) add_lxc_mountpoint || true ;;
    11) host_create_samba_share || true ;;
    12) host_create_nfs_export || true ;;
    13) remove_storage || true ;;
    14) remove_lxc_mountpoint || true ;;
    0) break ;;
    *) ;;
    esac
  done
}

header_info
root_check
pve_check
require_pve
ensure_packages
confirm_start || exit 0
main_menu

header_info
msg_ok "Работа мастера успешно завершена."
