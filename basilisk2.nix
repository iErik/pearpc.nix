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
  src,
}:

stdenv.mkDerivation {
  pname = "basilisk2";
  version = "unstable-2025-01-06";

  inherit src;

  sourceRoot = "source/BasiliskII/src/Unix";

  strictDeps = true;

  nativeBuildInputs = [
    autoconf
    automake
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
    NO_CONFIGURE=1 ./autogen.sh
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
  ] ++ lib.optionals (with stdenv.hostPlatform; isx86_32 || isx86_64) [ "--enable-jit-compiler" ];

  enableParallelBuilding = true;

  meta = {
    description = "68k Macintosh emulator (Basilisk II)";
    longDescription = ''
      Basilisk II runs 68k Mac OS software on Linux and other systems. You need a
      legal Mac ROM image and Mac OS install media; neither is included.
    '';
    homepage = "https://github.com/cebix/macemu";
    license = lib.licenses.gpl2Plus;
    maintainers = [ ];
    mainProgram = "BasiliskII";
    platforms = lib.platforms.linux;
  };
}
