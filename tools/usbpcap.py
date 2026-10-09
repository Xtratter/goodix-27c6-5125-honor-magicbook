"""Минимальный разбор pcap-файла USBPcap (link type 249) без tshark.

Использование:
    python3 -I usbpcap.py capture.pcap

Для каждого пакета выводит: шину, адрес устройства, endpoint, направление,
тип передачи, длину данных и первые 48 байт в hex.
"""
import struct
import sys


def main(path):
    data = open(path, "rb").read()
    magic, _vmaj, _vmin, _tz, _sig, _snap, link = struct.unpack("<IHHiIII", data[:24])
    print("magic %x link %d" % (magic, link))
    if link != 249:
        sys.exit("ожидался link type 249 (USBPcap)")

    off = 24
    n = 0
    while off + 16 <= len(data):
        _ts, _tu, incl, _orig = struct.unpack("<IIII", data[off:off + 16])
        off += 16
        pkt = data[off:off + incl]
        off += incl
        # заголовок USBPcap: hlen, irp id, status, function, info, bus, device, endpoint, transfer, data length
        hlen, _irp, status, func, info, bus, dev, ep, xfer, dlen = struct.unpack("<HQIHBHHBBI", pkt[:27])
        payload = pkt[hlen:]
        direction = "IN " if ep & 0x80 else "OUT"
        print(
            n,
            "bus%d dev%d ep%02x %s xfer%d info%d len%d st%x func%x"
            % (bus, dev, ep, direction, xfer, info, dlen, status, func),
            payload[:48].hex(),
        )
        n += 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
