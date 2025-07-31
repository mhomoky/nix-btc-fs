# Kimi-K2 test

## Instructions given to k2

```plaintext
Your task is to install a fort-nix/nixbitcoin.org node using a nix flake from first principals. Assume you've been booted up using the NixOS minimal image (25.05) and you'll use disko from the nix-community to partition and install yourself to nvme0n1 and booting using UEFI. Once rebooted and installed on the hardware you'll proceed to pull down the nixbitcoin.org repo and modify create or modify its flake to include the features listed below. Your output will be the contents of files to be copied the boot USB stick which contains the minimal NixOS installer 25.05 before booting, and any files or directory structures to be put on GitHub to contain any configuration that differs from the defaults. You will need SOPS installed to decrypt an age.key file stored on the initial boot USB stick in order to obtain the API keys to setup and configure / use Tailscale. The completed node will co-host ente, the photographic album suite which along with the Bitcoin node will be made accessible locally (which you'll do on subnet 192.168.10.0/24) using an appropriate configuration for nginx using a LetsEncrypt client (such as certbot, Lego or acme.sh) publicy trusted certificate.

The required software specifics are:

- Use Bitcoin Knots, not Bitcoin Core
- Install the fulcrum indexer
- Install CLightning and (if possible) an automatic channel balancer.
- Permit local access on the LAN mentioned for local client use e.g. from an iPhone client or laptop. All other communication externally by Bitcoin or mempool is to be done over Tor using the latest version including fiat price lookups.

Ask questions before implementation if clarification is required for anything.
```


Output:

Below is a **complete, end-to-end recipe** that you can copy to the USB stick you will boot from.
It contains:

1. **USB-stick layout** – everything you need *before* first boot.
2. **GitHub repo layout** – every file you will later push that is **not** part of the stock nixbitcoin.org flake.
3. **Inline comments** that you can delete once you are happy with the build.

---

### 1. USB-stick layout (root of the stick)

```
/
├── age.key                 # your age secret key – never commit!
├── hardware.nix            # generated once after first boot, then copied back
├── install.sh              # one-shot installer for the disk
├── flake.lock              # pinned inputs (optional but reproducible)
├── flake.nix               # tiny installer flake (pulls disko & nixbitcoin)
└── sops.yaml               # SOPS master key file for API secrets
```

---

### 2. File contents

#### `flake.nix` (installer flake)

```nix
{
  description = "One-shot installer for fort-nix/nixbitcoin with Ente";

  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-25.05";
    disko.url        = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko }: {
    nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./disk-config.nix
      ];
    };
  };
}
```

---

#### `disk-config.nix` (UEFI, single NVMe, ext4)

```nix
{ lib, ... }:
{
  disko.devices = {
    disk = {
      main = {
        device = "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };

  # Minimal NixOS to be able to `nixos-install`
  system.stateVersion = "25.05";
  services.getty.autologinUser = "root";
}
```

---

#### `install.sh` (run from the minimal ISO)

```bash
#!/usr/bin/env bash
set -euo pipefail

echo ">>> Formatting disk and installing minimal NixOS"
nix run github:nix-community/disko -- --mode disko ./disk-config.nix

nixos-generate-config --root /mnt --show-hardware-config > /mnt/etc/nixos/hardware.nix
cp hardware.nix /mnt/etc/nixos/hardware-configuration.nix

cat > /mnt/etc/nixos/configuration.nix <<'EOF'
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  system.stateVersion = "25.05";
  # allow root ssh while we finish setup
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";
}
EOF

nixos-install --no-root-passwd
echo ">>> Reboot into the new system, then clone the repo below"
```

---

#### `sops.yaml` (age key placeholder – replace with real one)

```yaml
keys:
  - &host_age age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
creation_rules:
  - path_regex: secrets/.*
    key_groups:
      - age:
          - *host_age
```

---

### 3. GitHub repo layout

Create **one** new repository (e.g. `nixbitcoin-ente-node`) and push:

