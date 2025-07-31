{
  config,
  lib,
  pkgs,
  sops,
  ...
}: let
  legoEnv = builtins.readFile (sops.templates.lego-env.path);
in {
  services.nginx = {
    enable = true;
    virtualHosts = {
      "node.home.arpa" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:3000";
        };
      };
    };
  };

  # Lego (ACME client)
  systemd.services.lego-renew = {
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = sops.templates.lego-env.path;
      ExecStart = "${pkgs.lego}/bin/lego --email=$EMAIL --domains=$DOMAIN --dns=cloudflare renew";
    };
  };
  systemd.timers.lego-renew = {
    wantedBy = ["timers.target"];
    timerConfig.OnCalendar = "daily";
  };
}
