# Спека: однокнопочная установка Debian 12 на голое железо (8 проблем + смежные баги)

Дата: 2026-07-23. Автор анализа: Claude (сессия с teleportboy), исходные проблемы — teleportboy («ставил кусками, из `Linux/` почему-то ломается, вечером накатываю на железо»).

**Статус (2026-07-23): реализовано, ревью пройдено, ждёт живого прогона.** `install.sh` переписан начисто, конфиги перенесены в репо готовыми файлами, раскладка переведена на Win+Space (решение 2026-07-23). Адверсариальное ревью: 25 находок, все закрыты/сняты — таблица R1–R12 внизу. Осталось: прогон на голом железе вечером. Инструкция — `docs/install_usage.md`, чеклист — `plan_linux.md`.

## Как проверялось

- **Живая система**: хост `rearm`, Debian 12.14 (bookworm), VMware, ядро 6.1.0-25-amd64. Аудит 2026-07-23 четырьмя параллельными аудиторами: пакеты (`apt-mark showmanual` — 329 шт. + история `/var/log/apt/history.log*` — 44 команды), дотфайлы (полный diff репо ↔ живые), системный уровень (`/etc`, службы, udev, alternatives), стиль доков (magican2).
- **Код**: `Debian/install.sh` @ HEAD `32ee815`.
- **Дефолты Debian 12 netinstall**: включены только `main non-free-firmware`; **contrib ВЫКЛЮЧЕН** — критично для P2.

## Сводка вердиктов

| # | Проблема | Вердикт |
|---|----------|---------|
| P1 | Ubuntu PPA `linuxuprising/apps` на Debian | **Подтверждена** (install.sh:45; на Launchpad нет dist `bookworm` → `apt update` вернёт код 100 → `errexit` убивает скрипт, причём именно в ветке голого железа). Фикс: ветка выброшена, `tlp` из bookworm |
| P2 | `ttf-mscorefonts-installer` не ставится на свежем netinstall | **Подтверждена** (пакет живёт в contrib, netinstall contrib не включает; плюс интерактивная EULA). Фикс: `sources.list` готовым файлом + debconf preseed EULA |
| P3 | `startx` в середине скрипта | **Подтверждена** (install.sh:85; всё после выполняется только по выходу из X; `~/.config/i3/config` не существует до прохождения мастера i3 → `sed` на строке 106 падает на отсутствующем файле → errexit). Фикс: startx убран вообще, конфиги кладутся файлами |
| P4 | oh-my-zsh вешает прогон | **Подтверждена** (инсталлер в конце делает `exec zsh` и интерактивно спрашивает про chsh — скрипт стоит, пока юзер не наберёт `exit`). Фикс: `RUNZSH=no CHSH=no ... --unattended`, наш `.zshrc` кладётся поверх |
| P5 | Запуск зависит от cwd и шелла («из `Linux/` ломается») | **Подтверждена живьём** (память юзера + разбор: `sh install.sh` → dash → `Bad substitution` на `${BASH_SOURCE[0]}`; `curl \| bash` → `SCRIPT_PATH="."` → `cp` полибара падает не из папки `Debian/`). Фикс: абсолютный `SCRIPT_PATH` через `cd && pwd` + POSIX-guard на bash первой строкой |
| P6 | Скрипт не воспроизводит живую машину (дрифт) | **Подтверждена** (diff: `.Xresources` size=10≠13, нет `termName`; раскладки `us,ru` в скрипте нет вообще; `.zprofile` живой содержит 4 дубля `PATH=$PATH:/usr/sbin` — прямое доказательство неидемпотентности `>>`). Фикс: живые конфиги в репо готовыми файлами, `cp` вместо `echo/sed` |
| P7 | На голом железе нет сети/firmware/microcode/питания | **Подтверждена** (NetworkManager отсутствует даже в VM — i3-конфиг зовёт `nm-applet`, которого нет; firmware-пакетов и `tlp` нет). Фикс: ветка bare-metal — NM+nm-applet, firmware по чипам, microcode по вендору CPU, tlp при наличии батареи |
| P8 | Скрипт не знает ~60 пакетов и весь ручной софт | **Подтверждена** (аудит: embedded-тулчейн ARM/J-Link/NXP, Yocto host-deps, Qt dev, postgresql, NFS-сервер, 7 сторонних реп, rustup/nvm/claude/lazygit/nvim, snap/flatpak). Фикс: модульные секции с флагами в шапке скрипта |

