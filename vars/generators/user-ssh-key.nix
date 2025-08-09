{
  "user-ssh-key" = {
    files = {
      key = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      key = {
        description = "Content of the user ssh key file";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/key" "$out/key"
    '';
    meta = {
    tags = [ "user" "user-ssh" ];
    };
  };
} 