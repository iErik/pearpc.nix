# NixOS module: install PearPC and optionally configure TUN for emulated networking.
# See https://github.com/sebastianbiallas/pearpc — networking uses the host TUN device.

{ self, lib }:

{ config, pkgs, ... }:

let
  cfg = config.programs.pearpc;

  defaultPackage =
    self.packages.${pkgs.stdenv.hostPlatform.system}.pearpc or null;

  pearpcPkg =
    if cfg.package != null then
      cfg.package
    else if defaultPackage != null then
      defaultPackage
    else
      throw "programs.pearpc: set `package` — this flake has no `packages.${pkgs.stdenv.hostPlatform.system}.pearpc`.";

  linuxTun = cfg.networking.enableTunAccess && pkgs.stdenv.hostPlatform.isLinux;
in

{
  options.programs.pearpc = {
    enable = lib.mkEnableOption "PearPC, a PowerPC architecture emulator (`ppc` / `pearpc` in PATH)";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        PearPC package to install. When `null`, uses this flake's
        `packages.<system>.pearpc` for the NixOS host platform.
      '';
    };

    networking = {
      enableTunAccess = lib.mkEnableOption ''
        Linux: load the `tun` kernel module and set a udev rule so members of
        the `pearpc-net` group can open `/dev/net/tun` (needed for PearPC's
        emulated NIC without running as root). Either list accounts under
        `programs.pearpc.networking.tunUsers`, or add
        `users.users.<name>.extraGroups = [ "pearpc-net" ];` yourself, then
        re-login or run `newgrp pearpc-net`.
      '';

      tunUsers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "alice" ];
        description = ''
          User names that receive the `pearpc-net` group for TUN access.
          Only has effect when `programs.pearpc.networking.enableTunAccess`
          is true.
        '';
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ pearpcPkg ];
    })

    (lib.mkIf (cfg.enable && linuxTun) {
      boot.kernelModules = [ "tun" ];

      users.groups.pearpc-net = { };

      environment.etc."udev/rules.d/70-pearpc-tun.rules".text = ''
        # PearPC emulated NIC: allow group pearpc-net to use /dev/net/tun
        KERNEL=="tun", GROUP="pearpc-net", MODE="0660"
      '';
    })

    (lib.mkIf (cfg.enable && linuxTun && cfg.networking.tunUsers != [ ]) {
      users.users = lib.mkMerge (
        map (u: {
          ${u} = {
            extraGroups = [ "pearpc-net" ];
          };
        }) cfg.networking.tunUsers
      );
    })

    {
      assertions = [
        {
          assertion =
            !cfg.enable
            || !linuxTun
            || cfg.networking.tunUsers == [ ]
            || lib.all (u: (builtins.hasAttr u config.users.users) && (
              let
                account = config.users.users.${u};
              in
              (account.isNormalUser or false) || (account.isSystemUser or false)
            )) cfg.networking.tunUsers;
          message = ''
            programs.pearpc.networking.tunUsers must list existing user accounts that have either
            users.users.<name>.isNormalUser or isSystemUser set elsewhere in your configuration.
          '';
        }
      ];

      warnings =
        lib.optional (
          cfg.enable && cfg.networking.enableTunAccess && !pkgs.stdenv.hostPlatform.isLinux
        ) "programs.pearpc.networking.enableTunAccess only applies on Linux; ignored on this host.";
    }
  ];
}
