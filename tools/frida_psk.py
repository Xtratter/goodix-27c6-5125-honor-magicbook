"""Перехват CryptUnprotectData в процессах драйвера Goodix (WUDFHost.exe и т.п.).

STATUS (EN): did NOT work in practice - no CryptUnprotectData calls were captured; kept
as a starting point. Writing a new PSK was the path that worked (see docs/install.md).

СТАТУС: на практике НЕ сработал (вызовы не были перехвачены, причину выяснить не
удалось). Оставлен как отправная точка; рабочим путём оказалась запись нового PSK
(см. docs/install.ru.md).

Запускать в Windows от имени администратора:
    pip install frida frida-tools
    python frida_psk.py

Пока скрипт работает, в ДРУГОМ окне (тоже от администратора) перезапустите сканер:
    pnputil /restart-device "USB\\VID_27C6&PID_5125\\<INSTANCE_SERIAL>"

Драйвер при старте читает C:\\ProgramData\\Goodix\\Goodix_Cache.bin и вызывает
CryptUnprotectData. Скрипт ловит вызовы, у которых вход 324/332 байта и энтропия 48 байт,
и сохраняет вход, энтропию и результат (32 байта, это PSK) в goodix_psk_dump.json.

ВАЖНО: в json лежит секретный ключ сканера. Не публикуйте файл.
Скрипт только читает память процесса и ничего не меняет в нём и в сканере.
"""
import json
import sys
import time

import frida

TARGET_NAMES = {"wudfhost.exe", "sessionservice.exe"}
OUT = "goodix_psk_dump.json"

JS = r"""
'use strict';

function findExport(mod, name) {
  try {
    if (typeof Process.getModuleByName === 'function') {
      var m = Process.getModuleByName(mod);
      if (typeof m.getExportByName === 'function') return m.getExportByName(name);
    }
  } catch (e) {}
  try { return Module.getExportByName(mod, name); } catch (e) {}
  try { return Module.findExportByName(mod, name); } catch (e) {}
  return null;
}

function readBlob(p) {
  if (p.isNull()) return null;
  var ps = Process.pointerSize;
  var len = p.readU32();
  var data = p.add(ps).readPointer();
  if (data.isNull() || len === 0 || len > 0x100000) return { len: len, hex: '' };
  return { len: len, hex: hexString(data.readByteArray(len)) };
}

function hexString(buf) {
  var a = new Uint8Array(buf), s = '';
  for (var i = 0; i < a.length; i++) s += ('0' + a[i].toString(16)).slice(-2);
  return s;
}

var hooked = [];
['crypt32.dll', 'dpapi.dll'].forEach(function (mod) {
  var addr = findExport(mod, 'CryptUnprotectData');
  if (!addr || hooked.indexOf(addr.toString()) !== -1) return;
  hooked.push(addr.toString());
  Interceptor.attach(addr, {
    onEnter: function (args) {
      this.inBlob = readBlob(args[0]);
      this.entropy = readBlob(args[2]);
      this.outPtr = args[6];
    },
    onLeave: function (retval) {
      var out = retval.toInt32() !== 0 ? readBlob(this.outPtr) : null;
      send({
        type: 'CryptUnprotectData',
        module: mod,
        ok: retval.toInt32() !== 0,
        in: this.inBlob,
        entropy: this.entropy,
        out: out
      });
    }
  });
});
send({ type: 'hooked', count: hooked.length });
"""

results = []
attached = {}


def on_message_factory(pid, name):
    def on_message(message, _data):
        if message["type"] == "error":
            print(f"[{pid} {name}] ошибка скрипта: {message.get('description')}")
            return
        payload = message["payload"]
        if payload["type"] == "hooked":
            print(f"[{pid} {name}] хуков установлено: {payload['count']}")
            return
        payload["pid"] = pid
        payload["process"] = name
        results.append(payload)
        in_len = payload["in"]["len"] if payload["in"] else None
        ent_len = payload["entropy"]["len"] if payload["entropy"] else None
        out_len = payload["out"]["len"] if payload["out"] else None
        flag = " <== похоже на PSK Goodix" if ent_len == 48 and out_len == 32 else ""
        print(f"[{pid} {name}] CryptUnprotectData in={in_len} entropy={ent_len} out={out_len}{flag}")
        with open(OUT, "w") as f:
            json.dump(results, f, indent=2)

    return on_message


def attach(device, proc):
    try:
        session = device.attach(proc.pid)
        script = session.create_script(JS)
        script.on("message", on_message_factory(proc.pid, proc.name))
        script.load()
        attached[proc.pid] = session
        print(f"подключился к {proc.name} (pid {proc.pid})")
    except Exception as e:  # процесс мог завершиться или быть недоступен
        attached[proc.pid] = None
        print(f"не удалось подключиться к {proc.name} (pid {proc.pid}): {e}")


def main():
    extra = {a.lower() for a in sys.argv[1:]}
    names = TARGET_NAMES | extra
    device = frida.get_local_device()
    print("жду процессы:", ", ".join(sorted(names)))
    print("теперь перезапустите сканер (pnputil /restart-device ...). Ctrl+C - выход.")
    try:
        while True:
            for proc in device.enumerate_processes():
                if proc.pid not in attached and proc.name.lower() in names:
                    attach(device, proc)
            time.sleep(0.05)
    except KeyboardInterrupt:
        pass
    print(f"перехвачено вызовов: {len(results)}; результат в {OUT}")


if __name__ == "__main__":
    main()