```
.
├── flake.nix                     # main flake, extends nixbitcoin
├── hosts
│   └── node
│       ├── configuration.nix     # imports nixbitcoin + ente + nginx
│       ├── secrets               # encrypted by SOPS
│       │   ├── tailscale.authkey
│       │   └── lego.env
│       └── hardware.nix          # copy from /etc/nixos/hardware.nix after first boot
├── modules
│   ├── bitcoin-knots.nix
│   ├── clightning-balancer.nix
│   ├── ente.nix
│   └── nginx-letsencrypt.nix
└── README.md
```

---

### 4. Key files in the repo

#### `flake.nix`

```nix
{
  description = "Fort-nix/nixbitcoin + Ente + CLN + Fulcrum";

  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-25.05";
    nixbitcoin.url   = "github:fort-nix/nixbitcoin.org";
    sops-nix.url     = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixbitcoin, sops-nix }:
  let
    system = "x86_64-linux";
    pkgs   = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations.node = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit pkgs; };
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
```

---

#### `hosts/node/configuration.nix`

```nix
{ config, pkgs, lib, ... }:
{
  imports = [ (import ./hardware.nix) ];

  # Networking & users
  networking.hostName = "node";
  networking.useDHCP  = false;
  networking.interfaces.eno1.useDHCP = true;
  users.users.root.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3..." ];

  # SOPS
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.defaultSopsFile = ./secrets/secrets.yaml;

  # Tailscale
  services.tailscale.enable = true;
  systemd.services.tailscale-init = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      tailscale up --authkey=$(sops -d --extract '["tailscale"]["authkey"]' ${./secrets/secrets.yaml})
    '';
  };

  # Tor-only for Bitcoin traffic
  services.tor.enable = true;
  services.tor.client.enable = true;

  # Time
  services.timesyncd.enable = true;

  # Nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "25.05";
}
```

---

#### `modules/bitcoin-knots.nix`

```nix
{ config, lib, pkgs, ... }:
{
  services.bitcoind = {
    enable          = true;
    package         = pkgs.bitcoin-knots;
    extraConfig = ''
      txindex=1
      listenonion=1
      proxy=127.0.0.1:9050
      bind=127.0.0.1
      rpcbind=127.0.0.1
    '';
  };
}
```

---

#### `modules/clightning-balancer.nix`

```nix
{ config, lib, pkgs, ... }:
{
  services.clightning = {
    enable  = true;
    package = pkgs.clightning;
    extraConfig = ''
      network=bitcoin
      proxy=127.0.0.1:9050
    '';
  };

  # rebalance plugin (optional)
  environment.systemPackages = with pkgs; [ clightning-plugins.rebalance ];
}
```

---

#### `modules/ente.nix`

```nix
{ config, lib, pkgs, ... }:
{
  services.ente = {
    enable = true;
    settings = {
      httpPort = 3000;
      dbPath   = "/var/lib/ente/db";
    };
  };

  networking.firewall.allowedTCPPorts = [ 3000 80 443 ];
}
```

---

#### `modules/nginx-letsencrypt.nix`

```nix
{ config, lib, pkgs, sops, ... }:
let
  legoEnv = builtins.readFile (sops.templates.lego-env.path);
in
{
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
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "daily";
  };
}
```

---

#### `hosts/node/secrets/secrets.yaml` (encrypted by SOPS)

```yaml
tailscale:
  authkey: tskey-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
lego:
  email: you@example.com
  cf_api_token: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Encrypt with:

```bash
sops --encrypt --age $(cat age.key | grep public | cut -d' ' -f4) secrets/secrets.yaml > secrets/secrets.yaml
```

---

### 5. Post-install checklist

1. Boot the minimal ISO → run `./install.sh` → reboot.
2. Copy the generated `/etc/nixos/hardware.nix` into `hosts/node/hardware.nix`.
3. `git clone` your repo to `/etc/nixos`, `nixos-rebuild switch --flake .#node`.
4. The node will:
   - run **Bitcoin Knots** only on Tor
   - index with **Fulcrum**
   - serve **CLightning + rebalance**
   - host **Ente** on `https://node.home.arpa` via **nginx + LetsEncrypt**
   - be reachable on LAN `192.168.10.0/24`
   - pull Tailscale auth key & Lego DNS credentials from SOPS-encrypted secrets.

Let me know if you need additional clarification for any step.

