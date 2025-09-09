{
  "api-key-aws-access" = {
    share = true;
    files = {
      aws_access_key_id = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      aws_access_key_id = {
        description = "AWS access key ID";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/aws_access_key_id" "$out/aws_access_key_id"
    '';
    meta = {
      tags = ["aws" "api-key" "dev" "fish"];
    };
  };
}