---

## P1. Ubuntu PPA убивает скрипт именно на железе

### Факты (верифицировано)

- install.sh:45 `sudo add-apt-repository -y ppa:linuxuprising/apps` — Launchpad собирает только под Ubuntu; для Debian запись получает dist `bookworm`, которого в PPA нет → 404 на Release-файле → `apt update` (строка 46) выходит с кодом 100 → `set -o errexit` валит весь скрипт.
- Ветка `*)` в `case $(systemd-detect-virt)` — это ветка **голого железа**. То есть скрипт гарантированно не доезжал до zsh/i3/polybar именно там, где его вечером запускать.
- Бонусом в той же ветке: `apt install tlpui` без `-y` (интерактив) и `sudo tlpui` — запуск GUI, когда X ещё не существует (startx только на строке 85).

### Фикс (install.sh v2)

1. PPA/tlpui выброшены. `tlp tlp-rdw` из bookworm, ставятся только при наличии батареи (`/sys/class/power_supply/BAT*`).
2. TLP настраивается конфигом `/etc/tlp.conf` — дефолт достаточен, GUI не нужен.

### Тесты P1

- TC-P1.1: `grep -c add-apt-repository install.sh` → 0.

---

## P2. mscorefonts: contrib + EULA

### Факты (верифицировано)

- `ttf-mscorefonts-installer` — секция **contrib**; на текущей машине contrib включён руками (sources.list правился), на свежем netinstall его нет → `apt install` умирает ещё на строке 11 старого скрипта.
- Пакет задаёт интерактивный debconf-вопрос (EULA) — вешает «однокнопочный» прогон.

### Фикс (install.sh v2 + etc/apt/sources.list)

1. `etc/apt/sources.list` — готовый файл: bookworm / -security / -updates с `main contrib non-free non-free-firmware` (копия рабочего). Ставится до первого `apt install`, старый уходит в `.bak`.
2. ~~debconf-preseed EULA~~ — **СНЯТ** (ревью 2026-07-23): шаблон `msttcorefonts/accepted-mscorefonts-eula` существует только в Ubuntu, в Debian-пакете его нет — преседить нечего; хватает `DEBIAN_FRONTEND=noninteractive` во всех apt-вызовах.
3. **ВАЖНО (урок ревью 2026-07-23)**: postinst пакета качает 11 .exe с зеркал SourceForge и при их недоступности валит всю apt-транзакцию — mscorefonts вынесен из общей транзакции в отдельный `try apt_install` (падение стоит только шрифтов, попадает в SKIPPED).

### Тесты P2

- TC-P2.1: свежий netinstall → секция fonts проходит без единого вопроса.

---

## P3–P6. Конфиги файлами вместо генерации, независимость от cwd

### Факты (верифицировано)

- Полный список дрифта живой машины против скрипта — см. Сводку. Ключевое: раскладка us,ru существовала только в живом `~/.xinitrc`, скрипт её не знал — на свежей машине юзер остался бы без русского.
- `~/.zprofile` живой: `PATH=$PATH:/usr/sbin` ×4 — скрипт запускался 4 раза, каждый раз дописывал.
- Мёртвый код в живом `~/.xinitrc`: два `exec xset ...` ПОСЛЕ `exec i3` — не выполняются никогда (dpms и так задан в i3 config:32-33).

### Дизайн

Репо = источник истины. Структура:

