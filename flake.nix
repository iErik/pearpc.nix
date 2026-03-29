{
  description = "PearPC, Basilisk II, SheepShaver — emulators (flake packages + PearPC NixOS module)";

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

      pearpcNixosModule = import ./nixos/pearpc.nix {
        inherit self;
        lib = nixpkgs.lib;
        pearpcNix = ./pearpc.nix;
      };
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
          macemuSrc = pkgs.callPackage ./macemu-src.nix { };
        in
        {
          pearpc = pkgs.callPackage ./pearpc.nix { };
          basilisk2 = pkgs.callPackage ./basilisk2.nix { src = macemuSrc; };
          sheepshaver = pkgs.callPackage ./sheepshaver.nix { src = macemuSrc; };
          default = self.packages.${system}.pearpc;
        }
      );
    };
}
