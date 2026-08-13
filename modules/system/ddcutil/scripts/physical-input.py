#!/usr/bin/env python3
"""Turn the monitor on from physical seat input (USB HID / power button).

Ignores uinput (Sunshine), Bluetooth, and SYN/key-release noise so WoL plus a
remote session cannot light the panel.
"""
import glob
import os
import select
import struct
import subprocess
import sys
import time

POLICY_FILE = os.environ.get("MONITOR_POWER_POLICY", "/run/monitor-power/policy")
MONITOR_POWER = os.environ.get("MONITOR_POWER_BIN", "@MONITOR_POWER@")
EVENT = struct.Struct("llHHi")
EV_KEY = 0x01
EV_REL = 0x02


def is_physical_phys(phys: str) -> bool:
    return phys.startswith(("usb-", "LNXPWRBN", "PNP0C0C"))


def is_actionable(ev_type: int, _code: int, value: int) -> bool:
    if ev_type == EV_KEY:
        return value != 0
    if ev_type == EV_REL:
        return value != 0
    return False


def read_phys(event_dev: str) -> str:
    name = os.path.basename(event_dev)
    path = f"/sys/class/input/{name}/device/phys"
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def read_policy() -> str:
    try:
        with open(POLICY_FILE, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return "on"


def write_policy(value: str) -> None:
    os.makedirs(os.path.dirname(POLICY_FILE), exist_ok=True)
    tmp = POLICY_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(value + "\n")
    os.replace(tmp, POLICY_FILE)


def request_on() -> None:
    if read_policy() == "on":
        return
    write_policy("on")
    for _ in range(20):
        result = subprocess.run([MONITOR_POWER, "on"], check=False)
        if result.returncode == 0:
            return
        time.sleep(0.25)


def drain_actionable(fh) -> bool:
    hit = False
    while True:
        chunk = fh.read(EVENT.size)
        if not chunk:
            break
        if len(chunk) != EVENT.size:
            break
        _sec, _usec, ev_type, code, value = EVENT.unpack(chunk)
        if is_actionable(ev_type, code, value):
            hit = True
    return hit


def run_daemon() -> None:
    devices = {}
    while True:
        present = [p for p in glob.glob("/dev/input/event*") if os.access(p, os.R_OK)]
        for path in present:
            if path in devices.values():
                continue
            if not is_physical_phys(read_phys(path)):
                continue
            try:
                fh = open(path, "rb")
                os.set_blocking(fh.fileno(), False)
                devices[fh] = path
            except OSError:
                pass
        for fh in list(devices):
            if devices[fh] not in present:
                try:
                    fh.close()
                except OSError:
                    pass
                del devices[fh]

        if not devices:
            time.sleep(1.0)
            continue

        readable, _, _ = select.select(list(devices), [], [], 1.0)
        for fh in readable:
            try:
                if drain_actionable(fh):
                    request_on()
            except OSError:
                try:
                    fh.close()
                except OSError:
                    pass
                devices.pop(fh, None)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        sys.stderr.write(f"usage: {sys.argv[0]}\n")
        sys.exit(2)
    run_daemon()
