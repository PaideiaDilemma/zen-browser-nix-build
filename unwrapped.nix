# Firefox build from nixpkgs and adapted for zen.
# this builds zen without surfer, wayland-only, linux only i think, no pgo (yet?)
# the important stuff is in the postPatch phase in here.
# TODO: it should be doable to directly use buildMozillaMach from nixpkgs
# First patch sources and then just use buildMozillaMach with extraConfigureFlags.
# The only problem is the meta information i think.
# TODO: pgo
{
  name,
  version,
  firefox-src,
  zen-src,
  zen-l10n,
  zen-version,
  llvmBuildPackages,
  # nah jemallocSupport ? !stdenv.hostPlatform.isMusl,
  alsaSupport ? llvmBuildPackages.stdenv.hostPlatform.isLinux,
  debugBuild ? false,
  enableDebugSymbols ? !llvmBuildPackages.stdenv.hostPlatform.is32bit,
  ffmpegSupport ? true,
  geolocationSupport ? false,
  gssSupport ? true,
  jackSupport ? false,
  ltoSupport ? false,
  pipewireSupport ? true,
  pulseaudioSupport ? llvmBuildPackages.stdenv.hostPlatform.isLinux,
  sndioSupport ? llvmBuildPackages.stdenv.hostPlatform.isLinux,
  webrtcSupport ? false,
}: {
  lib,
  stdenvAdapters,
  writeText,
  rsync,

  autoconf,
  cargo,
  dump_syms,
  git,
  makeWrapper,
  mimalloc,
  nodejs,
  perl,
  pkg-config,
  pkgsCross, # wasm32 rlbox
  python3,
  runCommand,
  rust-cbindgen,
  rustPlatform,
  rustc,
  unzip,
  which,
  wrapGAppsHook3,

  bzip2,
  dbus,
  dbus-glib,
  file,
  fontconfig,
  freetype,
  glib,
  gnum4,
  gtk3,
  icu77, # if you fiddle with the icu parameters, please check Thunderbird's overrides
  libGL,
  libGLU,
  libdrm,
  libevent,
  libffi,
  libjpeg,
  libpng,
  libstartup_notification,
  libvpx,
  libxkbcommon,
  libwebp,
  nasm,
  nspr,
  nss_latest,
  pango,
  xorg,
  zlib,

  # Darwin
  apple-sdk_14,
  apple-sdk_15,
  cups,

  # optional
  alsa-lib,
  libjack2,
  libkrb5,
  libpulseaudio,
  sndio,

  # part of the wrapper in nixpkgs
  makeDesktopItem,
  udev,
  pciutils,
  libva,
  libgbm,
  libnotify,
  vulkan-loader,
}: let
  binaryName = "zen";

  # TODO: from nixpkgs firefox it seems like we don't need this
  # Copy the way they get mach to work.
  mach-env = python3.withPackages (ps:
    with ps; [
      ansiconv
      appdirs
      attrs
      blessed
      build
      cbor2
      certifi
      chardet
      charset-normalizer
      click
      colorama
      diskcache
      distro
      filelock
      glean-parser
      glean-sdk
      idna
      importlib-metadata
      importlib-resources
      jinja2
      jsmin
      jsonschema
      looseversion
      orjson
      packaging
      pip
      pip-tools
      pkgutil-resolve-name
      platformdirs
      pyproject-hooks
      pyrsistent
      python-hglib
      requests
      sentry-sdk
      setuptools
      six
      toml
      tomli
      tomlkit
      tqdm
      typing-extensions
      urllib3
      wcwidth
      wheel
      zipp
      zstandard
    ]);

  # Compile the wasm32 sysroot to build the RLBox Sandbox
  # https://hacks.mozilla.org/2021/12/webassembly-and-back-again-fine-grained-sandboxing-in-firefox-95/
  # We only link c++ libs here, our compiler wrapper can find wasi libc and crt itself.
  wasiSysRoot = runCommand "wasi-sysroot" {} ''
    mkdir -p $out/lib/wasm32-wasi
    for lib in ${pkgsCross.wasi32.llvmPackages.libcxx}/lib/*; do
      ln -s $lib $out/lib/wasm32-wasi
    done
  '';

  # Mold can also do lto :)
  buildEnv = lib.lists.foldl' (acc: adapter: adapter acc) llvmBuildPackages.stdenv [
    stdenvAdapters.useMoldLinker
  ];

  # https://github.com/zen-browser/desktop/blob/dev/surfer.json
  brandingConfig = {
    backgroundColor = "#303338"; # #282A33 is original
    brandShorterName = "Zen";
    brandShortName = "Zen";
    brandFullName = "Zen Browser";
    brandingVendor = "Zen OSS Team (Unofficial build)";
  };

  # https://github.com/zen-browser/surfer/blob/main/src/commands/patches/branding-patch.ts
  brandingNsi = writeText "branding.nsi" ''
    # This Source Code Form is subject to the terms of the Mozilla Public
    # License, v. 2.0. If a copy of the MPL was not distributed with this
    # file, You can obtain one at http://mozilla.org/MPL/2.0/.

    # NSIS branding defines for official release builds.
    # The nightly build branding.nsi is located in browser/installer/windows/nsis/
    # The unofficial build branding.nsi is located in browser/branding/unofficial/

    # BrandFullNameInternal is used for some registry and file system values
    # instead of BrandFullName and typically should not be modified.
    !define BrandFullNameInternal "${brandingConfig.brandFullName}"
    !define BrandFullName         "${brandingConfig.brandFullName}"
    !define CompanyName           "${brandingConfig.brandingVendor}"
    !define URLInfoAbout          "https://zen-browser.app"
    !define URLUpdateInfo         "https://zen-browser.app/release-notes/#${zen-version}"
    !define HelpLink              "https://github.com/zen-browser/desktop/issues"

    !define URLManualDownload "https://zen-browser.app/download"
    !define URLSystemRequirements "https://www.mozilla.org/firefox/system-requirements/"
    !define Channel "stable"

    # The installer's certificate name and issuer expected by the stub installer
    !define CertNameDownload   "${brandingConfig.brandFullName}"
    !define CertIssuerDownload "DigiCert SHA2 Assured ID Code Signing CA"

    # Dialog units are used so the UI displays correctly with the system's DPI
    # settings. These are tweaked to look good with the en-US strings; ideally
    # we would customize them for each locale but we don't really have a way to
    # implement that and it would be a ton of work for the localizers.
    !define PROFILE_CLEANUP_LABEL_TOP "50u"
    !define PROFILE_CLEANUP_LABEL_LEFT "22u"
    !define PROFILE_CLEANUP_LABEL_WIDTH "175u"
    !define PROFILE_CLEANUP_LABEL_HEIGHT "100u"
    !define PROFILE_CLEANUP_LABEL_ALIGN "left"
    !define PROFILE_CLEANUP_CHECKBOX_LEFT "22u"
    !define PROFILE_CLEANUP_CHECKBOX_WIDTH "175u"
    !define PROFILE_CLEANUP_BUTTON_LEFT "22u"
    !define INSTALL_HEADER_TOP "70u"
    !define INSTALL_HEADER_LEFT "22u"
    !define INSTALL_HEADER_WIDTH "180u"
    !define INSTALL_HEADER_HEIGHT "100u"
    !define INSTALL_BODY_LEFT "22u"
    !define INSTALL_BODY_WIDTH "180u"
    !define INSTALL_INSTALLING_TOP "115u"
    !define INSTALL_INSTALLING_LEFT "270u"
    !define INSTALL_INSTALLING_WIDTH "150u"
    !define INSTALL_PROGRESS_BAR_TOP "100u"
    !define INSTALL_PROGRESS_BAR_LEFT "270u"
    !define INSTALL_PROGRESS_BAR_WIDTH "150u"
    !define INSTALL_PROGRESS_BAR_HEIGHT "12u"

    !define PROFILE_CLEANUP_CHECKBOX_TOP_MARGIN "12u"
    !define PROFILE_CLEANUP_BUTTON_TOP_MARGIN "12u"
    !define PROFILE_CLEANUP_BUTTON_X_PADDING "80u"
    !define PROFILE_CLEANUP_BUTTON_Y_PADDING "8u"
    !define INSTALL_BODY_TOP_MARGIN "20u"

    # Font settings that can be customized for each channel
    !define INSTALL_HEADER_FONT_SIZE 20
    !define INSTALL_HEADER_FONT_WEIGHT 600
    !define INSTALL_INSTALLING_FONT_SIZE 15
    !define INSTALL_INSTALLING_FONT_WEIGHT 600

    # UI Colors that can be customized for each channel
    !define COMMON_TEXT_COLOR 0x000000
    !define COMMON_BACKGROUND_COLOR 0xFFFFFF
    !define INSTALL_INSTALLING_TEXT_COLOR 0xFFFFFF
    # This color is written as 0x00BBGGRR because it's actually a COLORREF value.
    !define PROGRESS_BAR_BACKGROUND_COLOR 0xFFAA00
  '';

  defaultPrefs = writeText "unoffical-zen-nixos-default-prefs.nsi" ''
    /* This Source Code Form is subject to the terms of the Mozilla Public
    * License, v. 2.0. If a copy of the MPL was not distributed with this
    * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

    pref("startup.homepage_override_url", "https://zen-browser.app/whatsnew?v=%VERSION%");
    pref("startup.homepage_welcome_url", "https://zen-browser.app/welcome/");
    pref("startup.homepage_welcome_url.additional", "https://zen-browser.app/privacy-policy/");

    // Give the user x seconds to react before showing the big UI. default=192 hours
    pref("app.update.promptWaitTime", 691200);
    // app.update.url.manual: URL user can browse to manually if for some reason
    // all update installation attempts fail.
    // app.update.url.details: a default value for the "More information about this
    // update" link supplied in the "An update is available" page of the update
    // wizard.
    pref("app.update.url.manual", "https://zen-browser.app/download/");
    pref("app.update.url.details", "https://zen-browser.app/release-notes/latest/");
    pref("app.releaseNotesURL", "https://zen-browser.app/whatsnew/");
    pref("app.releaseNotesURL.aboutDialog", "https://www.zen-browser.app/release-notes/%VERSION%/");
    pref("app.releaseNotesURL.prompt", "https://zen-browser.app/release-notes/%VERSION%/");

    // Number of usages of the web console.
    // If this is less than 5, then pasting code into the web console is disabled
    pref("devtools.selfxss.count", 5);

    pref("geo.provider.use_geoclue", false);
  '';

  dirstibutionIni = writeText "distribution.ini" (
    lib.generators.toINI {} {
      # Some light branding indicating this build uses our distro preferences
      Global = {
        id = "nixos";
        version = "1.0";
      };
      Preferences = {
        # These values are exposed through telemetry
        "app.distributor" = "unofficial-nixos";
        "app.distributor.channel" = "TODO";
      };
    }
  );

  wmClass = "zen-browser";
  desktopItem = makeDesktopItem {
    name = binaryName;
    exec = "${binaryName} --name ${wmClass} %U";
    # installed below
    icon = wmClass;
    desktopName = brandingConfig.brandFullName;
    startupNotify = true;
    startupWMClass = wmClass;
    terminal = false;
  };

  ffprefs = rustPlatform.buildRustPackage {
    name = "ffprefs";
    version = "latest";

    postPatch = ''
      substituteInPlace src/main.rs \
          --replace "../engine/" "../"
    '';

    src = "${zen-src}/tools/ffprefs";
    useFetchCargoVendor = true;
    cargoHash = "sha256-DZMwxeulQiIiSATU0MoyqiUMA0USZq6umhkr67hZH1Q=";
  };
in
  buildEnv.mkDerivation {
    pname = "zen-browser-unwrapped";
    src = firefox-src;
    inherit version;

    outpus = ["out" "lib" "share"];

    nativeBuildInputs = [
      cargo
      git
      llvmBuildPackages.bintools
      mach-env
      nasm
      nodejs
      rsync
      rust-cbindgen
      rustPlatform.bindgenHook
      rustc
      unzip
      wrapGAppsHook3
    ];

    ## Doesn't work?
    #appendRunpaths = [
    #  "${pipewire}/lib"
    #  "${udev}/lib"
    #  "${libva}/lib"
    #  "${libgbm}/lib"
    #  "${libnotify}/lib"
    #  "${cups}/lib"
    #  "${pciutils}/lib"
    #  "${vulkan-loader}/lib"
    #];

    depsBuildBuild = [
      pkg-config
    ];

    WASM_CC = "${pkgsCross.wasi32.stdenv.cc}/bin/${pkgsCross.wasi32.stdenv.cc.targetPrefix}cc";
    WASM_CXX = "${pkgsCross.wasi32.stdenv.cc}/bin/${pkgsCross.wasi32.stdenv.cc.targetPrefix}c++";
    MACH_BUILD_PYTHON_NATIVE_PACKAGE_SOURCE = "none";

    MOZ_NOSPAM = "1";
    MOZ_APP_BASENAME = "Zen";
    MOZ_USER_DIR = "zen_browser";
    MOZ_APP_REMOTINGNAME = binaryName;

    postPatch = ''
      rm -rf obj-x86_64-pc-linux-gnu
      patchShebangs mach build

      echo "Zenifying firefox..."

      # Merge zen-browser/desktop/src into the firefox source
      rsync -r --exclude "*.patch" ${zen-src}/src/ .
      rsync -r ${zen-src}/prefs/ ./prefs

      # Apply all patches
      find ${zen-src}/src/ -name "*.patch" -exec sh -c 'git apply "$0"' {} \;

      # Uhg, for branding we will overwrite the unofficial one.
      # That avoids dealing with moz.build and is also what surfer does it seems.
      rsync -r ${zen-src}/configs/branding/release/ ./browser/branding/unofficial/
      rsync ${brandingNsi} ./browser/branding/unofficial/branding.nsi

      # Copy transitions for the zen ui (this is about what update_en_US_packs does)
      rsync -r ${zen-l10n}/en-US/browser/ ./browser/locales/en-US/

      # Zen preferences
      ${ffprefs}/bin/ffprefs .
    '';

    preConfigure = ''
      mkdir objdir

      export MOZ_OBJDIR=$(pwd)/objdir
      export MOZBUILD_STATE_PATH=$TMPDIR/mozbuild
      # Set reproducible build date; https://bugzilla.mozilla.org/show_bug.cgi?id=885777#c21
      export MOZ_BUILD_DATE=$(head -n1 sourcestamp.txt)

      # AS=as in the environment causes build failure
      # https://bugzilla.mozilla.org/show_bug.cgi?id=1497286
      unset AS

      configureScript="$(realpath ./mach) configure"
    '';

    setOutputFlags = false; # `./mach configure` doesn't understand `--*dir=` flags.

    configureFlags =
      [
        "--with-branding=browser/branding/unofficial"
        "--with-app-name=zen"
        "--with-app-basename=Zen"
        "--disable-tests"
        "--disable-updater"
        "--enable-application=browser"
        "--enable-default-toolkit=cairo-gtk3-wayland-only"
        "--enable-system-pixman"
        "--with-distribution-id=app.zen-browser.nixos"
        "--with-libclang-path=${llvmBuildPackages.libclang.lib}/lib"
        "--with-system-ffi"
        "--with-system-icu"
        "--with-system-jpeg"
        "--with-system-libevent"
        "--with-system-libvpx"
        "--with-system-nspr"
        "--with-system-nss"
        "--with-system-png" # needs APNG support
        "--with-system-webp"
        "--with-system-zlib"
        "--with-wasi-sysroot=${wasiSysRoot}"
        # for firefox, host is buildPlatform, target is hostPlatform
        "--host=${buildEnv.buildPlatform.config}"
        "--target=${buildEnv.hostPlatform.config}"
      ]
      ++ lib.optionals ltoSupport [
        "--enable-lto=cross,full" # Cross-Language LTO
      ]
      # elf-hack is broken when using clang+lld:
      # https://bugzilla.mozilla.org/show_bug.cgi?id=1482204
      #++ lib.optional (ltoSupport && (buildStdenv.hostPlatform.isAarch32 || buildStdenv.hostPlatform.isi686 || buildStdenv.hostPlatform.isx86_64)) "--disable-elf-hack"
      ++ lib.optional true "--allow-addon-sideload"
      ++ [
        (lib.enableFeature false "crashreporter")
        (lib.enableFeature alsaSupport "alsa")
        (lib.enableFeature ffmpegSupport "ffmpeg")
        (lib.enableFeature geolocationSupport "necko-wifi")
        (lib.enableFeature gssSupport "negotiateauth")
        (lib.enableFeature jackSupport "jack")
        (lib.enableFeature pulseaudioSupport "pulseaudio")
        (lib.enableFeature sndioSupport "sndio")
        (lib.enableFeature webrtcSupport "webrtc")
        (lib.enableFeature debugBuild "debug")
        (lib.enableFeature (!debugBuild && !buildEnv.hostPlatform.is32bit) "release")
        (lib.enableFeature enableDebugSymbols "debug-symbols")
        #(if debugBuild then "--enable-profiling" else "--enable-optimize")
        # --enable-release adds -ffunction-sections & LTO that require a big amount
        # of RAM, and the 32-bit memory space cannot handle that linking
      ];
    #++ lib.optionals enableDebugSymbols [ "--disable-strip" "--disable-install-strip" ]
    #++ lib.optional (branding != null) "--with-branding=${branding}";

    buildInputs =
      [
        bzip2
        file
        libGL
        libGLU
        libstartup_notification
        libxkbcommon
        libdrm
        icu77
      ]
      ++ lib.optionals buildEnv.hostPlatform.isDarwin [
        apple-sdk_15
        cups
      ]
      ++ lib.optionals (!buildEnv.hostPlatform.isDarwin) [
        dbus
        dbus-glib
        fontconfig
        freetype
        glib
        gtk3
        libffi
        libevent
        libjpeg
        libpng
        libvpx
        libwebp
        nspr
        pango
        nss_latest
      ]
      ++ lib.optional alsaSupport alsa-lib
      ++ lib.optional jackSupport libjack2
      ++ lib.optional pulseaudioSupport libpulseaudio # only headers are needed
      ++ lib.optional sndioSupport sndio
      ++ lib.optional gssSupport libkrb5;

    buildPhase = ''
      ./mach build --priority normal
    '';

    preInstall = ''
      cd objdir
    '';

    postInstall = ''
      # Remove SDK cruft. FIXME: move to a separate output?
      rm -rf $out/share/idl $out/include $out/lib/${binaryName}-devel-*

      # Needed to find Mozilla runtime
      gappsWrapperArgs+=(--argv0 "$out/bin/.${binaryName}-wrapped")

      resourceDir=$out/lib/${binaryName}
      # Install distribution customizations
      install -Dvm644 ${dirstibutionIni} "$resourceDir/distribution/distribution.ini"
      install -Dvm644 ${defaultPrefs} "$resourceDir/browser/defaults/preferences/unoffical-nixos-zen-default-prefs.js"
      install -Dvm644 ${zen-src}/docs/assets/zen-dark.svg "$out/share/icons/hicolor/scalable/apps/${wmClass}.svg"
      # Install desktop file
      install -m 644 -D -t $out/share/applications ${desktopItem}/share/applications/*
    '';

    separateDebugInfo = enableDebugSymbols;
    enableParallelBuilding = true;
    requiredSystemFeatures = ["big-parallel"];
    doCheck = false;

    #env = lib.optionalAttrs stdenv.hostPlatform.isMusl {
    # Firefox relies on nonstandard behavior of the glibc dynamic linker. It re-uses
    # previously loaded libraries even though they are not in the rpath of the newly loaded binary.
    # On musl we have to explicitly set the rpath to include these libraries.
    #LDFLAGS = "-Wl,-rpath,${placeholder "out"}/lib/${binaryName}";
    #};

    passthru = {
      applicationName = name;
      inherit binaryName;
      inherit alsaSupport;
      inherit jackSupport;
      inherit pipewireSupport;
      inherit sndioSupport;
      inherit nspr;
      inherit ffmpegSupport;
      inherit gssSupport;
      inherit gtk3;
      inherit wasiSysRoot;
    };

    meta = {
      homepage = "https://zen-browser.app";
      description = "Beautiful, fast, private browser";
      license = lib.licenses.mpl20;
      mainProgram = binaryName;
      platforms = [
          "aarch64-linux" # TODO: test
          "x86_64-linux"
        ];
    };
  }
