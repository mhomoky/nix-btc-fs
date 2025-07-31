{
  config,
  lib,
  pkgs,
  ...
}: {
  services.mempool = {
    enable = true;
    backend = {
      network = "mainnet";
      bitcoin.active = true;
      bitcoin.host = "127.0.0.1";
      bitcoin.port = 8332;
      bitcoin.user = "mempool";
      bitcoin.passFile = config.sops.secrets."mempool/bitcoind-rpcpass".path;
    };
    frontend = {
      basePath = "/mempool";
      torOnly = true; # external access via Tor
    };
  };

  # firewall only open on LAN for local browser access
  networking.firewall.interfaces.eno1.allowedTCPPorts = [8999];
}
