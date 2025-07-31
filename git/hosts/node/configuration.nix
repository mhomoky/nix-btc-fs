{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    (import ./hardware.nix)
    ../../modules/tailscale-oauth.nix
  ];

  # Networking & users
  networking.hostName = "node";
  networking.useDHCP = false;
  networking.interfaces.eno1.useDHCP = true;
  users.users.root.openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJxbuUFahg5/QCUq56bqfpJeW/hof9RAzgw0XmEOON4F"];

  # SOPS
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.defaultSopsFile = ./secrets/secrets.yaml;

  # Tailscale
  services.tailscale-oauth = {
    enable = true;
    clientIdPath = config.sops.secrets."tailscale/oauth_client_id".path;
    clientSecretPath = config.sops.secrets."tailscale/oauth_client_secret".path;
  };

  sops.secrets = {
    "tailscale/oauth_client_id" = {};
    "tailscale/oauth_client_secret" = {};
  };

  # systemd.services.tailscale-init = {
  #   wantedBy = ["multi-user.target"];
  #   serviceConfig.Type = "oneshot";
  #   script = ''
  #     tailscale up --authkey=$(sops -d --extract '["tailscale"]["authkey"]' ${./secrets/secrets.yaml})
  #   '';
  # };

  # Tor-only for Bitcoin traffic
  services.tor.enable = true;
  services.tor.client.enable = true;

  # Time
  services.timesyncd.enable = true;

  # Nix settings
  nix.settings.experimental-features = ["nix-command" "flakes"];
  system.stateVersion = "25.05";
}
