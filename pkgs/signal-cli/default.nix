# signal-cli 0.14.8, built from the upstream release tarball.
#
# Why not nixpkgs' signal-cli: nixos-26.05 ships 0.14.2, and device linking
# fails on it with
#
#   INFO ProvisioningManagerImpl - Received link information from +46…, linking in progress ...
#   Link request error: StatusCode: 409
#
# which is the long-standing MissingCapabilitiesException-on-link bug
# (AsamK/signal-cli#1556, #1709, #1386; bbernhard/signal-cli-rest-api#457,
# #591). Every one of those threads was resolved by moving to a newer
# signal-cli, and those versions are all *older* than 0.14.8 — so the fix is
# very likely in one of the six patch releases nixpkgs is behind. Packaging the
# release directly is the cheapest way to find out; fold this back into nixpkgs
# once 26.05 or unstable carries a version that links.
#
# The upstream `bin/signal-cli` is a shell script that assembles a ~70-jar
# classpath at runtime with xargs/sed. We replace it with a direct makeWrapper
# invocation, same shape as nixpkgs' own signal-cli.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  # 0.14.8's classes are class-file version 69 (Java 25); nixpkgs' default
  # `jdk` is 21 and refuses to load them.
  jdk25_headless,
  version ? "0.14.8",
  url ? "https://github.com/AsamK/signal-cli/releases/download/v${version}/signal-cli-${version}.tar.gz",
  # Default so `pkgs.callPackage ../../pkgs/signal-cli { }` works; override it to
  # re-point the package at another release.
  sha256 ? "sha256-zNQI6DHv9+Qeuq8wlwSEC7ANeKeGnzWtcA265bWlu2U=",
}:
stdenvNoCC.mkDerivation {
  pname = "signal-cli";
  inherit version;

  src = fetchurl {
    inherit url sha256;
  };

  nativeBuildInputs = [makeWrapper];

  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/share/man
    cp -r lib/. $out/lib/
    cp -r man/. $out/share/man/

    # Upstream's launcher builds a ~70-jar classpath at runtime; expand it here
    # instead and hand java a concrete list. A literal glob inside the wrapper
    # is wrong: it is expanded when the wrapper is written, so java receives an
    # already-expanded argv and the next flag becomes the main class.
    classpath=$(printf '%s:' $out/lib/*.jar)
    makeWrapper ${jdk25_headless}/bin/java $out/bin/signal-cli \
      --add-flags "-classpath ''${classpath%:}" \
      --add-flags org.asamk.signal.Main

    runHook postInstall
  '';

  meta = {
    description = "Command-line and dbus interface for the Signal messaging service";
    homepage = "https://github.com/AsamK/signal-cli";
    license = lib.licenses.agpl3Plus;
    mainProgram = "signal-cli";
    platforms = lib.platforms.unix;
  };
}
