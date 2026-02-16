{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage rec {
  pname = "codenomad";
  version = "0.10.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/@neuralnomads/codenomad/-/codenomad-${version}.tgz";
    hash = "sha512-1lKmaufZuaXctVem5vObHQeIjvgXJ1BM3+PgSe6RQ+TbjZJmuufFQAEv3HdYyE+wZ2F0eREcUcbHcjvz6sWJHg==";
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-xoZvMUcyB3gl6in7RT6l4EXC53TOOt/qJ5dHW9NJuJk=";
  dontNpmBuild = true;

  meta = {
    description = "CodeNomad multi-instance OpenCode workspace server";
    homepage = "https://github.com/NeuralNomadsAI/CodeNomad";
    license = lib.licenses.mit;
    mainProgram = "codenomad";
    platforms = lib.platforms.linux;
  };
}
