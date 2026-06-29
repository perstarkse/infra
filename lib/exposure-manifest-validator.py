#!/usr/bin/env python3
"""Validate exposure manifest structure and consistency."""

import json
import re
import sys
from collections import defaultdict

DOMAIN_RE = re.compile(r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*\.?$")


def fail(message):
    print(f"exposure-manifest-check: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(condition, message):
    if not condition:
        fail(message)


def validate_manifest(manifest):
    require(isinstance(manifest, dict), "manifest must be an object")
    exports = manifest.get("exports", [])
    rendered = manifest.get("rendered", [])
    require(isinstance(exports, list), "manifest.exports must be a list")
    require(isinstance(rendered, list), "manifest.rendered must be a list")
    all_entries = exports + rendered
    seen_services = set()
    domains = defaultdict(list)
    dns_records = defaultdict(list)
    entries_by_owner = {}

    for entry in all_entries:
        require(isinstance(entry, dict), "manifest entries must be objects")
        machine = entry.get("machine")
        service = entry.get("service")
        require(isinstance(machine, str) and machine, "entry machine must be a non-empty string")
        require(isinstance(service, str) and service, f"entry service for {machine or '<unknown>'} must be a non-empty string")
        key = (machine, service)
        require(key not in seen_services, f"duplicate service entry {machine}.{service}")
        seen_services.add(key)
        owner = f"{machine}.{service}"
        entries_by_owner[owner] = entry

        upstream = entry.get("upstream", {})
        require(isinstance(upstream, dict), f"{machine}.{service}: upstream must be an object")
        host = upstream.get("host")
        port = upstream.get("port")
        scheme = upstream.get("scheme")
        require(isinstance(host, str) and host, f"{machine}.{service}: upstream.host must be set")
        require(scheme in ("http", "https"), f"{machine}.{service}: upstream.scheme must be http or https")

        http = entry.get("http", {})
        require(isinstance(http, dict), f"{machine}.{service}: http must be an object")
        vhosts = http.get("virtualHosts", [])
        require(isinstance(vhosts, list), f"{machine}.{service}: http.virtualHosts must be a list")
        if vhosts:
            require(isinstance(port, int) and 1 <= port <= 65535, f"{machine}.{service}: upstream.port must be set when virtual hosts exist")

        for index, vhost in enumerate(vhosts):
            require(isinstance(vhost, dict), f"{machine}.{service}: vhost {index} must be an object")
            domain = vhost.get("domain")
            require(isinstance(domain, str) and DOMAIN_RE.match(domain), f"{machine}.{service}: invalid vhost domain {domain!r}")
            target_port = vhost.get("targetPort")
            require(target_port is None or (isinstance(target_port, int) and 1 <= target_port <= 65535), f"{machine}.{service}: invalid targetPort for {domain}")
            target_scheme = vhost.get("targetScheme")
            require(target_scheme is None or target_scheme in ("http", "https"), f"{machine}.{service}: invalid targetScheme for {domain}")
            domains[domain].append(owner)

        dns = entry.get("dns", {})
        require(isinstance(dns, dict), f"{machine}.{service}: dns must be an object")
        records = dns.get("records", [])
        require(isinstance(records, list), f"{machine}.{service}: dns.records must be a list")
        for index, record in enumerate(records):
            require(isinstance(record, dict), f"{machine}.{service}: dns record {index} must be an object")
            name = record.get("name")
            target = record.get("target")
            require(isinstance(name, str) and DOMAIN_RE.match(name), f"{machine}.{service}: invalid dns name {name!r}")
            require(isinstance(target, str) and target, f"{machine}.{service}: dns target for {name} must be set")
            dns_records[name].append((target, owner))

        firewall = entry.get("firewall", {})
        require(isinstance(firewall, dict), f"{machine}.{service}: firewall must be an object")
        local = firewall.get("local", {})
        require(isinstance(local, dict), f"{machine}.{service}: firewall.local must be an object")
        for protocol in ("tcp", "udp"):
            ports = local.get(protocol, [])
            require(isinstance(ports, list), f"{machine}.{service}: firewall.local.{protocol} must be a list")
            for port_value in ports:
                require(isinstance(port_value, int) and 1 <= port_value <= 65535, f"{machine}.{service}: invalid {protocol} firewall port {port_value!r}")

    def allowed_import_duplicate(owners):
        if len(owners) != 2:
            return False
        first, second = owners
        first_entry = entries_by_owner[first]
        second_entry = entries_by_owner[second]
        rendered_entry = first_entry if first_entry.get("renderedFrom") else second_entry if second_entry.get("renderedFrom") else None
        source_entry = second_entry if rendered_entry is first_entry else first_entry if rendered_entry is second_entry else None
        if not rendered_entry or not source_entry:
            return False
        rendered_from = rendered_entry.get("renderedFrom") or {}
        return rendered_from.get("machine") == source_entry["machine"] and rendered_from.get("service") == source_entry["service"]

    duplicate_domains = {domain: owners for domain, owners in domains.items() if len(owners) > 1}
    unexpected_duplicate_domains = {
        domain: owners
        for domain, owners in duplicate_domains.items()
        if not allowed_import_duplicate(owners)
    }
    require(not unexpected_duplicate_domains, "duplicate vhost domains: " + ", ".join(f"{domain} -> {owners}" for domain, owners in sorted(unexpected_duplicate_domains.items())))
    if duplicate_domains:
        print("router import/source duplicate domains allowed: " + ", ".join(f"{domain} -> {owners}" for domain, owners in sorted(duplicate_domains.items()) if allowed_import_duplicate(owners)))

    conflicting_dns = {name: values for name, values in dns_records.items() if len({target for target, _owner in values}) > 1}
    require(not conflicting_dns, "conflicting dns records: " + ", ".join(f"{name} -> {values}" for name, values in sorted(conflicting_dns.items())))
    print(f"validated {len(exports)} exposure exports and {len(rendered)} rendered imports")


def main():
    if len(sys.argv) != 2:
        print("Usage: exposure-manifest-validator.py <manifest.json>", file=sys.stderr)
        raise SystemExit(1)

    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        manifest = json.load(handle)

    validate_manifest(manifest)


if __name__ == "__main__":
    main()
