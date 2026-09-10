#!/usr/bin/env python3
"""Fail closed when a secret generator's tags are discovered by no machine.

Every vars/generators/*.nix generator must share at least one tag with at
least one machines/*/configuration.nix includeTags list. Otherwise the
secret deploys nowhere (silent missing-file at runtime — the air-exhaust
precedent, where an io-local declaration never reached charon's inventory).

Deliberately one-directional: the reverse (every includeTags entry matches
a generator) is NOT checked, because tags are also produced dynamically
(interpolated meta.tags like politikerstod-${name}) and programmatically
(my.secrets.declarations, e.g. wireguard-tunnels) — both invisible to
static parsing. Enforcing it would force tag renames for zero safety gain.

Usage: secrets-discovery-check.py <repo-root>
Exit 0 when closed, 1 with a failure list otherwise. Read-only.
"""

import pathlib
import re
import sys

TAG_RE = re.compile(r'"([^"$]+)"')


def quoted_tokens(text: str) -> set[str]:
    # Skip interpolated fragments ("politikerstod-${name}"): only whole
    # static tokens count.
    return {t for t in TAG_RE.findall(text) if "${" not in t}


def bracket_list(source: str, key: str) -> set[str]:
    m = re.search(key + r"\s*=\s*\[(.*?)\]", source, re.DOTALL)
    if not m:
        return set()
    return quoted_tokens(m.group(1))


def main() -> int:
    root = pathlib.Path(sys.argv[1])
    gen_dir = root / "vars" / "generators"
    machines_dir = root / "machines"

    generators: dict[str, set[str]] = {}
    for path in sorted(gen_dir.glob("*.nix")):
        text = path.read_text()
        # meta.tags may appear at top level or inside the generator object;
        # collect every tags=[...] list in the file and union them.
        tags: set[str] = set()
        for m in re.finditer(r"tags\s*=\s*\[(.*?)\]", text, re.DOTALL):
            tags |= quoted_tokens(m.group(1))
        generators[path.name] = tags

    machines: dict[str, set[str]] = {}
    for conf in sorted(machines_dir.glob("*/configuration.nix")):
        machines[conf.parent.name] = bracket_list(conf.read_text(), "includeTags")

    failures: list[str] = []
    for gen, tags in generators.items():
        if not tags:
            failures.append(f"{gen}: no parseable meta.tags (check syntax)")
            continue
        discoverers = sorted(m for m, itags in machines.items() if tags & itags)
        if not discoverers:
            failures.append(
                f"{gen}: tags {sorted(tags)} discovered by NO machine "
                "(secret would deploy nowhere)"
            )

    if failures:
        print("secrets-discovery-check FAILED:")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print(
        f"secrets-discovery-check OK: "
        f"{len(generators)} generators all discovered by "
        f"{len(machines)} machines"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
