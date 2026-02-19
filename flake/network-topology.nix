{
  pkgs,
  lib,
  nodes,
  networks,
}: let
  escape = s:
    lib.replaceStrings ["\"" "\n"] ["\\\"" "\\n"] (toString s);

  networkIds = builtins.attrNames networks;

  interfaceEntries = lib.flatten (
    lib.mapAttrsToList (
      nodeName: node:
        lib.mapAttrsToList (
          ifName: iface:
            if iface.network != null
            then {
              node = nodeName;
              interface = ifName;
              network = iface.network;
              addresses = iface.addresses or [];
            }
            else null
        ) (node.interfaces or {})
    )
    nodes
  );

  filteredEntries = lib.filter (x: x != null) interfaceEntries;

  groupKey = x: "${x.node}__${x.network}";

  grouped =
    lib.foldl' (
      acc: x: let
        key = groupKey x;
        prev =
          acc.${
            key
          }
          or {
            node = x.node;
            network = x.network;
            interfaces = [];
            addresses = [];
          };
      in
        acc
        // {
          ${key} =
            prev
            // {
              interfaces = prev.interfaces ++ [x.interface];
              addresses = prev.addresses ++ x.addresses;
            };
        }
    ) {}
    filteredEntries;

  edgeGroups = builtins.attrValues grouped;

  hostIds = lib.unique (map (x: x.node) edgeGroups);

  hostStmt = n: let
    info = nodes.${n}.hardware.info or "";
    label =
      if info != ""
      then "${nodes.${n}.name}\\n${info}"
      else nodes.${n}.name;
  in ''
    "host:${n}" [
      label="${escape label}"
      shape=box
      style="rounded,filled"
      fillcolor="#111827"
      color="#475569"
      penwidth=1.4
      fontcolor="#e5e7eb"
      fontsize=13
      margin="0.16,0.1"
    ];
  '';

  networkStmt = n: let
    net = networks.${n};
    cidr =
      if net.cidrv4 != null
      then "\\n${net.cidrv4}"
      else if net.cidrv6 != null
      then "\\n${net.cidrv6}"
      else "";
  in ''
    "net:${n}" [
      label="${escape (net.name + cidr)}"
      shape=ellipse
      style="filled"
      fillcolor="#0b1220"
      color="${net.style.primaryColor}"
      penwidth=2.2
      fontcolor="#f8fafc"
      fontsize=14
    ];
  '';

  edgeStmt = x: let
    ifaceLabel = lib.concatStringsSep ", " (lib.unique x.interfaces);
    addrList = lib.unique x.addresses;
    addrLabel =
      if addrList != []
      then "\\n${lib.concatStringsSep "\\n" addrList}"
      else "";
  in ''
    "host:${x.node}" -- "net:${x.network}" [
      label="${escape (ifaceLabel + addrLabel)}"
      color="${networks.${x.network}.style.primaryColor}"
      fontcolor="#cbd5e1"
      penwidth=2.0
      fontsize=11
    ];
  '';

  dot = ''
    graph network_topology {
      bgcolor="#030712";
      pad=0.35;
      rankdir=LR;
      overlap=false;
      splines=true;
      outputorder=edgesfirst;
      nodesep=0.85;
      ranksep=1.1;
      fontname="JetBrains Mono";
      label="Network Attachment Topology";
      labelloc=t;
      fontsize=22;
      fontcolor="#f8fafc";

      node [fontname="JetBrains Mono"];
      edge [fontname="JetBrains Mono"];

      subgraph cluster_hosts {
        label="Hosts";
        color="#1f2937";
        style="rounded";
        penwidth=1.3;
        ${lib.concatLines (map hostStmt hostIds)}
      }

      subgraph cluster_networks {
        label="Networks";
        color="#1f2937";
        style="rounded";
        penwidth=1.3;
        ${lib.concatLines (map networkStmt networkIds)}
      }

      ${lib.concatLines (map edgeStmt edgeGroups)}
    }
  '';
in
  pkgs.runCommand "topology-network" {nativeBuildInputs = [pkgs.graphviz];} ''
        mkdir -p "$out"
        cat > "$out/network.dot" <<'EOF'
    ${dot}
    EOF
        dot -Tsvg "$out/network.dot" > "$out/network.svg"
  ''
