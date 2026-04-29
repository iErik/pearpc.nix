{
  lib,
  stdenv,
  fetchFromGitHub,
  autoconf,
  automake,
  pkg-config,
  flex,
  bison,
  python3,
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
  # other. postPatch rewrites sys_alloc_read_write_execute to hint mmap() near
  # the binary's .text, fixing this for both PIE and non-PIE builds.
  # hardeningDisable = ["pie"] is kept as belt-and-suspenders for non-PIE
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
  hardeningDisable = lib.optionals useJitcX86 [ "pic" ];

  patches = [
    ./patches/generic-ppc-fatal.patch
    # GCC 13+: cannot bind packed `fpr[]` / `gpr[]` to non-const references.
    ./patches/jitc-x86-64-packed-fpr.patch
    ./patches/jitc-x86-64-packed-mmu.patch
    # IO code calls ppc_fatal; upstream only defines it in generic / AArch64 CPU trees.
    ./patches/jitc-x86-64-ppc-fatal.patch
  ];

  nativeBuildInputs = [
    autoconf
    automake
    pkg-config
    flex
    bison
    python3
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

    # Rewrite sys_alloc_read_write_execute in sysvm.cc to allocate the JIT
    # translation cache near the binary .text section.  The x86/x86_64 JIT
    # emits CALL/JMP rel32 instructions that require source and target to be
    # within ±2 GB.  MAP_32BIT only satisfies this for non-PIE binaries;
    # using a hint derived from a .text address works for both PIE and non-PIE.
    python3 - <<'EOF'
import sys
f = 'src/system/osapi/posix/sysvm.cc'
src = open(f).read()

old = (
    '#include <sys/mman.h>\n'
    '#include <sys/types.h>\n'
)
new = (
    '#include <sys/mman.h>\n'
    '#include <stdint.h>\n'
    '#include <sys/types.h>\n'
)
assert old in src, 'sysvm.cc: include block not found'
src = src.replace(old, new, 1)

old = """\
void *sys_alloc_read_write_execute(size_t size)
{
\tint flags = MAP_ANON | MAP_PRIVATE;
#if defined(__aarch64__) && defined(__APPLE__)
\tflags |= MAP_JIT;
#else
\tflags |= MAP_32BIT;
#endif
\tvoid *p = mmap(0, size, PROT_READ | PROT_WRITE | PROT_EXEC, flags, -1, 0);

\treturn (p == (void *)-1) ? NULL : p;
}"""

new = """\
void *sys_alloc_read_write_execute(size_t size)
{
\tint flags = MAP_ANON | MAP_PRIVATE;
\tvoid *p;
#if defined(__aarch64__) && defined(__APPLE__)
\tflags |= MAP_JIT;
\tp = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC, flags, -1, 0);
#elif defined(__x86_64__) || defined(__i386__)
\t/* The x86 JIT emits CALL/JMP rel32: source and target must be within
\t * +-2 GB.  Hint mmap() to just below this function (in .text) so the
\t * cache lands near all helper functions regardless of PIE.  Fall back
\t * to MAP_32BIT (works for non-PIE) if the hint is too close to 0 or
\t * the kernel maps outside the window. */
\tp = MAP_FAILED;
\t{
\t\tuintptr_t anchor = (uintptr_t)(void *)sys_alloc_read_write_execute;
\t\tif (anchor >= (uintptr_t)size) {
\t\t\tvoid *hint = (void *)(anchor - (uintptr_t)size);
\t\t\tp = mmap(hint, size, PROT_READ | PROT_WRITE | PROT_EXEC, flags, -1, 0);
\t\t\tif (p != MAP_FAILED) {
\t\t\t\tintptr_t off = (intptr_t)((uintptr_t)p - anchor);
\t\t\t\tif (off < -(intptr_t)0x70000000 || off > (intptr_t)0x70000000) {
\t\t\t\t\tmunmap(p, size);
\t\t\t\t\tp = MAP_FAILED;
\t\t\t\t}
\t\t\t}
\t\t}
\t}
\tif (p == MAP_FAILED)
\t\tp = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
\t\t         flags | MAP_32BIT, -1, 0);
#else
\tp = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
\t         flags | MAP_32BIT, -1, 0);
#endif
\treturn (p == MAP_FAILED) ? NULL : p;
}"""

assert old in src, 'sysvm.cc: function body not found'
src = src.replace(old, new, 1)
open(f, 'w').write(src)
EOF
  '';

  preConfigure =
    # Disable PIE: the x86/x86_64 JIT emits CALL/JMP rel32, which truncates
    # the displacement to 32 bits.  A PIE binary lands at ~0x5555... (~94 TB),
    # while MAP_32BIT places the JIT cache in the first 2 GB.  The ~94 TB gap
    # overflows int32 → wrong jump target → SIGSEGV.  hardeningDisable=["pie"]
    # is also set, but export LDFLAGS here ensures PIE is off even when this
    # derivation is wrapped in overrideAttrs (NixOS module compilerOptimizeForHostCpu).
    lib.optionalString useJitcX86 ''
      export LDFLAGS="$LDFLAGS -no-pie"
      export CFLAGS="$CFLAGS -fno-pie"
      export CXXFLAGS="$CXXFLAGS -fno-pie"
    ''
    + "./autogen.sh";

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
