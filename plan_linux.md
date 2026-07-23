# Linux — План реализации однокнопочной установки Debian 12

Полная спека (вердикты, факты, дизайн, тест-кейсы): **docs/spec_install.md**.
Инструкция на вечер: **docs/install_usage.md**.

**ВАЖНО**: запускать только `bash install.sh` (НЕ `sh` — умрёт на Bad substitution, это P5).

---

## Этап 0: Аудит живой системы ✅

| # | Задача | Статус |
|---|--------|--------|
| 0.1 | Пакеты: showmanual 329 + история apt (44 команды) + софт мимо apt | ✅ 2026-07-23 |
| 0.2 | Дотфайлы: полный diff репо ↔ живые, поиск дрифта и мусора | ✅ 2026-07-23 |
| 0.3 | Система: /etc, службы, группы, udev, alternatives, звук, сеть | ✅ 2026-07-23 |
| 0.4 | Стиль доков из magican2 | ✅ 2026-07-23 |

## Этап 1: Конфиги в репо готовыми файлами ✅

| # | Файл | Что чистилось | Статус |
|---|------|---------------|--------|
| 1.1 | `home/.zshrc` | ничего (живой чистый) | ✅ |
| 1.2 | `home/.zprofile` | 4 дубля PATH → 1 строка | ✅ |
| 1.3 | `home/.zshenv` | cargo env под guard `[ -f ]` | ✅ |
| 1.4 | `home/.Xresources` | как есть (size=13, termName — ручные правки) | ✅ |
| 1.5 | `home/.xinitrc` | мёртвые строки после `exec i3` убраны; раскладка → `grp:win_space_toggle` | ✅ |
| 1.6 | `home/.config/i3/config` | `$mod+space focus mode_toggle` закомментирован (конфликт с переключалкой); путь polybar → `~` | ✅ |
| 1.7 | `home/.config/polybar/{config,launch.sh}` | launch.sh файлом (+x), config байт-в-байт | ✅ |
| 1.8 | `home/.config/{git/ignore,htop/htoprc,mimeapps.list,doublecmd/*}` + `home/bin/telega.sh` | без history.xml/session.ini/кэшей; история вкладок `<Tabs>` вырезана из doublecmd.xml (ревью R11); секретов нет (проверено grep) | ✅ |
| 1.9 | `etc/default/keyboard` | rctrl → win_space | ✅ |
| 1.10 | `etc/udev/rules.d/99-usb-serial.rules` | как есть (ttyUSB* 0666) | ✅ |
| 1.11 | `etc/apt/*`: sources.list (contrib+non-free), 5 реп + gpg-ключи с живой машины | mono-wheezy НЕ перенесён (A6) | ✅ |
| ~~1.12~~ | ~~`home/.bashrc`, `home/.profile`~~ | **СНЯТ** 2026-07-23: шелл zsh; в .bashrc битый TERM (A3) | — |

## Этап 2: install.sh v2 ✅

| # | Секция | Зависит от | Статус |
|---|--------|------------|--------|
| 2.1 | Guards: bash-check, Debian 12, не-root, sudo pre-flight (кейс root-пароля, R1), NOPASSWD сразу после `sudo -v` (R2), абс. SCRIPT_PATH, trap ERR + errtrace (R7), лог в файл | — | ✅ |
| 2.2 | apt: sources.list + preseed EULA + update/upgrade | 2.1 | ✅ |
| 2.3 | base: X, urxvt, шрифты, курсор, звук (pulseaudio), CLI-утилиты | 2.2 | ✅ |
| 2.4 | hardware: vmware→vm-tools; железо→NM+nm-applet, firmware, microcode по вендору, bluez, tlp при батарее | 2.2 | ✅ |
| 2.5 | система: локали, таймзона, клавиатура, группы, udev (sudoers переехал в 2.1 — ревью R2) | 2.2 | ✅ |
| 2.6 | desktop-приложения + dev base + embedded + Qt + Yocto deps (флаги) | 2.3 | ✅ |
| 2.7 | сторонние репы из etc/apt + chrome.deb + discord/gitkraken/jlink через try() | 2.2 | ✅ |
| 2.8 | flatpak (Flameshot, Telegram) + snap (android-studio, postman) через try() | 2.2 | ✅ |
| 2.9 | server: ssh, postgresql; NFS — флаг OFF по умолчанию (вопрос юзеру №1) | 2.2 | ✅ |
| 2.10 | zsh+omz (unattended) → дотфайлы поверх → chsh | 2.3 | ✅ |
| 2.11 | user tools: rustup(+rustlings), nvm+node22, claude, lazygit, nvim+LazyVim, repo, git config | 2.10 | ✅ |
| 2.12 | финальный summary: ручной перенос + пропущенные try()-шаги + reboot | всё | ✅ |

