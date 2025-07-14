{
  lib,
  config,
}: ({
  name,
  type,
  fileName ? "password",
  multiline ? false,
  ...
}: let
  mainUser = config.my.mainUser.name;
  promptType =
    if multiline
    then "multiline-hidden"
    else "hidden";
  perms = {
    root = {
      owner = "root";
      mode = "0400";
    };
    user = {
      owner = mainUser;
      mode = "0400";
    };
    shared = {
      owner = "root";
      group = "secret-readers";
      mode = "0440";
    };
  };
in {
  "${name}" = {
    share = type == "shared";
    prompts.input = {
      description = "${name} (${fileName})";
      type = promptType;
      persist = false;
    };
    script = "cp $prompts/input $out/${fileName}";
    files."${fileName}" = {secret = true;} // perms.${type};
  };
})
