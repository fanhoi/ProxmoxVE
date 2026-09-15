<!-- Главный README каталог скриптов Proxmox VE с бейджами shieldcn -->
# 🧰 Proxmox VE — Скрипты и системные утилиты

<p align="left">
  <a href="https://proxmox.com"><img src="https://shieldcn.dev/badge/Proxmox_VE-v7%20%7C%20v8-E57000.svg?logo=proxmox&logoColor=white" alt="Proxmox VE" /></a>
  <a href="https://www.gnu.org/software/bash/"><img src="https://shieldcn.dev/badge/Language-Bash-4EAA25.svg?logo=gnubash&logoColor=white" alt="Bash" /></a>
  <a href="LICENSE"><img src="https://shieldcn.dev/badge/License-MIT-059669.svg" alt="License MIT" /></a>
  <a href="https://github.com/fanhoi/ProxmoxVE"><img src="https://shieldcn.dev/badge/Status-Maintained-2563EB.svg?logo=lu:ShieldCheck&logoColor=white" alt="Status" /></a>
</p>

Коллекция полезных, безопасных и русифицированных bash-скриптов для управления, диагностики и оптимизации серверов **Proxmox Virtual Environment (PVE)**.

---

## 📑 Каталог доступных скриптов

| Категория | Скрипт | Описание | Запуск в 1 клик через консоль Proxmox VE |
| :--- | :--- | :--- | :--- |
| 💽 **Хранилище** | [`tools/disk-health.sh`](tools/disk-health.sh) | Диагностика состояния здоровья накопителей (NVMe, SSD, HDD), SMART-отчёт, температура, износ и запуск теста самодиагностики | `bash -c "$(curl -fsSL https://raw.githubusercontent.com/fanhoi/ProxmoxVE/main/tools/disk-health.sh)"` |

---

## 🛠️ Описание инструментов

### 💽 1. Проверка состояния дисков и SMART-диагностика (`disk-health.sh`)

Скрипт для быстрой оценки состояния, износа, температуры и SMART-метрик всех физических дисков хоста Proxmox VE.

#### 🚀 Быстрый запуск:
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/fanhoi/ProxmoxVE/main/tools/disk-health.sh)"
```

#### ✨ Ключевые возможности:
- **Автопоиск накопителей**: находит физические диски, исключая loop, zram и виртуальные device-mapper разделы.
- **Поддержка NVMe**: температура, доступный резерв, процент использованного ресурса, объем записанных данных, небезопасные отключения, ошибки целостности данных.
- **Поддержка SATA SSD / HDD**: температура, время наработки (Power On Hours), индикатор износа (Wear Leveling / Wearout), переназначенные и нестабильные секторы (Reallocated/Pending Sectors), ошибки UDMA CRC.
- **Интерактивный тест самодиагностики**: через псевдографическое меню `whiptail` можно в один клик запустить безопасный фоновый короткий тест (**SHORT SMART Self-Test**) на выбранном накопителе.
- **Автоустановка утилит**: при необходимости сам установит `smartmontools` и `nvme-cli`.

<details>
<summary><b>📊 Пример вывода disk-health.sh</b></summary>

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

</details>

## 📄 Лицензия

Проект распространяется под лицензией [MIT](LICENSE).
Бейджи оформления созданы с помощью [shieldcn](https://shieldcn.dev).