```
Debian/
  install.sh            — оркестратор, модульные секции с флагами
  home/                 — дотфайлы, копируются в $HOME как есть
    .zshrc .zprofile .zshenv .Xresources .xinitrc
    .config/{i3,polybar,git,htop,doublecmd}/... .config/mimeapps.list
    bin/telega.sh
  etc/                  — системные файлы, копируются с sudo
    apt/sources.list, apt/sources.list.d/*, apt/keyrings/*, apt/trusted.gpg.d/*
    default/keyboard
    udev/rules.d/99-usb-serial.rules
docs/  spec_install.md, install_usage.md
plan_linux.md
```

Отклонённые альтернативы: stow/chezmoi — отклонены по цене входа (лишняя зависимость и симлинк-магия ради 15 файлов; `cp` достаточно, идемпотентен по построению); Ansible — отклонён (один хост, один прогон в год).

### Фикс (install.sh v2)

1. `SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"` — абсолютный; первой строкой POSIX-guard: запуск не-bash'ем → внятная ошибка, а не Bad substitution.
2. Все дотфайлы: `cp -a "$SCRIPT_PATH/home/." "$HOME/"` ПОСЛЕ установки oh-my-zsh (наш `.zshrc` побеждает сгенерённый).
3. Никаких `>>` и `sed` по конфигам. Повторный запуск скрипта = тот же результат.
4. В репо-версиях вычищено: `.zprofile` — 1 строка вместо 4; `.xinitrc` — без мёртвых строк; `.zshenv` — cargo под guard `[ -f ]` (иначе первый логин до установки rustup сыпал бы ошибкой).

### Решение юзера 2026-07-23: раскладка

Правый Ctrl (`grp:rctrl_toggle`) — **СНЯТ** («хуйня, буду отказываться»). Выбран **Win+Space** (`grp:win_space_toggle`): `etc/default/keyboard` (консоль+X) и `setxkbmap` в `.xinitrc`. Конфликт: дефолтный i3-бинд `$mod+space focus mode_toggle` стрелял бы вместе с переключалкой — **закомментирован** в `home/.config/i3/config` (floating toggle на `$mod+Shift+space` остаётся).

### Тесты P3–P6

- TC-P5.1: `bash Debian/install.sh` из `/`, из `$HOME`, из `Debian/` → `SCRIPT_PATH` один и тот же (абсолютный).
- TC-P5.2: `sh Debian/install.sh` → «Run it with bash», код 1, ни одна команда не выполнена.
- TC-P6.1: после прогона `diff -r Debian/home/ $HOME/` по списку файлов → пусто.
- TC-P3.1: второй прогон подряд → `grep -c '/usr/sbin' ~/.zprofile` = 1.

---

## P7. Голое железо: сеть, firmware, питание

### Факты (верифицировано)

- NetworkManager не установлен вообще (сеть в VM — ifupdown+DHCP на `ens33`); `nm-applet` из i3 config:37 молча не запускается.
- Из firmware стоят только `firmware-linux-free` + `intel-microcode` (CPU хоста — i5-12400, проброшен в VM). Wi-Fi/BT-firmware, tlp, brightnessctl, bluez — нет ничего.

### Фикс (install.sh v2, ветка по `systemd-detect-virt`)

1. `vmware` → `open-vm-tools open-vm-tools-desktop` (как раньше).
2. `none` (железо) → `network-manager network-manager-gnome` (nm-applet для i3), `/etc/network/interfaces` переписывается на lo-only (бэкап), чтобы NM забрал интерфейсы; `firmware-linux firmware-misc-nonfree firmware-iwlwifi firmware-realtek firmware-atheros` (все три wifi-семейства — дешевле поставить лишнее, чем остаться без сети); microcode по `vendor_id` из `/proc/cpuinfo` (intel-microcode / amd64-microcode); `bluez blueman`; при наличии `BAT*` — `tlp tlp-rdw acpid brightnessctl`.
3. `xserver-xorg` ставится явно (не через Recommends xinit) — драйвер modesetting подхватит железо сам, xorg.conf не нужен (проверено: и в VM он пуст).

### Тесты P7

- TC-P7.1 (жив., вечером): после reboot `nmtui` видит Wi-Fi сети; `ip link` показывает wlp*.

---

## P8. Полный перенос среды: модульные секции

### Факты (верифицировано)

