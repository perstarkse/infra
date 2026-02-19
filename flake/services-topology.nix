{
  pkgs,
  lib,
  nodes,
}: let
  sanitizeChars = [
    " "
    "."
    "-"
    ":"
    "/"
    "'"
    "\""
    "("
    ")"
    "["
    "]"
    "{"
    "}"
    ","
    "+"
    "#"
    "@"
  ];

  sanitize = s: lib.replaceStrings sanitizeChars (map (_: "_") sanitizeChars) s;

  escape = s:
    lib.replaceStrings ["\"" "\n"] ["\\\"" "\\n"] (toString s);

  splitNonEmptyLines = s:
    lib.filter (x: x != "") (lib.splitString "\n" (toString s));

  parseEndpointToken = token: let
    isHttp = lib.hasPrefix "http://" token;
    isHttps = lib.hasPrefix "https://" token;
    hasScheme = isHttp || isHttps;
    stripped =
      if isHttp
      then lib.removePrefix "http://" token
      else if isHttps
      then lib.removePrefix "https://" token
      else token;
    hostPortPart = builtins.head (lib.splitString "/" stripped);
    hostPortMatch = builtins.match "^([0-9A-Za-z._-]+):([0-9]+)$" hostPortPart;
    hostOnlyMatch = builtins.match "^([0-9A-Za-z._-]+)$" hostPortPart;
  in
    if hostPortMatch != null
    then {
      host = builtins.elemAt hostPortMatch 0;
      port = builtins.elemAt hostPortMatch 1;
    }
    else if hasScheme && hostOnlyMatch != null
    then {
      host = builtins.elemAt hostOnlyMatch 0;
      port =
        if isHttps
        then "443"
        else "80";
    }
    else null;

  parseEndpointCandidates = text:
    lib.filter (x: x != null) (map parseEndpointToken (splitNonEmptyLines text));

  mkHostId = host: "host_" + sanitize host;
  mkServiceId = host: service: "svc_" + sanitize host + "_" + sanitize service.id;
  mkDetailId = host: service: detail:
    "det_" + sanitize host + "_" + sanitize service.id + "_" + sanitize detail.name;
  mkRouteId = route: "route_" + sanitize route.domain;

  hostNames = lib.sort (a: b: a < b) (builtins.attrNames nodes);

  stripCidr = address: builtins.head (lib.splitString "/" address);

  hostAddressCandidates = host: let
    ifaceAddresses = lib.flatten (
      lib.mapAttrsToList (_: iface: map stripCidr (iface.addresses or [])) (nodes.${host}.interfaces or {})
    );
  in
    lib.unique ([host "${host}.lan"] ++ ifaceAddresses);

  visibleServicesFor = host:
    lib.filter (service: !(service.hidden or false)) (lib.attrValues (nodes.${host}.services or {}));

  isIoNginx = host: service: host == "io" && service.id == "nginx";

  serviceEndpointCandidates = lib.flatten (
    map (
      host:
        lib.flatten (
          map (
            service: let
              candidateTexts =
                (lib.optional ((service.info or "") != "") service.info)
                ++ map (detail: detail.text) (lib.attrValues (service.details or {}));
              parsed = lib.flatten (map parseEndpointCandidates candidateTexts);
            in
              lib.flatten (
                map (
                  endpoint: let
                    endpointHosts =
                      if builtins.elem endpoint.host ["0.0.0.0" "::" "127.0.0.1" "localhost"]
                      then hostAddressCandidates host
                      else [endpoint.host];
                  in
                    map (endpointHost: {
                      inherit host;
                      serviceId = mkServiceId host service;
                      serviceName = service.name;
                      hostPort = "${endpointHost}:${endpoint.port}";
                    })
                    endpointHosts
                )
                parsed
              )
          ) (lib.filter (s: !(isIoNginx host s)) (visibleServicesFor host))
        )
    )
    hostNames
  );

  findServiceByHostPort = hostPort: let
    matches = lib.filter (x: x.hostPort == hostPort) serviceEndpointCandidates;
  in
    if matches == []
    then null
    else builtins.head matches;

  ioNginxService =
    if nodes ? io && (nodes.io.services or {}) ? nginx
    then nodes.io.services.nginx
    else null;

  ioNginxServiceId =
    if ioNginxService == null
    then null
    else mkServiceId "io" ioNginxService;

  ingressRoutes =
    if ioNginxService == null
    then []
    else
      map (
        detail: let
          parsed = parseEndpointCandidates detail.text;
          endpoint =
            if parsed == []
            then null
            else builtins.head parsed;
          hostPort =
            if endpoint == null
            then null
            else "${endpoint.host}:${endpoint.port}";
          resolved =
            if hostPort == null
            then null
            else findServiceByHostPort hostPort;
        in {
          domain = detail.name;
          backendText = detail.text;
          backendHostPort = hostPort;
          resolvedService = resolved;
        }
      ) (lib.attrValues (ioNginxService.details or {}));

  backendHostToNode = let
    mappings =
      map (
        host: let
          addresses = lib.flatten (
            lib.mapAttrsToList (_: iface: map stripCidr (iface.addresses or [])) (nodes.${host}.interfaces or {})
          );
        in
          lib.listToAttrs (map (addr: {
              name = addr;
              value = host;
            })
            addresses)
      )
      hostNames;
  in
    lib.foldl' (acc: mapping: acc // mapping) {} mappings;

  nodeForBackendHost = backendHost:
    if nodes ? ${backendHost}
    then backendHost
    else backendHostToNode.${backendHost} or null;

  mkBackendNodeIdForRoute = route:
    if route.backendHostPort != null
    then "backend_" + sanitize route.backendHostPort
    else "backend_text_" + sanitize route.backendText;

  backendLabelForRoute = route:
    if route.backendHostPort == null
    then route.backendText
    else let
      toks = lib.splitString ":" route.backendHostPort;
      host = builtins.head toks;
      port =
        if lib.length toks > 1
        then builtins.elemAt toks 1
        else "?";
      ownerNode = nodeForBackendHost host;
      ownerLabel =
        if ownerNode == null
        then host
        else nodes.${ownerNode}.name;
    in "${ownerLabel}:${port}";

  resolvedIngressRoutes = lib.filter (route: route.resolvedService != null) ingressRoutes;
  unresolvedIngressRoutes = lib.filter (route: route.resolvedService == null) ingressRoutes;

  unresolvedBackends = builtins.attrValues (
    lib.foldl' (
      acc: route:
        acc
        // {
          ${mkBackendNodeIdForRoute route} = {
            nodeId = mkBackendNodeIdForRoute route;
            label = backendLabelForRoute route;
            inherit (route) backendText;
          };
        }
    ) {}
    unresolvedIngressRoutes
  );

  detailLabel = detail:
    if detail.text != ""
    then detail.name + "\\n" + detail.text
    else detail.name;

  serviceDisplayName = host: service:
    if isIoNginx host service
    then "NGINX ingress"
    else service.name;

  mkDetailNodes = host: service:
    if isIoNginx host service
    then ""
    else
      lib.concatLines (
        map (
          detail: let
            detailId = mkDetailId host service detail;
            serviceId = mkServiceId host service;
          in ''
            "${detailId}" [
              label="${escape (detailLabel detail)}"
              shape=note
              style="filled"
              fillcolor="#0b1220"
              color="#334155"
              fontcolor="#cbd5e1"
              fontsize=10
            ];
            "${serviceId}" -> "${detailId}" [
              color="#475569"
              style=dashed
              penwidth=1.2
            ];
          ''
        ) (
          lib.sort
          (
            a: b:
              if a.order != b.order
              then a.order < b.order
              else a.name < b.name
          )
          (lib.attrValues (service.details or {}))
        )
      );

  mkServiceNode = host: service: let
    serviceId = mkServiceId host service;
    serviceInfo = service.info or "";
    infoSuffix =
      if serviceInfo != "" && !(isIoNginx host service)
      then "\\n" + serviceInfo
      else "";
  in ''
    "${serviceId}" [
      label="${escape (serviceDisplayName host service + infoSuffix)}"
      shape=box
      style="rounded,filled"
      fillcolor="#111827"
      color="#4b5563"
      fontcolor="#e5e7eb"
    ];
    "${mkHostId host}" -> "${serviceId}" [
      color="#64748b"
      penwidth=1.4
    ];
    ${mkDetailNodes host service}
  '';

  mkHostCluster = host: let
    node = nodes.${host};
    services = visibleServicesFor host;
  in ''
    subgraph "cluster_${sanitize host}" {
      label="${escape node.name}";
      color="#243244";
      penwidth=1.2;
      style="rounded";

      "${mkHostId host}" [
        label="${escape node.name}"
        shape=box
        style="rounded,filled"
        fillcolor="#1f2937"
        color="#64748b"
        fontcolor="#f8fafc"
      ];

      ${lib.concatLines (map (service: mkServiceNode host service) services)}
    }
  '';

  mkIngressRouteNode = route: let
    routeId = mkRouteId route;
  in ''
    "${routeId}" [
      label="${escape route.domain}"
      shape=box
      style="rounded,filled"
      fillcolor="#0b1220"
      color="#0ea5e9"
      fontcolor="#e0f2fe"
      fontsize=11
    ];
  '';

  mkIngressToNginxEdge = route: let
    routeId = mkRouteId route;
  in
    if ioNginxServiceId == null
    then ""
    else ''
      "${routeId}" -> "${ioNginxServiceId}" [
        color="#38bdf8"
        penwidth=1.6
      ];
    '';

  mkResolvedRouteToServiceEdge = route: let
    routeId = mkRouteId route;
  in ''
    "${routeId}" -> "${route.resolvedService.serviceId}" [
      label="${escape route.backendText}"
      color="#f59e0b"
      fontcolor="#fcd34d"
      fontsize=10
      penwidth=1.6
    ];
  '';

  nginxResolvedServiceEdges =
    if ioNginxServiceId == null
    then ""
    else
      lib.concatLines (
        map (
          serviceId: ''
            "${ioNginxServiceId}" -> "${serviceId}" [
              color="#f59e0b"
              penwidth=1.8
            ];
          ''
        ) (lib.unique (map (route: route.resolvedService.serviceId) resolvedIngressRoutes))
      );

  mkUnresolvedBackendNode = backend: ''
    "${backend.nodeId}" [
      label="${escape backend.label}"
      shape=note
      style="filled"
      fillcolor="#111827"
      color="#6b7280"
      fontcolor="#d1d5db"
      fontsize=10
    ];
  '';

  nginxUnresolvedBackendEdges =
    if ioNginxServiceId == null
    then ""
    else
      lib.concatLines (
        map (
          backend: ''
            "${ioNginxServiceId}" -> "${backend.nodeId}" [
              color="#94a3b8"
              style=dashed
              penwidth=1.4
            ];
          ''
        )
        unresolvedBackends
      );

  mkUnresolvedRouteToBackendEdge = route: let
    routeId = mkRouteId route;
    backendNodeId = mkBackendNodeIdForRoute route;
  in ''
    "${routeId}" -> "${backendNodeId}" [
      color="#64748b"
      style=dotted
      penwidth=1.1
    ];
  '';

  hostsWithServices =
    lib.filter (host: visibleServicesFor host != []) hostNames;

  dot = ''
    digraph services {
      graph [
        rankdir=LR
        bgcolor="#030712"
        pad=0.25
        ranksep=1.0
        nodesep=0.4
        splines=true
        fontname="JetBrains Mono"
        label="Services Topology"
        labelloc=t
        fontsize=18
        fontcolor="#e5e7eb"
      ];

      node [fontname="JetBrains Mono" fontsize=12 margin="0.08,0.05"];
      edge [fontname="JetBrains Mono"];

      ${lib.concatLines (map mkHostCluster hostsWithServices)}

      subgraph cluster_ingress {
        label="Ingress routes";
        color="#1d4b6e";
        penwidth=1.2;
        style="rounded";
        ${lib.concatLines (map mkIngressRouteNode ingressRoutes)}
        ${lib.concatLines (map mkUnresolvedBackendNode unresolvedBackends)}
        ${lib.concatLines (map mkIngressToNginxEdge ingressRoutes)}
        ${lib.concatLines (map mkResolvedRouteToServiceEdge resolvedIngressRoutes)}
        ${lib.concatLines (map mkUnresolvedRouteToBackendEdge unresolvedIngressRoutes)}
      }

      ${nginxResolvedServiceEdges}
      ${nginxUnresolvedBackendEdges}
    }
  '';
in
  pkgs.runCommand "services-topology" {nativeBuildInputs = [pkgs.graphviz];} ''
        mkdir -p "$out"
        cat > "$out/services.dot" <<'EOF'
    ${dot}
    EOF
        dot -Tsvg "$out/services.dot" > "$out/services.svg"
  ''
