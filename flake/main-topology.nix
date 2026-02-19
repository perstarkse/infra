{
  pkgs,
  lib,
  nodes,
}: let
  escape = s:
    lib.replaceStrings ["\"" "\n"] ["\\\"" "\\n"] (toString s);

  nodeIds = builtins.attrNames nodes;

  coreNodes = lib.filter (n: builtins.elem n ["internet" "io" "switch-main"]) nodeIds;
  otherNodes = lib.filter (n: !(builtins.elem n coreNodes)) nodeIds;

  allConnections = lib.flatten (
    lib.mapAttrsToList (
      srcNode: node:
        lib.flatten (
          lib.mapAttrsToList (
            srcIf: iface:
              map (conn: {
                inherit srcNode srcIf;
                dstNode = conn.node;
                dstIf = conn.interface;
              }) (iface.physicalConnections or [])
          ) (node.interfaces or {})
        )
    )
    nodes
  );

  connectionKey = c: let
    a = "${c.srcNode}:${c.srcIf}";
    b = "${c.dstNode}:${c.dstIf}";
  in
    if a < b
    then "${a}__${b}"
    else "${b}__${a}";

  uniqueConnections = builtins.attrValues (lib.foldl' (acc: c: acc // {${connectionKey c} = c;}) {} allConnections);

  nodeColor = n: let
    t = nodes.${n}.deviceType or "nixos";
  in
    {
      internet = "#1d4ed8";
      router = "#d97706";
      switch = "#0e7490";
      nixos = "#6d28d9";
    }
      .${
      t
    } or "#334155";

  nodeLabel = n: let
    node = nodes.${n};
    info = node.hardware.info or "";
  in
    if info != ""
    then "${node.name}\\n${info}"
    else node.name;

  nodeStmt = n: ''
    "${n}" [
      label="${escape (nodeLabel n)}"
      shape=box
      style="rounded,filled"
      fillcolor="#111827"
      color="${nodeColor n}"
      penwidth=1.8
      fontcolor="#e5e7eb"
      fontsize=14
      margin="0.18,0.12"
    ];
  '';

  edgeStmt = c: let
    showLabel = c.srcIf != "*" && c.dstIf != "*";
    label =
      if showLabel
      then "${c.srcIf} <-> ${c.dstIf}"
      else "";
  in ''
    "${c.srcNode}" -- "${c.dstNode}" [
      color="#f1cf8a"
      penwidth=2.1
      ${lib.optionalString showLabel ''label="${escape label}"''}
      ${lib.optionalString showLabel ''fontcolor="#cbd5e1"''}
      ${lib.optionalString showLabel ''fontsize=11''}
    ];
  '';

  dot = ''
    graph main_topology {
      bgcolor="#030712";
      pad=0.35;
      rankdir=LR;
      splines=polyline;
      overlap=false;
      outputorder=edgesfirst;
      nodesep=0.8;
      ranksep=1.0;
      fontname="JetBrains Mono";
      label="Machine Interconnect Topology";
      labelloc=t;
      fontsize=22;
      fontcolor="#f8fafc";

      node [fontname="JetBrains Mono"];
      edge [fontname="JetBrains Mono"];

      subgraph cluster_core {
        label="Core";
        color="#1f2937";
        style="rounded";
        penwidth=1.3;
        ${lib.concatLines (map nodeStmt coreNodes)}
      }

      subgraph cluster_hosts {
        label="Endpoints";
        color="#1f2937";
        style="rounded";
        penwidth=1.3;
        ${lib.concatLines (map nodeStmt otherNodes)}
      }

      ${lib.concatLines (map edgeStmt uniqueConnections)}
    }
  '';
in
  pkgs.runCommand "topology-main" {nativeBuildInputs = [pkgs.graphviz];} ''
        mkdir -p "$out"
        cat > "$out/main.dot" <<'EOF'
    ${dot}
    EOF
        dot -Tsvg "$out/main.dot" > "$out/main.svg"
  ''
