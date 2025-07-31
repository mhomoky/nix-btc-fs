{
  config,
  lib,
  pkgs,
  ...
}: {
  services.ente = {
    enable = true;
    settings = {
      httpPort = 3000;
      dbPath = "/var/lib/ente/db";
    };
  };

  networking.firewall.allowedTCPPorts = [3000 80 443];
}
