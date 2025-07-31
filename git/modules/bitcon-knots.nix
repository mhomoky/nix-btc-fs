{
  config,
  lib,
  pkgs,
  ...
}: {
  services.bitcoind = {
    enable = true;
    package = pkgs.bitcoin-knots;

    # ############################################################
    #   EDIT HERE  – any additional bitcoind knobs you want
    # ############################################################
    rpcauth = [
      "mempool:${config.sops.secrets."mempool/bitcoind_rpcpass".path}"
    ];

    extraConfig = ''
      txindex=1
      listenonion=1
      proxy=127.0.0.1:9050
      bind=127.0.0.1
      rpcbind=127.0.0.1
      # maxuploadtarget=5000
      # prune=550
    '';
  };

  sops.secrets."mempool/bitcoind_rpcpass" = {};
}
