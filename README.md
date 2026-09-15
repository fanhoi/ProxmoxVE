<div align="center">

# 🧰 Proxmox VE Helper Scripts & Tools

<p>
  <strong>Набор удобных, безопасных и русифицированных утилит для серверов Proxmox VE</strong>
</p>

<p align="center">
  <a href="https://proxmox.com"><img src="https://shieldcn.dev/badge/Proxmox_VE-v7_%7C_v8-E57000.svg?logo=proxmox&logoColor=white" alt="Proxmox VE" /></a>
  <a href="https://www.gnu.org/software/bash/"><img src="https://shieldcn.dev/badge/Language-Bash-4EAA25.svg?logo=gnubash&logoColor=white" alt="Bash" /></a>
  <a href="LICENSE"><img src="https://shieldcn.dev/badge/License-MIT-059669.svg" alt="License MIT" /></a>
  <a href="https://github.com/fanhoi/ProxmoxVE"><img src="https://shieldcn.dev/badge/Status-Active-2563EB.svg?logo=lu:Activity&logoColor=white" alt="Status" /></a>
</p>

</div>

---

## 🧭 Навигация по категориям

- 💽 [**Хранилище и диски**](#-хранилище-и-диски)
  - [Диагностика состояния накопителей (disk-health.sh)](#-проверка-состояния-накопителей-и-smart-disk-healthsh)

---

## 💽 Хранилище и диски

### 🔍 Проверка состояния накопителей и SMART (`disk-health.sh`)

Скрипт для экспресс-диагностики физических накопителей (NVMe, SATA SSD, HDD). Формирует понятный русскоязычный отчёт по температуре, износу, ресурсу и критическим SMART-атрибутам, а также позволяет запустить безопасный фоновый тест самодиагностики.

#### ⚡ Команда для запуска (вставьте в консоль Proxmox VE):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/fanhoi/ProxmoxVE/main/tools/disk-health.sh)"
```

#### ✨ Что проверяет скрипт:
- **NVMe накопители**: температура, доступный резерв (Available Spare), процент износа (Percentage Used), объём записанных данных, время наработки, небезопасные отключения, ошибки целостности данных.
- **SATA/SAS SSD и HDD**: температура, часы наработки, индикатор износа (Wear Leveling/Wearout), переназначенные секторы (Reallocated), нестабильные секторы (Pending), неисправимые ошибки (Offline Uncorrectable), ошибки передачи (UDMA CRC).
- **Самодиагностика**: запуск короткого фонового теста (**SHORT SMART Self-Test**) через удобное интерактивное меню.
- **Автоматика**: при отсутствии `smartmontools` или `nvme-cli` скрипт сам аккуратно установит недостающие пакеты.

<details>
<summary><b>📋 Пример отчёта в терминале</b></summary>

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

---

## 📜 Лицензия

Проект распространяется под лицензией [MIT](LICENSE).
Стилизованные бейджи сгенерированы сервисом [shieldcn](https://shieldcn.dev).
