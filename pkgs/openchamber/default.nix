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
  version = "1.11.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@openchamber/web/-/web-${version}.tgz";
    hash = "sha256-f9onT25hs6XU+hgK/yE93XFwR40jl2uZBxvHD7lVAQk=";
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-IUMpHUYKqeK6bDxW3ZFeUm5Q4TBfgzdQhL1wbk6kZsc=";

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
