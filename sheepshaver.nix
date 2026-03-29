{
  lib,
  stdenv,
  autoconf,
  automake,
  pkg-config,
  gtk2,
  SDL2,
  libX11,
  libXext,
  libXxf86dga,
  libXxf86vm,
  ncurses,
  readline,
  perl,
  file,
  src,
}:

stdenv.mkDerivation {
  pname = "sheepshaver";
  version = "unstable-2025-01-06";

  inherit src;

  sourceRoot = "source/SheepShaver/src/Unix";

  postUnpack = ''
    chmod -R u+w source
  '';

  postPatch = ''
    patchShebangs ../kpx_cpu
  '';

  strictDeps = true;

  nativeBuildInputs = [
    autoconf
    automake
    perl
    file
    pkg-config
  ];

  buildInputs = [
    gtk2
    SDL2
    libX11
    libXext
    libXxf86dga
    libXxf86vm
    ncurses
    readline
  ];

  preConfigure = ''
    ( cd ../../.. && make -C SheepShaver links )
    NO_CONFIGURE=1 ./autogen.sh
    substituteInPlace configure --replace-fail '/usr/bin/file' '${file}/bin/file'
  '';

  postConfigure = ''
    if ! grep -q '^#define STDC_HEADERS' config.h; then
      echo '#define STDC_HEADERS 1' >> config.h
    fi
  '';

  configureFlags = [
    "--enable-sdl-video"
    "--enable-sdl-audio"
    "--with-sdl2"
    "--with-esd=no"
    "--with-mon=no"
  ];

  enableParallelBuilding = true;

  meta = {
    description = "PowerPC Mac OS run-time environment (SheepShaver)";
    longDescription = ''
      SheepShaver runs classic PowerPC Mac OS (7.5.2 through 9.0.4) on Linux.
      You need a legal Power Macintosh ROM and Mac OS install media; neither is
      included. On non-PowerPC hosts the built-in CPU emulator is used.

      The optional cxmon in-emulator debugger is disabled (`--with-mon=no`) because
      the cxmon sources in macemu omit files that SheepShaver's build still expects.
    '';
    homepage = "https://github.com/cebix/macemu";
    license = lib.licenses.gpl2Plus;
    maintainers = [ ];
    mainProgram = "SheepShaver";
    platforms = lib.platforms.linux;
  };
}
