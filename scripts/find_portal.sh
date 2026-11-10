#!/usr/bin/env python3
"""Находит SberPortal в локальной сети (adb по 5555) и печатает host:5555.

IP портала меняется по DHCP, поэтому
скрипты не должны полагаться на жёсткий адрес.

    ./find_portal.sh            # -> <IP>:5555
    IP=<IP> ./test_alisa.sh
"""
import concurrent.futures
import socket
import subprocess
import sys


def local_prefix() -> str:
    out = subprocess.run(
        ["route", "-n", "get", "default"], capture_output=True, text=True
    ).stdout
    ifc = next(
        (line.split(":", 1)[1].strip() for line in out.splitlines() if line.startswith("interface:")),
        "en0",
    )
    ip = subprocess.run(
        ["ipconfig", "getifaddr", ifc], capture_output=True, text=True
    ).stdout.strip()
    return ip.rsplit(".", 1)[0]


def probe(host: str):
    sock = socket.socket()
    sock.settimeout(0.35)
    try:
        sock.connect((host, 5555))
        return host
    except OSError:
        return None
    finally:
        sock.close()


def main() -> int:
    prefix = local_prefix()
    if not prefix:
        print("не удалось определить локальную подсеть", file=sys.stderr)
        return 1
    hosts = [f"{prefix}.{i}" for i in range(1, 255)]
    with concurrent.futures.ThreadPoolExecutor(64) as pool:
        candidates = [host for host in pool.map(probe, hosts) if host]

    for host in candidates:
        addr = f"{host}:5555"
        subprocess.run(["adb", "connect", addr], capture_output=True)
        model = subprocess.run(
            ["adb", "-s", addr, "shell", "getprop", "ro.product.model"],
            capture_output=True,
            text=True,
        ).stdout.strip()
        if model == "SberPortal":
            print(addr)
            return 0

    print(f"SberPortal не найден в {prefix}.0/24", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
