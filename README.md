<!-- README файл для Proxmox VE Disk Health Script с бейджами shieldcn -->
# 💽 Proxmox VE — Disk Health Check & SMART Diagnostics

<p align="left">
  <a href="https://proxmox.com"><img src="https://shieldcn.dev/badge/Proxmox_VE-v7%20%7C%20v8-E57000.svg?logo=proxmox&logoColor=white" alt="Proxmox VE" /></a>
  <a href="https://www.gnu.org/software/bash/"><img src="https://shieldcn.dev/badge/Language-Bash-4EAA25.svg?logo=gnubash&logoColor=white" alt="Bash" /></a>
  <a href="https://www.smartmontools.org/"><img src="https://shieldcn.dev/badge/Tool-smartmontools-2563EB.svg?logo=linux&logoColor=white" alt="smartmontools" /></a>
  <a href="https://nvmexpress.org/"><img src="https://shieldcn.dev/badge/Storage-NVMe_%26_SATA%2FSSD-7C3AED.svg" alt="NVMe and SATA" /></a>
  <a href="LICENSE"><img src="https://shieldcn.dev/badge/License-MIT-059669.svg" alt="License MIT" /></a>
</p>

Удобный интерактивный bash-скрипт для быстрой оценки состояния здоровья, температуры, износа и ключевых SMART-параметров физических накопителей (NVMe, SATA SSD, HDD) на серверах **Proxmox VE**.

---

## 🚀 Возможности

- 🔍 **Автоматическое сканирование**: находит все физические накопители в системе (исключая loop, zram и виртуальные device-mapper разделы).
- ⚡ **Поддержка NVMe и SATA/SAS**:
  - **NVMe**: температура, доступный резерв, процент использованного ресурса, объём записанных данных, время наработки, небезопасные отключения, ошибки целостности данных.
  - **SATA/SAS SSD и HDD**: температура, время наработки (Power On Hours), индикатор износа (Wear Leveling / Wearout Indicator), переназначенные и нестабильные секторы (Reallocated / Pending Sectors), неисправимые ошибки и ошибки UDMA CRC.
- 📦 **Автоматическая установка зависимостей**: при отсутствии утилит `smartmontools` или `nvme-cli`, скрипт аккуратно установит их автоматически.
- 🩺 **Запуск самодиагностики**: интерактивное меню (whiptail) для запуска короткого фонового теста самодиагностики (**SHORT SMART Self-Test**) на выбранном диске.
- 🇷🇺 **Полностью на русском языке**: все системные сообщения, таблицы и диалоговые окна переведены на русский язык с удобной цветовой индикацией.

---

## 📋 Требования

- **ОС**: Proxmox VE 7.x / 8.x (Debian-based)
- **Права**: `root` (необходимы для прямого доступа к SMART-командам накопителей)
- **Доступ в интернет**: для первоначальной загрузки зависимостей

---

## 🛠️ Как пользоваться скриптом

### Вариант 1. Запуск из терминала в один клик (без скачивания)

Подключитесь к консоли хоста Proxmox VE (через SSH или Web Shell) и выполните команду:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/disk-health.sh)"
```

---

### Вариант 2. Запуск локального скрипта

1. Склонируйте репозиторий или скачайте файл скрипта:
   ```bash
   git clone https://github.com/fanhoi/ProxmoxVE.git
   cd ProxmoxVE
   ```

2. Сделайте скрипт исполняемым:
   ```bash
   chmod +x disk-health.sh
   ```

3. Запустите скрипт от имени `root`:
   ```bash
   ./disk-health.sh
   ```

---

## 📊 Пример вывода

```text
======================================================
/dev/nvme0n1  1.8T  Samsung SSD 980 PRO 2TB
======================================================
  Состояние:                   Исправен (PASSED)
  Температура:                 41 C
  Доступный резерв:            100%
  Использованный ресурс:       4%
  Записано данных:             28,451,120 [14.5 TB]
  Время работы (часы):         4,210
  Небезопасных отключений:     12
  Ошибки целостности данных:   0

======================================================
/dev/sda  3.6T  WDC WD40EFRX-68N32N0
======================================================
  Состояние:                   Исправен (PASSED)
  Температура:                 34 °C
  Время работы (часы):         18420
  Переназначенные секторы:     0
  Нестабильные секторы:        0
  Неисправимые ошибки:         0
  Ошибки UDMA CRC:             0
```

---

## 🧪 Интерактивный тест самодиагностики (SMART Self-Test)

После вывода сводного отчёта скрипт предложит запустить короткий тест самодиагностики:

1. Выберите **«Да»** в появившемся диалоге.
2. В списке дисков выберите накопитель для проверки.
3. Тест запустится в фоновом режиме, не прерывая работу виртуальных машин и контейнеров.
4. Проверить результат выполнения теста можно командой:
   ```bash
   smartctl -a /dev/sdX
   # или для NVMe
   smartctl -a /dev/nvmeXn1
   ```

---

## 📄 Лицензия

Распространяется под лицензией [MIT](LICENSE).
Основано на скриптах сообщества [Proxmox VE Helper-Scripts](https://github.com/community-scripts/ProxmoxVE).
Бейджи оформлены с помощью сервиса [shieldcn](https://shieldcn.dev).
