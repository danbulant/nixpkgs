{ stdenv, lib, fetchurl, runtimeShell
, gettext, pkg-config, python3
, avahi, libgphoto2, libieee1284, libjpeg, libpng, libtiff, libusb1, libv4l, net-snmp
, curl, systemd, libxml2, poppler, gawk
, sane-drivers

# List of { src name backend } attibute sets - see installFirmware below:
, extraFirmware ? []

# For backwards compatibility with older setups; use extraFirmware instead:
, gt68xxFirmware ? null, snapscanFirmware ? null

# Not included by default, scan snap drivers require fetching of unfree binaries.
, scanSnapDriversUnfree ? false, scanSnapDriversPackage ? sane-drivers.epjitsu
}:

stdenv.mkDerivation {
  pname = "sane-backends";
  version = "1.0.32";

  src = fetchurl {
    # raw checkouts of the repo do not work because, the configure script is
    # only functional in manually uploaded release tarballs.
    # https://gitlab.com/sane-project/backends/-/issues/440
    # unfortunately this make the url unpredictable on update, to find the link
    # go to https://gitlab.com/sane-project/backends/-/releases and choose
    # the link with other in the URL.
    url = "https://gitlab.com/sane-project/backends/uploads/104f09c07d35519cc8e72e604f11643f/sane-backends-1.0.32.tar.gz";
    sha256 = "055iicihxa6b28iv5fnz13n67frdr5nrydq2c846f9x7q0vw4a1s";
  };

  outputs = [ "out" "doc" "man" ];

  nativeBuildInputs = [
    gettext
    pkg-config
    python3
  ];

  buildInputs = [
    avahi
    libgphoto2
    libieee1284
    libjpeg
    libpng
    libtiff
    libusb1
    libv4l
    net-snmp
    curl
    systemd
    libxml2
    poppler
    gawk
  ];

  enableParallelBuilding = true;

  configureFlags =
    lib.optional (avahi != null)   "--with-avahi"
    ++ lib.optional (libusb1 != null) "--with-usb"
  ;

  postInstall = let

    compatFirmware = extraFirmware
      ++ lib.optional (gt68xxFirmware != null) {
        src = gt68xxFirmware.fw;
        inherit (gt68xxFirmware) name;
        backend = "gt68xx";
      }
      ++ lib.optional (snapscanFirmware != null) {
        src = snapscanFirmware;
        name = "your-firmwarefile.bin";
        backend = "snapscan";
      };

    installFirmware = f: ''
      mkdir -p $out/share/sane/${f.backend}
      ln -sv ${f.src} $out/share/sane/${f.backend}/${f.name}
    '';

  in ''
    mkdir -p $out/etc/udev/rules.d/
    ./tools/sane-desc -m udev > $out/etc/udev/rules.d/49-libsane.rules || \
    cp tools/udev/libsane.rules $out/etc/udev/rules.d/49-libsane.rules
    # the created 49-libsane references /bin/sh
    substituteInPlace $out/etc/udev/rules.d/49-libsane.rules \
      --replace "RUN+=\"/bin/sh" "RUN+=\"${runtimeShell}"

    substituteInPlace $out/lib/libsane.la \
      --replace "-ljpeg" "-L${lib.getLib libjpeg}/lib -ljpeg"

    # net.conf conflicts with the file generated by the nixos module
    rm $out/etc/sane.d/net.conf

  ''
  + lib.optionalString scanSnapDriversUnfree ''
    # the ScanSnap drivers live under the epjitsu subdirectory, which was already created by the build but is empty.
    rmdir $out/share/sane/epjitsu
    ln -svT ${scanSnapDriversPackage} $out/share/sane/epjitsu
  ''
  + lib.concatStrings (builtins.map installFirmware compatFirmware);

  meta = with lib; {
    description = "SANE (Scanner Access Now Easy) backends";
    longDescription = ''
      Collection of open-source SANE backends (device drivers).
      SANE is a universal scanner interface providing standardized access to
      any raster image scanner hardware: flatbed scanners, hand-held scanners,
      video- and still-cameras, frame-grabbers, etc. For a list of supported
      scanners, see http://www.sane-project.org/sane-backends.html.
    '';
    homepage = "http://www.sane-project.org/";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
  };
}
