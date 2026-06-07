{
  lib,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  nodejs,
  nodePackages,
  git,
  openssh,
  opencode,
  cloudflared,
  bun,
  bashInteractive,
  coreutils,
  gnugrep,
  ripgrep,
  gnutar,
  gawk,
  findutils,
  python3,
}:
buildNpmPackage rec {
  pname = "openchamber";
  version = "1.12.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/@openchamber/web/-/web-${version}.tgz";
    hash = "sha256-LNdD3ud4i7iGDPzuubIy61m6bkiPlXSdh4p+0ugIi+A=";
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-Ms7zJ5rPWntO0MAmpZicu0Q7oNvoUDfgfX6QaaRazkI=";

  dontNpmBuild = true;

  nativeBuildInputs = [
    makeWrapper
    python3
  ];

  postInstall = ''
    wrapProgram $out/bin/openchamber \
      --prefix PATH : ${lib.makeBinPath [
      nodejs
      nodePackages.pnpm
      git
      openssh
      opencode
      cloudflared
      bun
      bashInteractive
      coreutils
      gnugrep
      ripgrep
      gnutar
      gawk
      findutils
    ]}
  '';

  meta = {
    description = "Desktop and web interface for the OpenCode AI agent";
    homepage = "https://github.com/openchamber/openchamber";
    license = lib.licenses.mit;
    mainProgram = "openchamber";
    platforms = lib.platforms.linux;
  };
}
