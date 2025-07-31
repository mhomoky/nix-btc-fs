{
  config,
  lib,
  pkgs,
  ...
}: {
  services.clightning = {
    enable = true;
    package = pkgs.clightning;
    extraConfig = ''
      network=bitcoin
      proxy=127.0.0.1:9050
    '';
  };

  # rebalance plugin (optional)
  environment.systemPackages = with pkgs; [clightning-plugins.rebalance];
}
