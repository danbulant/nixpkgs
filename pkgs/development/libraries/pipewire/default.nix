{ stdenv
, lib
, fetchFromGitLab
, removeReferencesTo
, python3
, meson
, ninja
, systemd
, pkg-config
, doxygen
, graphviz
, valgrind
, glib
, dbus
, alsaLib
, libjack2
, udev
, libva
, libsndfile
, SDL2
, vulkan-headers
, vulkan-loader
, webrtc-audio-processing
, ncurses
, makeFontsConf
, callPackage
, nixosTests
, withMediaSession ? true
, gstreamerSupport ? true, gst_all_1 ? null
, ffmpegSupport ? true, ffmpeg ? null
, bluezSupport ? true, bluez ? null, sbc ? null, libopenaptx ? null, ldacbt ? null, fdk_aac ? null
, nativeHspSupport ? true
, nativeHfpSupport ? true
, ofonoSupport ? true
, hsphfpdSupport ? true
, pulseTunnelSupport ? true, libpulseaudio ? null
, zeroconfSupport ? true, avahi ? null
}:

let
  fontsConf = makeFontsConf {
    fontDirectories = [];
  };

  mesonEnable = b: if b then "enabled" else "disabled";

  self = stdenv.mkDerivation rec {
    pname = "pipewire";
    version = "0.3.30";

    outputs = [
      "out"
      "lib"
      "pulse"
      "jack"
      "dev"
      "doc"
      "mediaSession"
      "installedTests"
    ];

    src = fetchFromGitLab {
      domain = "gitlab.freedesktop.org";
      owner = "pipewire";
      repo = "pipewire";
      rev = version;
      sha256 = "sha256-DnaPvZoDaegjtJNKBmCJEAZe5FQBnSER79FPnxiWQUE=";
    };

    patches = [
      # Break up a dependency cycle between outputs.
      ./0040-alsa-profiles-use-libdir.patch
      # Change the path of the pipewire-pulse binary in the service definition.
      ./0050-pipewire-pulse-path.patch
      # Change the path of the pipewire-media-session binary in the service definition.
      ./0055-pipewire-media-session-path.patch
      # Move installed tests into their own output.
      ./0070-installed-tests-path.patch
      # Add option for changing the config install directory
      ./0080-pipewire-config-dir.patch
      # Remove output paths from the comments in the config templates to break dependency cycles
      ./0090-pipewire-config-template-paths.patch
    ];

    nativeBuildInputs = [
      doxygen
      graphviz
      meson
      ninja
      pkg-config
      python3
    ];

    buildInputs = [
      alsaLib
      dbus
      glib
      libjack2
      libsndfile
      ncurses
      udev
      vulkan-headers
      vulkan-loader
      webrtc-audio-processing
      valgrind
      SDL2
      systemd
    ] ++ lib.optionals gstreamerSupport [ gst_all_1.gst-plugins-base gst_all_1.gstreamer ]
    ++ lib.optional ffmpegSupport ffmpeg
    ++ lib.optionals bluezSupport [ bluez libopenaptx ldacbt sbc fdk_aac ]
    ++ lib.optional pulseTunnelSupport libpulseaudio
    ++ lib.optional zeroconfSupport avahi;

    mesonFlags = [
      "-Ddocs=enabled"
      "-Dman=disabled" # we don't have xmltoman
      "-Dexamples=${mesonEnable withMediaSession}" # only needed for `pipewire-media-session`
      "-Dudevrulesdir=lib/udev/rules.d"
      "-Dinstalled_tests=enabled"
      "-Dinstalled_test_prefix=${placeholder "installedTests"}"
      "-Dpipewire_pulse_prefix=${placeholder "pulse"}"
      "-Dmedia-session-prefix=${placeholder "mediaSession"}"
      "-Dlibjack-path=${placeholder "jack"}/lib"
      "-Dlibcamera=disabled"
      "-Dlibpulse=${mesonEnable pulseTunnelSupport}"
      "-Davahi=${mesonEnable zeroconfSupport}"
      "-Dgstreamer=${mesonEnable gstreamerSupport}"
      "-Dffmpeg=${mesonEnable ffmpegSupport}"
      "-Dbluez5=${mesonEnable bluezSupport}"
      "-Dbluez5-backend-hsp-native=${mesonEnable nativeHspSupport}"
      "-Dbluez5-backend-hfp-native=${mesonEnable nativeHfpSupport}"
      "-Dbluez5-backend-ofono=${mesonEnable ofonoSupport}"
      "-Dbluez5-backend-hsphfpd=${mesonEnable hsphfpdSupport}"
      "-Dsysconfdir=/etc"
      "-Dpipewire_confdata_dir=${placeholder "lib"}/share/pipewire"
    ];

    FONTCONFIG_FILE = fontsConf; # Fontconfig error: Cannot load default config file

    doCheck = true;

    postUnpack = ''
      patchShebangs source/doc/strip-static.sh
      patchShebangs source/spa/tests/gen-cpp-test.py
    '';

    postInstall = ''
      pushd $lib/share
      mkdir -p $out/nix-support/etc/pipewire
      for f in pipewire/*.conf; do
        echo "Generating JSON from $f"
        $out/bin/spa-json-dump "$f" > "$out/nix-support/etc/$f.json"
      done

      mkdir -p $mediaSession/nix-support/etc/pipewire/media-session.d
      for f in pipewire/media-session.d/*.conf; do
        echo "Generating JSON from $f"
        $out/bin/spa-json-dump "$f" > "$mediaSession/nix-support/etc/$f.json"
      done
      popd

      moveToOutput "share/pipewire/media-session.d/*.conf" "$mediaSession"
      moveToOutput "share/systemd/user/pipewire-media-session.*" "$mediaSession"
      moveToOutput "lib/systemd/user/pipewire-media-session.*" "$mediaSession"
      moveToOutput "bin/pipewire-media-session" "$mediaSession"

      moveToOutput "share/systemd/user/pipewire-pulse.*" "$pulse"
      moveToOutput "lib/systemd/user/pipewire-pulse.*" "$pulse"
      moveToOutput "bin/pipewire-pulse" "$pulse"
    '';

    passthru = {
      updateScript = ./update.sh;
      tests = {
        installedTests = nixosTests.installed-tests.pipewire;

        # This ensures that all the paths used by the NixOS module are found.
        test-paths = callPackage ./test-paths.nix {
          paths-out = [
            "share/alsa/alsa.conf.d/50-pipewire.conf"
            "nix-support/etc/pipewire/client-rt.conf.json"
            "nix-support/etc/pipewire/client.conf.json"
            "nix-support/etc/pipewire/jack.conf.json"
            "nix-support/etc/pipewire/pipewire.conf.json"
            "nix-support/etc/pipewire/pipewire-pulse.conf.json"
          ];
          paths-out-media-session = [
            "nix-support/etc/pipewire/media-session.d/alsa-monitor.conf.json"
            "nix-support/etc/pipewire/media-session.d/bluez-monitor.conf.json"
            "nix-support/etc/pipewire/media-session.d/media-session.conf.json"
            "nix-support/etc/pipewire/media-session.d/v4l2-monitor.conf.json"
          ];
          paths-lib = [
            "lib/alsa-lib/libasound_module_pcm_pipewire.so"
            "share/alsa-card-profile/mixer"
          ];
        };
      };
    };

    meta = with lib; {
      description = "Server and user space API to deal with multimedia pipelines";
      homepage = "https://pipewire.org/";
      license = licenses.mit;
      platforms = platforms.linux;
      maintainers = with maintainers; [ jtojnar ];
    };
  };

in self
