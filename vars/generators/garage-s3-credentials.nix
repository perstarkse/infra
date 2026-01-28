{
  "garage-s3" = {
    share = true;
    files = {
      access_key_id = {
        mode = "0400";
        neededFor = "users";
      };
      secret_access_key = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      access_key_id = {
        description = "Garage S3 Access Key ID (from 'garage key create')";
        persist = true;
        type = "hidden";
      };
      secret_access_key = {
        description = "Garage S3 Secret Access Key";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/access_key_id" "$out/access_key_id"
      cp "$prompts/secret_access_key" "$out/secret_access_key"
    '';
    meta = {
      tags = ["garage-s3"];
    };
  };
}
