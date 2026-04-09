{
  "wifi-psk" = {
    share = false;
    files = {
      psk = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      psk = {
        description = "WiFi pre-shared key for g\xe5rdestorp networks";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      touch "$out/psk"
      cat >> "hello" "$out/psk"
    '';
    meta = {
      tags = ["wifi" "ariel"];
    };
  };
}
