[English](install.md) | **Русский**

# Установка в Arch/Manjaro

Проверено на Manjaro (ядро 6.18, KDE Plasma 6.7, fprintd 1.94.5, libfprint 1.94.100) на
HONOR MagicBook BMH-WDX9. Команды с `sudo` выполняйте сами в терминале.

**Сначала прочитайте код драйвера.** Он ставится как замена системного `libfprint` и работает
с root-правами в составе fprintd. Я читал коммит `a9286cc` (ветка `goodix5125-mr`): в нём нет
запуска процессов, сети и записей вне каталога `/var/lib/fprint/goodix5125`; запись PSK в
сканер выполняется только при `GOODIX5125_PROVISION_PSK=random`.

## 1. Зависимости и сборка

```sh
sudo pacman -S --needed base-devel git meson libgusb glib2-devel fprintd

git clone https://github.com/RuVl/FingerprintDriver_27c6_5125
git clone --branch goodix5125-mr https://gitlab.freedesktop.org/RuVl/libfprint.git libfprint-goodix5125
# зафиксировать тот самый проверенный коммит
git -C libfprint-goodix5125 checkout -B goodix5125-mr a9286cc

cd FingerprintDriver_27c6_5125/packaging/arch
LIBFPRINT_GOODIX5125_REPO=file://$HOME/libfprint-goodix5125 \
LIBFPRINT_GOODIX5125_BRANCH=goodix5125-mr \
makepkg -C
```

Так собирается ровно тот код, который вы только что прочитали, а не свежая версия ветки.
Результат: файл `libfprint-goodix5125-git-*.pkg.tar.zst` в `packaging/arch/`.

## 2. Установка

```sh
sudo pacman -U libfprint-goodix5125-git-*.pkg.tar.zst   # на вопрос о замене libfprint ответьте «да»
sudo systemctl restart fprintd
```

Откат: `sudo pacman -S libfprint`.

## 3. Ключ сопряжения (PSK)

Драйвер читает ключ из `/var/lib/fprint/goodix5125/psk` и сравнивает его хеш с тем, что хранит
сканер. Сначала проверьте нулевой ключ (у автора драйвера Windows использует именно его):

```sh
sudo install -d -m 700 /var/lib/fprint/goodix5125
printf '%064d\n' 0 | sudo install -m 600 /dev/stdin /var/lib/fprint/goodix5125/psk
fprintd-enroll -f right-thumb
```

Если регистрация упала с `enroll-unknown-error`, причина в журнале:
`journalctl -u fprintd --since -5min --no-pager`. Сообщение `hash differs` значит,
что в сканере другой ключ. Сканер при этом не изменяется.

### Запись нового ключа (только если нулевой не подошёл)

Это необратимо и может нарушить сопряжение с Windows. Сначала **удалите файл ключа**, иначе
драйвер запишет в сканер ключ из этого файла (нулевой):

```sh
sudo rm /var/lib/fprint/goodix5125/psk
sudo systemctl set-environment GOODIX5125_PROVISION_PSK=random
sudo systemctl restart fprintd
fprintd-enroll -f right-thumb      # первое открытие устройства записывает ключ
sudo systemctl unset-environment GOODIX5125_PROVISION_PSK
sudo systemctl restart fprintd
```

После этого **не удаляйте** `/var/lib/fprint/goodix5125/psk`: это единственная копия ключа.

## 4. Проверка

```sh
fprintd-verify
```

Ожидаемый ответ: `verify-match`. Регистрация занимает около 13 касаний: слегка сдвигайте
палец, но держите его на одной части подушечки.

## 5. sudo по отпечатку

```sh
sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.bak-before-fprint
```

Затем добавьте **первой строкой `auth`** в `/etc/pam.d/sudo`:

```
auth  sufficient  pam_fprintd.so max-tries=3 timeout=15
```

Правьте файл при открытой root-оболочке в другом окне. Без касания `sudo` ждёт 15 секунд и
переходит к паролю. Откат: `sudo cp /etc/pam.d/sudo.bak-before-fprint /etc/pam.d/sudo`.

## 6. Экран блокировки KDE

Менять ничего не нужно: `kscreenlocker` сам поставляет `/usr/lib/pam.d/kde-fingerprint` с
`pam_fprintd.so`, и экран блокировки использует записанный в fprintd отпечаток.

## Использование на экране блокировки (KDE Plasma 6.7)

- **Сначала разбудите экран блокировки.** Экран блокировки Plasma запускает проверку отпечатка только когда его интерфейс становится видимым, то есть после
  нажатия клавиши, щелчка или движения мыши (его `LockScreenUi.qml` вызывает `authenticator.startAuthenticating()` только по этому событию). По журналам
  сканер занимается через 8-12 с после блокировки, когда пользователь впервые что-то нажал. Палец, приложенный сразу после блокировки, не читается.
- **Держите палец примерно полсекунды**, а не «тапайте». Быстрое касание часто даёт пустой кадр (палец уходит раньше, чем снят кадр); после трёх пустых
  кадров драйвер просит повторить, и это выглядит как «не работает».
- Интерфейс снова прячется через 10 с, и проверка перезапускается при его показе; пошевелите мышь и приложите палец ещё раз.

## Необязательно: патчи точности и скорости

Три небольших патча к драйверу (повтор слабых кадров, порог покрытия, ответ за ~0,15 с вместо ~1,5 с) лежат в
[`patches/`](../patches/); что они меняют и насколько верить замерам, написано в [accuracy-patch.ru.md](accuracy-patch.ru.md).
Применяйте их к `libfprint-goodix5125` командой `git am` перед `makepkg` из шага 1.

## Проверка состояния

```sh
scripts/check.sh            # только чтение, касание не нужно
scripts/check.sh --verify   # дополнительно запускает fprintd-verify (приложите палец)
```

Проверяет: сканер виден, установлен пакет `libfprint` с драйвером `goodix5125`, файл PSK на месте,
палец записан, PAM настроен. Запускайте после любого обновления системы.

## Обновления

Собранный пакет называется `libfprint-goodix5125-git` и предоставляет `libfprint`, поэтому обычный
`pacman -Syu` не ставит стандартный `libfprint` поверх него. Сломать установку всё же могут две вещи:

- **Новый `fprintd`, которому нужна более новая версия ABI `libfprint`.** `pacman` покажет ошибку
  зависимости. Пересоберите драйвер на более свежей основе (повторите шаги 1-2 с новой веткой
  драйвера), а не форсируйте обновление.
- **Ручная установка стандартного пакета** (`pacman -S libfprint`). Если добавить `libfprint` в
  `IgnorePkg` в `/etc/pacman.conf`, `pacman` сначала спросит подтверждение. Это необязательно:
  настройка защищает от ошибки, а не от обычных обновлений.

После любого обновления системы запускайте `scripts/check.sh`: он покажет, на месте ли драйвер.
