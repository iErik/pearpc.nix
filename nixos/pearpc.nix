# NixOS module: install PearPC and optionally configure TUN for emulated networking.
# See https://github.com/sebastianbiallas/pearpc — networking uses the host TUN device.

{ self, lib, pearpcNix }:

{ config, pkgs, ... }:

let
  cfg = config.programs.pearpc;

  system = pkgs.stdenv.hostPlatform.system;

  flakePearpc = self.packages.${system}.pearpc or null;

  pearpcBase =
    if cfg.package != null then
      cfg.package
    else if cfg.cpu != null || cfg.ui != null then
      pkgs.callPackage pearpcNix {
        inherit (cfg) cpu ui;
      }
    else if flakePearpc != null then
      flakePearpc
    else
      throw "programs.pearpc: set `package`, or ensure this flake provides `packages.${system}.pearpc`.";

  pearpcPkg =
    if cfg.package != null then
      cfg.package
    else if cfg.compilerOptimizeForHostCpu then
      pearpcBase.overrideAttrs (old: {
        NIX_CFLAGS_COMPILE = (old.NIX_CFLAGS_COMPILE or "") + " -O3 -march=native";
        NIX_CXXFLAGS_COMPILE = (old.NIX_CXXFLAGS_COMPILE or "") + " -O3 -march=native";
      })
    else
      pearpcBase;

  linuxTun = cfg.networking.enableTunAccess && pkgs.stdenv.hostPlatform.isLinux;

  pearpcCpuEnum = [
    "generic"
    "jitc_x86"
    "jitc_x86_64"
    "jitc_aarch64"
  ];

  pearpcUiEnum = [
    "sdl"
    "x11"
  ];
in

{
  options.programs.pearpc = {
    enable = lib.mkEnableOption "PearPC, a PowerPC architecture emulator (`ppc` / `pearpc` in PATH)";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        PearPC package to install. When `null`, the module uses this flake’s
        `packages.<system>.pearpc`, or builds from this flake’s `pearpc.nix` when
        `cpu` or `ui` is set.

        When non-`null`, you must leave `cpu`, `ui`, and
        `compilerOptimizeForHostCpu` at their defaults — those options only apply
        when this module supplies the package.
      '';
    };

    cpu = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum pearpcCpuEnum);
      default = null;
      example = "jitc_aarch64";
      description = ''
        PearPC `--enable-cpu` value (`generic`, `jitc_x86`, `jitc_x86_64`,
        `jitc_aarch64`). When `null`, the package uses the flake default (on
        x86/x86_64 that is `generic` unless you set e.g. `jitc_x86_64` (the flake
        patches generic `ppc_fatal` and x86_64 JIT FPU code for current GCC).

        Only used when `package` is `null`.
      '';
    };

    ui = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum pearpcUiEnum);
      default = null;
      example = "x11";
      description = ''
        PearPC `--enable-ui` value (`sdl` or `x11`). When `null`, the build
        defaults to SDL (same as the flake package). GTK is not supported in this
        flake.

        Only used when `package` is `null`.
      '';
    };

    compilerOptimizeForHostCpu = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Append `-O3 -march=native` to the C/C++ compiler flags for PearPC.
        This can improve runtime performance on the machine that builds the
        package, but the output is **not reproducible** across CPUs and will not
        match substitutes built without these flags.

        Only applied when `package` is `null` (the module may use the flake
        package or a local `pearpc.nix` build).
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
            || cfg.package == null
            || (
              cfg.cpu == null && cfg.ui == null && !cfg.compilerOptimizeForHostCpu
            );
          message = ''
            programs.pearpc.package is set: unset programs.pearpc.cpu, programs.pearpc.ui, and
            programs.pearpc.compilerOptimizeForHostCpu (or set `package` to null) so the module
            does not ignore those options.
          '';
        }
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
        ) "programs.pearpc.networking.enableTunAccess only applies on Linux; ignored on this host."
        ++ lib.optional (
          cfg.enable
          && cfg.package == null
          && cfg.cpu == "jitc_x86"
          && pkgs.stdenv.hostPlatform.isx86_64
        ) "programs.pearpc.cpu=jitc_x86: the 32-bit x86 JIT is untested here and may fail to build with current GCC; consider `generic` or `jitc_x86_64`.";
    }
  ];
}
