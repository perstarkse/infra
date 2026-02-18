{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage rec {
  pname = "codenomad";
  version = "0.11.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@neuralnomads/codenomad/-/codenomad-${version}.tgz";
    hash = "sha512-OUV1HWpl5z60O2KK1YTz6Dv9Nr+sZ1zvPfVrEZfyglx9PGQJJS4Cxpg3N1xwmrOV+x6VYJaU4WSYxz3Bkv5jtw==";
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace package.json \
      --replace-fail '"dependencies": {' $'"dependencies": {\n    "@opencode-ai/plugin": "1.2.4",'
  '';

  npmDepsHash = "sha256-KsPePf9/xLTk3z33d8kqaOPqHk8w7DUezfdtWcw4928=";
  dontNpmBuild = true;

  meta = {
    description = "CodeNomad multi-instance OpenCode workspace server";
    homepage = "https://github.com/NeuralNomadsAI/CodeNomad";
    license = lib.licenses.mit;
    mainProgram = "codenomad";
    platforms = lib.platforms.linux;
  };
}
