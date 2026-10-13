# The shared MCP server surface (agent MCP parity), one function for every pi
# profile in the fleet. Called per profile with that profile's digikey OAuth
# token store — token files must never be shared between principals (the
# refresh flow rotates them; a shared store races).
#
# Machine configs call it as:
#   ctx.flake.lib.mkPiMcpServers {
#     inherit config pkgs;
#     inputs = ctx.inputs;
#     tokenStore = "/home/agent/.local/state/digikey-mcp/tokens.json";
#   }
{
  config,
  pkgs,
  inputs,
  tokenStore,
}: {
  accounted = {
    url = "https://accounting.lan.stark.pub/api/extensions/ext/mcp-server/mcp?client=pi-code";
    # pi's built-in MCP support has no `bearerToken` field: the
    # Authorization header is a `!command` value, and that command must
    # be the WHOLE value (pi runs it through a shell and takes trimmed
    # stdout), so the Bearer prefix comes from the command itself.
    headers.Authorization = "!cat ${config.my.secrets.getPath "accounted-mcp-key" "env"} | grep '^ACCOUNTED_MCP_API_KEY=' | cut -d= -f2 | sed 's/^/Bearer /'";
  };
  context7 = {
    url = "https://mcp.context7.com/mcp";
    headers = {
      CONTEXT7_API_KEY = "!cat ${config.my.secrets.getPath "context7" "env"} | grep '^CONTEXT7_API_KEY=' | cut -d= -f2";
    };
  };
  # Onshape FeatureScript MCP (hosted, streamable HTTP). Auth is OAuth,
  # not an Onshape API key: the account authorises in a browser via
  # `pi mcp login onshape`, and pi stores the token in
  # ~/.pi/agent/mcp-auth.json, so no secret belongs in this flake.
  onshape = {
    url = "https://fs-mcp.labs.onshape.app/mcp";
    description = "Onshape FeatureScript: write, run and refine custom Onshape features in a document.";
  };
  digikey = {
    # MyLists tools need the app subscribed to MyLists in the portal and its
    # OAuth Callback URL set to DIGIKEY_CALLBACK_URL below; the account owner
    # then runs the one-time mylists_authorize consent flow (per principal —
    # separate consent, separate token store).
    command = "${inputs.digikeyMcp.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/digikey-mcp";
    env = {
      DIGIKEY_CLIENT_ID = "!cat ${config.my.secrets.getPath "digikey" "env"} | grep '^DIGIKEY_CLIENT_ID=' | cut -d= -f2";
      DIGIKEY_CLIENT_SECRET = "!cat ${config.my.secrets.getPath "digikey" "env"} | grep '^DIGIKEY_CLIENT_SECRET=' | cut -d= -f2";
      DIGIKEY_CALLBACK_URL = "https://localhost:8139/digikey_callback";
      DIGIKEY_TOKEN_STORE = tokenStore;
    };
  };
  # agentcad: stdio MCP server exposing the CAD CLI as typed tools
  # (venv interpreter from the shared agent-tooling package).
  agentcad = {
    command = "${inputs.agentTooling.packages.${pkgs.stdenv.hostPlatform.system}.agentcad}/bin/python";
    args = ["-m" "agentcad.mcp"];
    # Host workaround: OCP's GL renderer aborts the process with an
    # X error on a live display it cannot use (BadWindow kills the
    # auto-diff PNG phase — agentcad 0.4.0 has no --no-diff). An
    # unreachable DISPLAY fails the GL phase gracefully instead.
    # See printing/desktop-side-box/spec.md → CAD tooling.
    env = {
      DISPLAY = "invalid-display";
    };
  };
}
