{
  "api-key-aws-secret" = {
    share = true;
    files = {
      aws_secret_access_key = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      aws_secret_access_key = {
        description = "AWS secret access key";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      cp "$prompts/aws_secret_access_key" "$out/aws_secret_access_key"
    '';
    meta = {
      tags = ["aws" "api-key" "dev" "fish"];
    };
  };
}
