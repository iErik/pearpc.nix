{
  lib,
  stdenv,
  fetchFromGitHub,
  autoconf,
  automake,
  pkg-config,
  flex,
  bison,
  sdl3,
  libX11,
  libXext,
  cpu ? null,
  ui ? null,
}:

let
  # GCC 13+ rejects passing packed GPR/FPR slots by non-const reference in cpu_jitc_x86_64 (patched).
  useGenericCpu =
    stdenv.hostPlatform.isx86_64 || stdenv.hostPlatform.parsed.cpu.name == "i686";

  # The x86/x86_64 JIT emits CALL/JMP rel32 instructions. Those require the
  # JIT translation cache and the binary's .text to be within ±2 GB of each
  # other. The mmap-hint patch (jitc-x86-64-mmap-hint.patch) fixes this at the
  # source level by placing the JIT cache near the binary's .text regardless of
  # PIE. hardeningDisable = ["pie"] is kept as belt-and-suspenders for non-PIE
  # builds (PIE disabled → binary at ~0x400000, always within 2 GB of cache).
  useJitcX86 = cpu != null && lib.hasPrefix "jitc_x86" cpu;

  effectiveUi = if ui == null then "sdl" else ui;

  cpuConfigureFlags =
    if cpu != null then
      [ "--enable-cpu=${cpu}" ]
    else
      lib.optional useGenericCpu "--enable-cpu=generic";
in

assert lib.assertMsg (effectiveUi != "gtk") "pearpc: ui = \"gtk\" is not supported in this flake (see meta.longDescription).";

stdenv.mkDerivation {
  pname = "pearpc";
  version = "0.6pre-unstable-2026-03-22";

  src = fetchFromGitHub {
    owner = "sebastianbiallas";
    repo = "pearpc";
    rev = "dab38803f9a783a13385c211f5a415606bced849";
    hash = "sha256-TOU4cSEvaxuHYalobp7ClFhogDELEX0XKHFXQvt2+Jo=";
  };

  strictDeps = true;

  # See useJitcX86 comment above.
  hardeningDisable = lib.optionals useJitcX86 [ "pie" ];

  patches = [
    ./patches/generic-ppc-fatal.patch
    # GCC 13+: cannot bind packed `fpr[]` / `gpr[]` to non-const references.
    ./patches/jitc-x86-64-packed-fpr.patch
    ./patches/jitc-x86-64-packed-mmu.patch
    # Place the JIT translation cache near the binary .text so CALL/JMP rel32
    # instructions reach helper functions regardless of PIE. Applies to all
    # builds; the fix is #ifdef-gated to x86/x86_64 at compile time.
    ./patches/jitc-x86-64-mmap-hint.patch
    # IO code calls ppc_fatal; upstream only defines it in generic / AArch64 CPU trees.
    ./patches/jitc-x86-64-ppc-fatal.patch
  ];

  nativeBuildInputs = [
    autoconf
    automake
    pkg-config
    flex
    bison
  ];

  buildInputs =
    lib.optionals (effectiveUi == "sdl") [ sdl3 ]
    ++ lib.optionals (effectiveUi == "x11") [
      libX11
      libXext
    ];

  postPatch = ''
    substituteInPlace src/debug/debugparse.y \
      --replace-fail '%token <scalar> EVAL_INT' '%code provides {
int yylex(YYSTYPE *yylval);
}

%token <scalar> EVAL_INT'
    substituteInPlace src/debug/lex.h \
      --replace-fail 'int yylex();' ""
  '';

  preConfigure = "./autogen.sh";

  configureFlags = [
    "--enable-ui=${effectiveUi}"
  ] ++ cpuConfigureFlags;

  installPhase = ''
    runHook preInstall
    install -Dm755 src/ppc "$out/bin/ppc"
    ln -s ppc "$out/bin/pearpc"
    install -Dm644 ppccfg.example "$out/share/doc/pearpc/ppccfg.example"
    runHook postInstall
  '';

  meta = {
    description = "PowerPC architecture emulator";
    longDescription = ''
      PearPC emulates PowerPC systems and can run many PowerPC operating systems.
      Networking features may require TUN/TAP support on the host at runtime.

      On x86/x86_64 hosts this build uses the portable generic CPU core by default.
      Patches supply `ppc_fatal` for the generic CPU tree and for `jitc_x86_64`
      (upstream only defines it alongside the AArch64 JIT). Other patches fix
      x86_64 JIT code so current GCC accepts packed GPR/FPR slots (no binding
      to non-const references). aarch64 still uses the AArch64 JIT when supported
      by upstream.

      Override Nix arguments `cpu` and `ui` to pass PearPC’s `--enable-cpu` and
      `--enable-ui` configure flags (e.g. `jitc_aarch64`, `jitc_x86_64`, `x11`).
      `jitc_x86` (32-bit JIT) is untested here and may still break on modern GCC.
      The GTK UI is not supported in this flake (upstream gtk makefiles
      assume FHS paths and the final link does not resolve reliably under Nix).
    '';
    homepage = "https://github.com/sebastianbiallas/pearpc";
    license = lib.licenses.gpl2Only;
    maintainers = [ ];
    mainProgram = "ppc";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
