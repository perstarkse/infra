# Shared herdr socket sharing. Extracted to flake/lib because two units needed
# it and a second copy drifts the same way the ntfy fan-out did.
#
# PENDING: roadmap Phase C moved makemake's herdr server off the system module
# (modules/system/herdr.nix) and onto the Home Manager user unit, so
# modules/home/herdr.nix is now the only consumer. Once that system module is
# retired, this lib should be inlined back into the home module rather than
# kept as a one-consumer indirection.
#
# Why an ACL at all: herdr chmods both sockets 0600 and exposes no knob for it
# (upstream src/server/socket_paths.rs), so the only way to let another local
# user drive the server is to widen the socket after the bind. herdr refuses to
# share the server process itself, which is correct — panes are spawned by the
# server, so moving the server would move every pane's identity.
#
# The wait keys on connectability, not on "-S" or inode identity. herdr leaves
# the previous run's socket files behind, so an existence test passes against a
# dead file, and an inode comparison never settles when the helper starts after
# herdr has already rebound. A unix socket whose server has gone returns
# ECONNREFUSED immediately, so connect() is the only signal that is true in
# either ordering, and a fast one.
#
# LIMIT: no path unit, so a socket replaced without a service restart would keep
# its old ACL. Add a path unit or watcher if herdr ever rebinds in place; a
# service restart is the only thing that re-runs ExecStartPost.
{pkgs}: {
  shareScript = pkgs.writeShellScript "herdr-share-sockets" ''
    set -uo pipefail
    api="$1"
    client="$2"
    shift 2
    python=${pkgs.python3}/bin/python3
    for _ in $(seq 1 60); do
      if [ -S "$client" ] &&
        "$python" -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.settimeout(0.5); s.connect(sys.argv[1])' "$api" 2>/dev/null; then
        break
      fi
      sleep 0.5
    done
    if [ ! -S "$api" ]; then
      echo "herdr: $api never appeared; socket not shared with: $*" >&2
      exit 0
    fi
    for path in "$api" "$client"; do
      [ -S "$path" ] || continue
      for user in "$@"; do
        ${pkgs.acl}/bin/setfacl -m "u:$user:rw" "$path" \
          || echo "herdr: setfacl failed for $user on $path" >&2
      done
    done
    echo "herdr: sockets shared with: $*"
  '';
}
