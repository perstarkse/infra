#!/usr/bin/env python3
"""Print a formatted table of exposure manifest entries."""

import json
import sys


def format_exposure_list(manifest):
    rows = []
    for kind, entries in (("export", manifest.get("exports", [])), ("rendered", manifest.get("rendered", []))):
        for entry in entries:
            machine = entry["machine"]
            service = entry["service"]
            upstream = entry.get("upstream", {})
            upstream_text = f"{upstream.get('scheme', 'http')}://{upstream.get('host', '?')}:{upstream.get('port', '?')}"
            router = "yes" if entry.get("router", {}).get("enable") else "no"
            for vhost in entry.get("http", {}).get("virtualHosts", []):
                rows.append((kind, machine, service, vhost.get("domain", "-"), upstream_text, router))
            if not entry.get("http", {}).get("virtualHosts"):
                rows.append((kind, machine, service, "-", upstream_text, router))

    headers = ("KIND", "MACHINE", "SERVICE", "DOMAIN", "UPSTREAM", "ROUTER")
    widths = [len(value) for value in headers]
    for row in rows:
        widths = [max(width, len(str(value))) for width, value in zip(widths, row)]

    def fmt(row):
        return "  ".join(str(value).ljust(width) for value, width in zip(row, widths))

    print(fmt(headers))
    print(fmt(tuple("-" * width for width in widths)))
    for row in sorted(rows):
        print(fmt(row))


def main():
    if len(sys.argv) != 2:
        print("Usage: exposure-list.py <manifest.json>", file=sys.stderr)
        raise SystemExit(1)

    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        manifest = json.load(handle)

    format_exposure_list(manifest)


if __name__ == "__main__":
    main()
