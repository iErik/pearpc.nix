{
  description = "PearPC — PowerPC emulator (flake package + NixOS module for TUN-friendly networking)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      pearpcNixosModule = import ./nixos/pearpc.nix { inherit self; lib = nixpkgs.lib; };
    in
    {
      nixosModules = {
        pearpc = pearpcNixosModule;
        default = pearpcNixosModule;
      };

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          pearpc = pkgs.callPackage ./pearpc.nix { };
          default = self.packages.${system}.pearpc;
        }
      );
    };
}
