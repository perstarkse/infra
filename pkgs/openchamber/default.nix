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
  gawk,
  findutils,
  python3,
}:
buildNpmPackage rec {
  pname = "openchamber";
  version = "1.8.5";

  src = fetchurl {
    url = "https://registry.npmjs.org/@openchamber/web/-/web-${version}.tgz";
    hash = "sha512-GTg8DYMPbGz8Y8eNa+h3EZxxm6gji+SGtCbVi0JpGxFW5zV/6Wo51XNfjb9era0hheI+Nbj535wOnoZigOCP4g==";
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-Shhoh9cVmnbDDbOHmbK4QcJCx7AMUDTwtsFPOmmb9FQ=";
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
