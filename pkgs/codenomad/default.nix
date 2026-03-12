{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage rec {
  pname = "codenomad";
  version = "0.12.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@neuralnomads/codenomad/-/codenomad-${version}.tgz";
    hash = "sha512-L9f7YAXTiS7YUpUvLBGBtJcvy0nwjSKPeaGsMPmjdZl8bksFMuYtVZJ57Z18m3JGqhYXcB8H2WL2FR3jXuXZSw==";
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace package.json \
      --replace-fail '"dependencies": {' $'"dependencies": {\n    "@opencode-ai/plugin": "1.2.4",'
  '';

  npmDepsHash = "sha256-szB6lYnJXu4l88q2E122IooHW/6vzmR6uRLzS/00+6M=";
  dontNpmBuild = true;

  meta = {
    description = "CodeNomad multi-instance OpenCode workspace server";
    homepage = "https://github.com/NeuralNomadsAI/CodeNomad";
    license = lib.licenses.mit;
    mainProgram = "codenomad";
    platforms = lib.platforms.linux;
  };
}