Сверх старого скрипта на машине живёт (полный аудит в отчётах, здесь — итог):

- **embedded**: `gcc-arm-none-eabi libnewlib-arm-none-eabi binutils-arm-none-eabi gdb-multiarch device-tree-compiler can-utils binwalk evtest minicom picocom cutecom gtkterm putty libqt5serialbus5{,-dev} dfu-util` + J-Link 8.10 (.deb с segger.com) + NXP LinkServer/MCU-Link/lpcscrypt/pemicro (через MCUXpressoInstaller, требует аккаунт NXP — **автоматизации не подлежит**) + udev-правила `99-usb-serial.rules` (ttyUSB* 0666), `99-jlink.rules` (ставит сам J-Link)
- **Yocto host-deps**: канонический список bookworm + `libgmp-dev libmpfr-dev libmpc-dev cmake ninja-build bc flex bison xvfb liblz4-tool`
- **Qt dev**: `qtcreator qtbase5-dev qt5-qmake libgl1-mesa-dev mesa-common-dev`
- **server**: `openssh-server postgresql postgresql-contrib libpq-dev postgresql-server-dev-all nfs-kernel-server nfs-common` (+exports `/nfs/nfs_debix*`)
- **сторонние репы** (ключи сохранены в репо — от сайтов вечером не зависим): VS Code, Opera, Beyond Compare 5, Antigravity, cucumber-space (yandex-music). Chrome — через .deb (сам прописывает репу)
- **вне apt**: rustup(+rustlings), nvm 0.40.3+node 22, claude code, lazygit, neovim AppImage `/opt/nvim/nvim`+LazyVim starter, flatpak (Flameshot, Telegram), snap (android-studio --classic, postman), repo → `~/bin`, GitExtensions (mono) — перенос руками
- **прочее**: `ripgrep nnn p7zip-full vim meld kdiff3 gitg colordiff diffstat zenity xautolock xclip usbutils lsof socat netcat-traditional inetutils-telnet python3-venv python-is-python3 fonts-noto-cjk fonts-open-sans qbittorrent filezilla okular zathura zathura-pdf-poppler libfuse2` (libfuse2 — без него AppImage nvim не стартует)
- **система**: локали en_US+ru_RU, таймзона Asia/Bishkek, группы `dialout plugdev netdev audio video`, sudo NOPASSWD (сейчас — ручные строки в `/etc/sudoers`; воспроизводим чисто — файлом в `/etc/sudoers.d/` с проверкой `visudo -cf`), курсор Breeze_Snow через update-alternatives, PulseAudio (НЕ pipewire), git config user.name/email (email уже светится в публичных коммитах репо — не новая утечка)

### Дизайн

Флаги-секции в шапке скрипта (`INSTALL_DESKTOP=1`, `INSTALL_DEV_EMBEDDED=1`, `INSTALL_YOCTO_DEPS=1`, `INSTALL_DEV_QT=1`, `INSTALL_RUST=1`, `INSTALL_NODE=1`, `INSTALL_SERVER=1`, `INSTALL_NFS_SERVER=0`, `INSTALL_FLATPAK_SNAP=1`, `INSTALL_EXTRA_APPS=1`). Не нужна секция — 0 в шапке, остальное не задевается.

Сетевые/сторонние шаги (discord, gitkraken, jlink, bcompare, snap, flatpak, claude, lazygit) — через `try()`: упавший URL пишет WARN и НЕ валит прогон; итоговый список пропусков печатается в конце. Ядро системы (apt base, дотфайлы, sources) — жёсткий fail.

### Тесты P8

- TC-P8.1: каждое имя apt-пакета из скрипта проверено `apt-cache policy` на живой машине (все репы включены) → candidate существует.
- TC-P8.2: `bash -n` + shellcheck → 0 ошибок.
- TC-P8.3: адверсариальное ревью «walkthrough свежего netinstall» (отдельные агенты) → все находки закрыты или сняты с причиной.

---

## Смежные баги (найдены по пути, закрыты в том же коммите)

