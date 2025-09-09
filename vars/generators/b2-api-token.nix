{
  "b2-service" = {
    share = true;
    files = {
      application_key_id = {
        mode = "0400";
        neededFor = "users";
      };
      application_key = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      application_key_id = {
        description = "B2 Application Key ID";
        persist = true;
        type = "hidden";
      };
      application_key = {
        description = "B2 Application Key Secret";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/application_key_id" "$out/application_key_id"
      cp "$prompts/application_key" "$out/application_key"
    '';
    meta = {
      tags = ["b2" "backups"];
    };
  };
}
