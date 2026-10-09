[English](findings.md) | **Русский**

# Что выяснено

Всё ниже получено наблюдением за собственным устройством и логами Windows-драйвера.
Где это догадка, так и сказано.

## USB-дескриптор

`lsusb -v -d 27c6:5125`:

- класс устройства 2 (CDC), подкласс 1, протокол 1; скорость Full Speed;
- интерфейс 0: CDC Communications, interrupt IN `0x82` (8 байт);
- интерфейс 1: CDC Data, bulk OUT `0x01` и bulk IN `0x81` (по 64 байта);
- драйвер ядра по умолчанию не привязывается (нет `/dev/ttyACM*`), доступ идёт через libusb.

Class 2 отличает его от многих других Goodix: большинство работает через vendor-specific
интерфейс.

## Сенсор и данные

Из отладочного журнала Windows-драйвера (`gfusb.dll` 1.1.125.12, 2021-05-25):

- тип сенсора 12, кадр 64 x 80 пикселей, 10240 байт на кадр (значит, 16 бит на пиксель;
  автор драйвера libfprint пишет про 12-битные данные);
- сопоставление отпечатков выполняется **на хосте** (`AlgoMilan.dll`, `AlgoChicago*.dll`,
  в логе `CompareTime 15ms`). Сканер отдаёт изображения, а не результат (это не match-on-chip).

## Транспорт

В захвате Windows (USBPcap) трафик сканера идёт по bulk endpoint'ам `0x01`/`0x81`. Кадры
выглядят как `[байт типа][длина, 2 байта LE][данные ...]`. Наблюдения:

- тип `0xa0` - короткие командные сообщения и подтверждения;
- тип `0xb0` - передача TLS: внутри видны записи `17 03 03` (TLS application data), то есть
  изображения идут поверх TLS;
- в журнале драйвера виден хендшейк TLS и режим PSK; в захвате самого хендшейка нет,
  потому что запись началась уже в середине сессии.

## Ключ сопряжения (PSK)

Из журнала Windows-драйвера (`production_get_host_psk_data`, `gf_unseal_data`):

1. драйвер читает `C:\ProgramData\Goodix\Goodix_Cache.bin` (332 байта);
2. распаковывает блоб функцией `CryptUnprotectData` (DPAPI): вход 324 байта, **энтропия 48
   байт** (функция `generate_entropy2` внутри `gfusb.dll`), выход 32 байта - это PSK;
3. из PSK строится «white-box» блок (32 -> 102 байта), берётся хеш (32 байта) и сравнивается
   с хешем, который хранит сканер.

`gfusb.dll` импортирует `CryptUnprotectData` из `CRYPT32.dll`.

Схема вычисления энтропии нигде не опубликована (поиск по issues goodix-fp-dump, libfprint и
по открытым репозиториям ничего не дал). Расшифровать блоб без неё нельзя: нужны ещё мастер-ключ
DPAPI и контекст учётной записи, под которой работает драйвер.

## Что не получилось

- **Нулевой PSK.** На устройстве автора драйвера Windows использует ключ из нулей. У меня
  драйвер libfprint ответил: `The Goodix PSK ... does not match the sensor (hash differs)`.
  Сканер был предварительно сопряжён с другим ключом.
- **Перехват через Frida** (`tools/frida_psk.py`): хук `CryptUnprotectData` в `WUDFHost.exe`
  не поймал ни одного вызова. Причина не установлена (возможные: процесс не подключился,
  ключ читается раньше установки хука, защита процесса).

## Что сработало

Записать в сканер новый случайный PSK штатным механизмом драйвера libfprint
(`GOODIX5125_PROVISION_PSK=random`, один раз). Ключ сохраняется в
`/var/lib/fprint/goodix5125/psk` до записи в сканер.

**Последствия для Windows** (из чужих описаний, на моём ноутбуке не проверено): Windows-драйвер
при несовпадении ключа, вероятно, проведёт новое сопряжение сам; шаблоны отпечатков хранятся
на хосте. Возможно, Windows Hello придётся настраивать заново, а Linux после этого нужно будет
перепаривать.

## Полезные ссылки

- [RuVl/FingerprintDriver_27c6_5125](https://github.com/RuVl/FingerprintDriver_27c6_5125) -
  драйвер, алгоритм сопоставления openchicago и инструменты;
- [libfprint!669](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/669) -
  merge request с драйвером;
- [goodix-fp-dump](https://github.com/goodix-fp-linux-dev/goodix-fp-dump) - исследования
  протокола Goodix, issues [#60](https://github.com/goodix-fp-linux-dev/goodix-fp-dump/issues/60),
  [#63](https://github.com/goodix-fp-linux-dev/goodix-fp-dump/issues/63),
  [#80](https://github.com/goodix-fp-linux-dev/goodix-fp-dump/issues/80);
- [Neodyme: Reversing a fingerprint reader](https://neodyme.io/en/blog/fingerprint_reversing) -
  общий разбор Goodix TLS-PSK.