| # | Что | Где | Фикс |
|---|-----|-----|------|
| A1 | Дубль `apt install rxvt-unicode` | install.sh:7,54 | закрыт P8 (единые списки) |
| A2 | `cp -r` powerline-конфигов: копия идентична системной (diff пуст), только маскирует обновления пакета | install.sh:117 | шаг удалён, powerline.zsh сорсится из `.zshrc` |
| A3 | `export TERM=rxvt-unicode-color256` — битое имя terminfo (правильно `rxvt-unicode-256color`), конфликтует с `URxvt.termName: xterm-256color` | ~/.bashrc | `.bashrc` в репо НЕ переносим (шелл — zsh); живую машину не трогаем |
| A4 | Мёртвые `exec xset` после `exec i3` | ~/.xinitrc | вычищено в репо-версии (dpms живёт в i3 config:32-33) |
| A5 | Репо лежит внутри `~/.ssh` рядом с приватными ключами — одна ошибка `git add` уровнем выше, и ключи в remote; `git clone` в `~/.ssh/...` на свежей машине падает (git не создаёт родителей) | репо | инструкция клонирует в `~/Linux`; рекомендация — переехать насовсем; на новой машине сразу `chmod 700 ~/.ssh && chmod 600 ~/.ssh/*` |
| A6 | Репа mono-project **wheezy** (2013 г.) | sources.list.d | НЕ переносим; `mono-complete` из bookworm (там 6.8 — достаточно для GitExtensions) |
| A7 | `raw.github.com` — legacy-домен | install.sh:77 | `raw.githubusercontent.com` |
| A8 | `pip install --user` на bookworm упрётся в PEP 668 (externally-managed) | новый скрипт | `--break-system-packages` + try() |
| A9 | Секция `[bar/example]` в polybar-конфиге мёртвая | home/.config/polybar/config | НЕ трогаем: байт-в-байт с живой машиной дороже красоты |

## Что НЕ переносим (проверено — и не надо)

- GRUB/cmdline, sysctl, `/etc/environment`, xorg.conf(.d), sshd_config — на живой машине чистый дефолт.
- `~/.config/powerline` (копия системного), `~/.oh-my-zsh/custom` (сток), `~/.fonts` (нет), `config.save` i3 (старый мусор), Postman-tarball из `/opt` (дубль snap-версии), `~/.gitconfig` файлом (машинный `safe.directory`; user.name/email задаются командами).
- VMware-специфика: open-vm-tools, xserver-xorg-video-vmware, `ens33` — на железо не едет (ветка по detect-virt).

## Ручной перенос (скрипт напоминает в финальном summary)

| Что | Откуда | Примечание |
|-----|--------|-----------|
| SSH-ключи | все ключи и `config` из `~/.ssh` | на новой машине сразу `chmod 700 ~/.ssh && chmod 600 ~/.ssh/*` |
| Проекты | `/opt/kobus9 /opt/serverKobus ~/WORKSHOP` | rsync/диск |
| buildroot SDK | `/opt/aarch64-buildroot-linux-gnu_sdk-buildroot` (730 МБ) | артефакт, не пересобирается скриптом |
| NXP-тулзы | MCUXpressoInstaller → LinkServer, MCU-Link, lpcscrypt, pemicro | требует логин NXP |
| GitExtensions | `~/bin/GitExtensions` | mono-complete уже ставит скрипт |
| Cursor, RustRover | `~/apps/` | AppImage/tarball, качаются с сайтов |

## Открытые вопросы юзеру

1. NFS-сервер (`/nfs/nfs_debix*` для Debix-плат) нужен на домашнем ноуте? Пока `INSTALL_NFS_SERVER=0`; включается флагом + правкой `NFS_SUBNET` под реальную сеть (в шапке — плейсхолдер).
2. `mecab libmecab-dev` (ставился 2025-11) — зачем был? В скрипт не включён.
3. Переезжаем репо из `~/.ssh/Linux` в `~/Linux` насовсем? Влияет только на привычку, риск утечки ключей снимает.

## Методика тестирования

