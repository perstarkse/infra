#!/usr/bin/env python3
"""Classifier tests for modules/system/ddcutil/scripts/physical-input.py."""
import importlib.util
import os
import sys


def load(path):
    spec = importlib.util.spec_from_file_location("physical_input", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_phys(mod):
    assert mod.is_physical_phys("usb-0000:05:00.1-4.1.1/input0")
    assert mod.is_physical_phys("LNXPWRBN/button/input0")
    assert mod.is_physical_phys("PNP0C0C/button/input0")
    assert not mod.is_physical_phys("")
    assert not mod.is_physical_phys("08:bf:b8:4a:50:86")
    assert not mod.is_physical_phys("py-evdev-uinput")


def test_events(mod):
    assert mod.is_actionable(mod.EV_KEY, 30, 1)
    assert mod.is_actionable(mod.EV_KEY, 30, 2)
    assert not mod.is_actionable(mod.EV_KEY, 30, 0)
    assert mod.is_actionable(mod.EV_REL, 0, 1)
    assert not mod.is_actionable(mod.EV_REL, 0, 0)
    assert not mod.is_actionable(0, 0, 0)


def test_request_on_when_off(mod):
    mod.request_on()
    assert mod.read_policy() == "on"
    with open(os.environ["POWER_LOG"], "r", encoding="utf-8") as fh:
        log = fh.read()
    assert "on\n" in log, log


def test_request_on_skips_when_on(mod):
    mod.request_on()
    with open(os.environ["POWER_LOG"], "r", encoding="utf-8") as fh:
        log = fh.read()
    assert log == "", log


def main():
    mod = load(sys.argv[1])
    test_phys(mod)
    test_events(mod)
    test_request_on_when_off(mod)
    os.environ["POWER_LOG"]  # required
    with open(os.environ["POWER_LOG"], "w", encoding="utf-8"):
        pass
    with open(os.environ["MONITOR_POWER_POLICY"], "w", encoding="utf-8") as fh:
        fh.write("on\n")
    test_request_on_skips_when_on(mod)


if __name__ == "__main__":
    main()
