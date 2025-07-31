{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.tailscale-oauth;
in {
  options.services.tailscale-oauth = {
    enable = lib.mkEnableOption "Tailscale OAuth auth-key generator";
    clientIdPath = lib.mkOption {
      type = lib.types.path;
      description = "SOPS secret file containing OAuth client-id";
    };
    clientSecretPath = lib.mkOption {
      type = lib.types.path;
      description = "SOPS secret file containing OAuth client-secret";
    };
    tags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["tag:nix"];
      description = "Tags to request on the auth-key";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.tailscale-oauth = {
      description = "Retrieve Tailscale auth-key via OAuth and up the node";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = [
          "TS_CLIENT_ID_FILE=${cfg.clientIdPath}"
          "TS_CLIENT_SECRET_FILE=${cfg.clientSecretPath}"
          "TS_TAGS=${lib.concatStringsSep "," cfg.tags}"
        ];
        ExecStart = "${pkgs.writeShellScript "tailscale-oauth-up" ''
          set -euo pipefail
          client_id=$(cat "$TS_CLIENT_ID_FILE")
          client_secret=$(cat "$TS_CLIENT_SECRET_FILE")

          # one-shot auth-key (valid 1h – long enough to join the tailnet)
          auth_key=$(curl -s -u "$client_id:$client_secret" \
            "https://api.tailscale.com/api/v2/oauth/token" \
            -d "client_id=$client_id" \
            -d "client_secret=$client_secret" \
            -d "grant_type=client_credentials" \
            -d "scope=authkey" \
            -d "tags=$TS_TAGS" \
            | jq -r '.access_token')

          # bring the node up
          tailscale up --authkey="$auth_key"
        ''}";
      };
    };
  };
}
