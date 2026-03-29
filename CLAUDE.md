# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Nix flake providing three classic Mac/PowerPC emulator packages and a NixOS module:

- **`pearpc`** — PowerPC architecture emulator (runs Mac OS X on x86/x86_64/aarch64)
- **`basilisk2`** — 68k Macintosh emulator (runs classic 68k Mac OS)
- **`sheepshaver`** — PowerPC Mac OS run-time environment (runs Mac OS 7.5.2–9.0.4)
- **`nixosModules.pearpc`** — NixOS module at `programs.pearpc.*`

Supported systems: `x86_64-linux`, `aarch64-linux`.

## Common commands

```bash
# Build a package
nix build .#pearpc
nix build .#basilisk2
nix build .#sheepshaver

# Enter a dev shell for a package (uses nixpkgs stdenv)
nix develop .#pearpc

# Check the flake
nix flake check

# Update flake inputs
nix flake update

# Update flake lock without changing inputs
nix flake lock
```

## Architecture

### Source layout

| File | Purpose |
|---|---|
| `flake.nix` | Entry point: declares inputs, iterates `systems`, wires packages and NixOS module |
| `pearpc.nix` | `stdenv.mkDerivation` for PearPC (autotools + SDL3) |
| `macemu-src.nix` | Single `fetchFromGitHub` for the shared macemu repo (used by both Basilisk II and SheepShaver) |
| `basilisk2.nix` | Derivation for Basilisk II; `sourceRoot = "BasiliskII/src/Unix"` |
| `sheepshaver.nix` | Derivation for SheepShaver; `sourceRoot = "SheepShaver/src/Unix"` |
| `nixos/pearpc.nix` | NixOS module — curried `{ self, lib }: { config, pkgs, ... }:` pattern |
| `patches/` | Local patches applied in `postPatch` |

### Key design decisions

- **Shared macemu source**: `macemu-src.nix` fetches the upstream `cebix/macemu` repo once; both `basilisk2.nix` and `sheepshaver.nix` receive it as the `src` argument from `flake.nix`.
- **Generic CPU on x86**: PearPC's x86 JIT sources fail to compile with GCC 13+ (packed FPR reference issue). `pearpc.nix` detects `isx86_64 || i686` and passes `--enable-cpu=generic`. The `patches/generic-ppc-fatal.patch` adds `ppc_fatal()` to the generic CPU backend, which upstream only defines in the AArch64 JIT tree.
- **NixOS module currying**: `nixos/pearpc.nix` is a function `{ self, lib } -> NixOS module`. It is partially applied in `flake.nix` with `import ./nixos/pearpc.nix { inherit self; lib = nixpkgs.lib; }`. The module uses `self` to resolve the default package for the current host platform.
- **TUN networking**: The NixOS module's `programs.pearpc.networking.enableTunAccess` option loads the `tun` kernel module, creates a `pearpc-net` group, and installs a udev rule — allowing non-root PearPC networking.
