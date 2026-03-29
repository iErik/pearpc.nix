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
  # GCC 13+ rejects passing packed FPR slots by non-const reference in cpu_jitc_x86_64 (ppc_fpu.cc).
  useGenericCpu =
    stdenv.hostPlatform.isx86_64 || stdenv.hostPlatform.parsed.cpu.name == "i686";

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

  patches = [ ./patches/generic-ppc-fatal.patch ];

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

      On x86/x86_64 hosts this build uses the portable generic CPU core by default
      because current GCC rejects the x86 JIT sources; aarch64 still uses the
      AArch64 JIT when supported by upstream. A small patch adds the missing
      generic `ppc_fatal` symbol that upstream only ships in the AArch64 JIT tree.

      Override Nix arguments `cpu` and `ui` to pass PearPC’s `--enable-cpu` and
      `--enable-ui` configure flags (e.g. `jitc_aarch64`, `x11`). Forcing
      `jitc_x86` / `jitc_x86_64` on x86/x86_64 may fail to compile with current
      GCC. The GTK UI is not supported in this flake (upstream gtk makefiles
      assume FHS paths and the final link does not resolve reliably under Nix).
    '';
    homepage = "https://github.com/sebastianbiallas/pearpc";
    license = lib.licenses.gpl2Only;
    maintainers = [ ];
    mainProgram = "ppc";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