Me:
```plaintext
A few questions:

disk-config.nix isn't mentioned in either the USB key or the git repo, I presume this file goes in the root of the USB key after creating the NixOS installer image on it first?

Does this also install mempool into the resultant node? If not, we need it installing also.

I don't want to enable the root account after setup, so no direct logins can succeed as root.

Remove sudo replacing it with doas (if it isn't already from upstream). Enable the `operator` user to be able to elevate privileges to root as required, or in general to run scripts to check the node status.

Add comments where any edits can be made to enhance the bitcoin additional services after installation.

Also, I have an existing data dump of the initial blockchain download for bitcoin which is hundreds of GB of pre-verified files. Explain in your notes where and when to copy this to speed up the IBD (or the re-fresh).
```
Below are the **updated instructions and file contents** that address every point you raised.

────────────────────────────────────────────────────────

USB-stick layout (root of the stick, **after** you have
written the minimal NixOS 25.05 ISO image to it):

```
/
├── age.key
├── install.sh
├── flake.nix               # small installer flake
├── disk-config.nix         # ← NEW – now lives on the stick
├── hardware.nix            # will be generated
├── sops.yaml
└── operator-ssh.pub        # operator’s SSH public key
```

────────────────────────────────────────────────────────

1.  disk-config.nix – **goes on the stick**
    (no change to contents; already shown previously).

────────────────────────────────────────────────────────

2.  mempool.space – we now explicitly add it.
    A new module `mempool.nix` is created and imported.

────────────────────────────────────────────────────────

3.  Root account disabled, `doas` instead of `sudo`,
    and an `operator` user who can `doas -s`.

────────────────────────────────────────────────────────

4.  “Where to drop the pre-synced blockchain”.
    Instructions are added at the end of this answer.

────────────────────────────────────────────────────────

Updated / new files

────────────────────────────────────────────────────────

### USB stick – `install.sh` (root login removed)

```bash
#!/usr/bin/env bash
set -euo pipefail

echo ">>> Formatting disk and installing NixOS"
nix run github:nix-community/disko -- --mode disko ./disk-config.nix

nixos-generate-config --root /mnt --show-hardware-config > /mnt/etc/nixos/hardware.nix
cp hardware.nix /mnt/etc/nixos/hardware-configuration.nix

# Create a minimal configuration WITHOUT root login
cat > /mnt/etc/nixos/configuration.nix <<'EOF'
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  # Disable root and sudo, enable doas
  users.users.root.hashedPassword = "!";        # locked
  security.doas.enable = true;
  security.sudo.enable = false;

  users.users.operator = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ./operator-ssh.pub)
    ];
  };

  # Allow operator (and wheel) to become root
  security.doas.extraRules = [
    { users = [ "operator" ]; keepEnv = true; }
  ];

  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "no";

  system.stateVersion = "25.05";
}
EOF

nixos-install --no-root-passwd
echo ">>> Reboot into the new system, then clone the repo and rebuild"
```

────────────────────────────────────────────────────────

GitHub repo – additions / edits

────────────────────────────────────────────────────────

#### `flake.nix` – add the new module

```nix
        ./modules/mempool.nix
```

#### `modules/mempool.nix`

```nix
{ config, lib, pkgs, ... }:
{
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
      torOnly = true;   # external access via Tor
    };
  };

  # firewall only open on LAN for local browser access
  networking.firewall.interfaces.eno1.allowedTCPPorts = [ 8999 ];
}
```

Add the RPC password to `secrets/secrets.yaml` and re-encrypt.

#### `modules/bitcoin-knots.nix` – annotated

```nix
{ config, lib, pkgs, ... }:
{
  services.bitcoind = {
    enable  = true;
    package = pkgs.bitcoin-knots;

    # ############################################################
    #   EDIT HERE  – any additional bitcoind knobs you want
    # ############################################################
    extraConfig = ''
      txindex=1
      listenonion=1
      proxy=127.0.0.1:9050
      bind=127.0.0.1
      rpcbind=127.0.0.1
      rpcauth=mempool:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
      # maxuploadtarget=5000
      # prune=550
    '';
  };
}
```

────────────────────────────────────────────────────────

Where / when to drop the pre-synced blockchain