**ВАЖНО: живой прогон до вечера невозможен** (нет свободного железа/чистой VM в этой сессии) — компенсируем статикой в 4 слоя:

1. **Синтаксис**: `bash -n install.sh` + shellcheck (все SC-ворнинги разобраны).
2. **Имена пакетов**: каждый apt-пакет прогнан через `apt-cache policy` на живой машине — ловит опечатки и несуществующие в bookworm пакеты (TC-P8.1).
3. **Адверсариальное ревью**: независимые агенты симулируют пошаговый прогон на свежем netinstall (порядок команд, errexit-ловушки, идемпотентность второго прогона, интерактивные промпты) — **выполнено, см. таблицу ниже**.
4. **Вечером (жив.)**: TC-P7.1 + полный прогон — результаты дописать сюда с датой.

---

## Ревью 2026-07-23: находки и закрытие

4 независимых ревьюера (walkthrough свежего netinstall, идемпотентность, интерактивные ловушки, гигиена публичного репо), 25 находок. Ключевые:

| # | Находка | Закрытие |
|---|---------|----------|
| R1 | netinstall с заданным root-паролем НЕ ставит sudo и не добавляет юзера в sudoers → «кнопка» не стартует вовсе | pre-flight guard с готовой командой `su -c ...`; в инструкции: root-пароль оставлять пустым |
| R2 | NOPASSWD ставился после 30+ минут качающих секций; sudo-тикет (15 мин) протухает, passwd_timeout=0 → прогон вечно стоит на вводе пароля | `setup_sudo_nopasswd` — первый шаг после `sudo -v`, до любых длинных секций |
| R3 | Лежащая сторонняя репа валила `apt-get update`/общую транзакцию → терялся весь хвост прогона (flatpak, server, zsh, дотфайлы) | оба `update` толерантны (`\|\| warn`); сторонние пакеты ставятся по одному через `try` |
| R4 | preseed EULA mscorefonts — Ubuntu-шаблон, в Debian мёртвый код; реальный риск — SourceForge-зеркала в postinst | preseed убран; mscorefonts в отдельном `try apt_install` |
| R5 | `sh -c "$(упавший curl)"` для oh-my-zsh — молчаливый no-op: chsh сделан, omz нет, каждый новый zsh сыпет ошибками без следа в логе | скачивание в файл + явная проверка `[ -d ~/.oh-my-zsh ]`, всё под `try` |
| R6 | Частичный curl внутри `try`-функций отравлял guard'ы: битый огрызок `/opt/nvim/nvim` после `chmod +x` удовлетворяет `[ -x ]` навсегда | все загрузки во временный файл + атомарный `install`; цепочки `&&` / `return 1` (nvim, repo, lazygit, omz, jlink, deb'ы) |
| R7 | Без `set -o errtrace` ERR-trap не срабатывает внутри функций — смерть прогона без `[FAIL]`-строки в логе | `set -o errexit -o errtrace -o pipefail` |
| R8 | Пакет `discover` в Debian — hardware-id тулза, не KDE Discover | заменён на `plasma-discover` |
| R9 | `snap wait`/`snap install` без таймаута висят вечно при недоступном store | `timeout 600` / `timeout 1800` |
| R10 | dpkg conffile-промпты не глушатся noninteractive → возможное зависание на rerun после point-release | `--force-confdef --force-confold` во всех apt-вызовах |
| R11 | Гигиена публичного репо: имена ssh-ключей и права `~/.ssh` в доках; история вкладок с деревом рабочих проектов в doublecmd.xml | доки обезличены; `<Tabs>` вырезан из doublecmd.xml (XML провалидирован); `NFS_SUBNET` — плейсхолдер |
| R12 | Проверено: rerun на живой VMware-машине безопасен (сеть/NM не трогаются, snap/flatpak идемпотентны), но перезапишет дотфайлы репо-версиями — by design | отмечено в install_usage.md |

Остальные находки — low/«приемлемо» (email в git log уже публичен, hostname VM, ключи вендоров — публичные OpenPGP, история git чиста — проверено по `rev-list --all`), действий не требуют.
