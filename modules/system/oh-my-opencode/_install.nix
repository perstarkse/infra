{lib}: let
  inherit (lib) concatStringsSep optionals escapeShellArg optionalString;
  inherit (builtins) hashString;
in {
  mkInstallArgs = installCfg:
    concatStringsSep " " (
      [
        "--no-tui"
        "--platform=opencode"
        "--claude=${installCfg.claude}"
        "--openai=${installCfg.openai}"
        "--gemini=${installCfg.gemini}"
        "--copilot=${installCfg.copilot}"
        "--opencode-zen=${installCfg.opencodeZen}"
        "--zai-coding-plan=${installCfg.zaiCodingPlan}"
        "--kimi-for-coding=${installCfg.kimiForCoding}"
        "--opencode-go=${installCfg.opencodeGo}"
        "--vercel-ai-gateway=${installCfg.vercelAiGateway}"
      ]
      ++ optionals installCfg.skipAuth ["--skip-auth"]
    );

  mkInstallFingerprint = {
    installArgs,
    omoPkg,
    extra ? "",
  }:
    hashString "sha256" "${installArgs}@${omoPkg}${optionalString (extra != "") "@${extra}"}";

  mkInstallIfChanged = {
    pkgs,
    stampPath,
    fingerprint,
    body,
    prefix ? "",
  }: ''
    _omo_stamp=${escapeShellArg stampPath}
    _omo_want=${escapeShellArg fingerprint}
    if [ ! -f "$_omo_stamp" ] || [ "$(${pkgs.coreutils}/bin/cat "$_omo_stamp")" != "$_omo_want" ]; then
      ${prefix}${body}
      ${prefix}${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$_omo_stamp")"
      ${prefix}${pkgs.coreutils}/bin/printf '%s' ${escapeShellArg fingerprint} > ${escapeShellArg stampPath}
    fi
  '';
}
