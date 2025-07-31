{
  description = "Fort-nix/nixbitcoin + Ente + CLN + Fulcrum";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixbitcoin.url = "github:fort-nix/nixbitcoin.org";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    nixbitcoin,
    sops-nix,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations.node = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit pkgs;};
      modules = [
        ./hosts/node/configuration.nix
        ./hosts/node/hardware.nix
        sops-nix.nixosModules.sops
        ./modules/bitcoin-knots.nix
        ./modules/clightning-balancer.nix
        ./modules/ente.nix
        ./modules/nginx-letsencrypt.nix
        nixbitcoin.nixosModules.default
      ];
    };
  };
}