## Этап 3: Верификация (статика) ✅

1. ✅ `bash -n` — чисто.
2. ✅ shellcheck — все ворнинги разобраны.
3. ✅ TC-P8.1: все apt-имена через `apt-cache policy` на живой машине.
4. ✅ Адверсариальное ревью: 4 агента (walkthrough, идемпотентность, интерактив, гигиена репо), 25 находок, все закрыты/сняты — таблица R1–R12 в спеке.

## Этап 4: Прогон в чистой VM ⬜ (добавлен 2026-07-23 по решению юзера: сначала VM, потом железо)

Свежая VM с debian-12-netinst, галки по docs/install_usage.md (root-пароль ПУСТОЙ).

1. ⬜ Обычный прогон: `git clone https://github.com/teleportboy/Linux ~/Linux && bash ~/Linux/Debian/install.sh` → доехал до DONE без единого вопроса после ввода пароля; SKIPPED пуст либо каждая строка объяснима (лежащий сторонний сайт).
2. ⬜ Ветка железа: `FORCE_VIRT=none bash ~/Linux/Debian/install.sh` — NM+firmware+microcode встали, `/etc/network/interfaces` переписан на lo-only (бэкап создан), после reboot сеть жива (интерфейс забрал NM).
3. ⬜ Повторный прогон (TC-P3.1): `grep -c /usr/sbin ~/.zprofile` = 1, без ложных SKIPPED, apt update с лежащей репой не валит прогон.
4. ⬜ reboot → `startx`: i3+polybar живы, раскладка Win+Space работает, urxvt JetBrains Mono 13.
5. ⬜ Результаты в спеку («Статус») с датой; найденное — новыми строками в «Известные баги».

## Этап 5: Живой прогон на железе ⬜ (после Этапа 4)

1. ⬜ Debian 12 netinstall (галки по docs/install_usage.md, root-пароль ПУСТОЙ).
2. ⬜ `git clone https://github.com/teleportboy/Linux ~/Linux && bash ~/Linux/Debian/install.sh`.
3. ⬜ reboot → login → `startx` → TC-P7.1 (Wi-Fi через nmtui), раскладка Win+Space.
4. ⬜ Ручной перенос по таблице из спеки (~/.ssh с правами 700/600!, /opt/*, ~/WORKSHOP, NXP, Cursor/RustRover).
5. ⬜ Результаты прогона дописать в спеку («Статус») с датой.

## Этап 6: preseed («2 кнопки») ⏸

⏸ отложено решением юзера 2026-07-23: вечером — надёжная 1 кнопка; preseed делаем отдельно и обкатываем в VM, не на живом железе.

---

## Что НЕ трогаем

- Живые конфиги текущей машины (rearm) — источник истины уже снят в репо, машина рабочая.
- `[bar/example]` в polybar (A9), GRUB/sysctl/xorg.conf (дефолт), mono-wheezy репа (A6 — mono из bookworm).

## Известные баги / грабли

| # | Баг | Workaround |
|---|-----|------------|
| B1 | `git clone` в `~/.ssh/Linux` на свежей машине падает — git не создаёт родительские каталоги | клонировать в `~/Linux` (инструкция); вопрос юзеру о переезде насовсем |
| B2 | J-Link .deb требует принятия лицензии на сайте SEGGER | try(): POST `accept_license_agreement=accepted`; если сломают — скачать руками, `apt install ./jlink.deb` |
| B3 | NXP-тулзы (LinkServer, MCU-Link, lpcscrypt, pemicro) не автоматизируются | MCUXpressoInstaller руками под аккаунтом NXP |
| B4 | snap сразу после установки snapd может не успеть просидиться | в скрипте `snap wait system seed.loaded` + try() |