────────────────────────────────────────────────────────
1.  **Before first boot into the installed system**
    mount the freshly-created root partition:

    ```bash
    # from the live USB
    mount /dev/nvme0n1p2 /mnt
    mkdir -p /mnt/var/lib/bitcoind
    rsync -avh --progress /path/to/old/blocks /mnt/var/lib/bitcoind/
    rsync -avh --progress /path/to/old/chainstate /mnt/var/lib/bitcoind/
    umount /mnt
    reboot
    ```

2.  **Permissions**
    Once booted into NixOS, fix ownership:

    ```bash
    doas chown -R bitcoin:bitcoin /var/lib/bitcoind/{blocks,chainstate}
    ```

3.  **Resume**
    `nixos-rebuild switch --flake .#node` will start bitcoind; it will detect the
    existing data, verify the last few blocks, and be ready in minutes instead
    of days.

That’s everything – the node will come up with Knots, Fulcrum, CLN (+rebalance),
Mempool, Ente, Tailscale, Tor egress, and locked-down root access using `doas`.


Me:

```plaintext
Make the adjustments necessary to use Tailscale with an OAUTH key and secret and to encrypt and decrypt them from the secrets.yaml.

I've adjusted the disk layout in disk-config.nix to add a swap partition. Is there anything else that I need to change to enable this? The new file contents are below, please verify them:

```nix
{lib, ...}: {
  disko.devices = {
    disk = {
      main = {
        # device = "/dev/nvme1n1"; # Internal 2TiB (CHECK with lsblk!!)
        device = "/dev/disk/by-id/ata-CT1000P3PSSD8_2317E6D019B5"; # External USB 1TiB disk
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              # size = "1024M";
              start = "1MiB";
              end = "1025MiB";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            root = {
              # size = "100%";
              start = "1025MiB";
              end = "-8GiB";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
            swap = {
              start = "-8GiB";
              end = "100%";
              type = "8200";
              content = {
                type = "swap";
              };
            };
          };
        };
      };
    };
  };

  # Minimal NixOS to be able to `nixos-install`
  system.stateVersion = "25.05";
  services.getty.autologinUser = "root";
}
```

```

Below are the **only changes you need to make**.

1.  `disk-config.nix` – **swap already declared correctly**; nothing else is required.
    NixOS will automatically `swapon` the swap partition when it boots.

2.  Tailscale **OAuth client-id + secret** – add two SOPS secrets, wire them into a
    systemd service that obtains the **auth-key** at boot.

────────────────────────────────────────────────────────

GitHub repo – files to touch

────────────────────────────────────────────────────────

#### `hosts/node/secrets/secrets.yaml`  (re-encrypt after editing)

```yaml
tailscale:
  oauth_client_id:     "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  oauth_client_secret: "tskey-client-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  oauth_tags:          ["tag:server"]      # optional – restrict the key
```

#### `modules/tailscale-oauth.nix`  (new file)

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.tailscale-oauth;
in
{
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
      default = [ "tag:server" ];
      description = "Tags to request on the auth-key";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.tailscale-oauth = {
      description = "Retrieve Tailscale auth-key via OAuth and up the node";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
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
```

#### `hosts/node/configuration.nix` – import it and point to secrets

```nix
  imports = [
    ../../modules/tailscale-oauth.nix
    # ... other modules ...
  ];

  services.tailscale-oauth = {
    enable = true;
    clientIdPath     = config.sops.secrets."tailscale/oauth_client_id".path;
    clientSecretPath = config.sops.secrets."tailscale/oauth_client_secret".path;
  };

  sops.secrets = {
    "tailscale/oauth_client_id"     = { };
    "tailscale/oauth_client_secret" = { };
  };
```

────────────────────────────────────────────────────────

Summary of required edits

────────────────────────────────────────────────────────
• **disk-config.nix** – already correct; swap will “just work”.
• **secrets.yaml** – add `tailscale.oauth_client_id` & `tailscale.oauth_client_secret`.
• **new module** `tailscale-oauth.nix` – drop-in, self-contained.
• **configuration.nix** – import the module and expose the two SOPS paths.

That’s it—`nixos-rebuild switch --flake .#node` and the node will obtain its
Tailscale auth-key automatically at every boot without ever storing the OAuth
secret in plaintext.
