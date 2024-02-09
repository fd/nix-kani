{ fetchFromGitHub
, rust-bin
, crane
, pkgs
, lib
, cbmc-viewer
, autoPatchelfHook
, stdenv
}:
let
  pname = "kani";
  rust_target = rust_targets.${pkgs.system};

  # version = "0.31.0";
  # rust_nightly_version = "2023-04-30";
  # hash = "sha256-HuYAH3ELJT2uphE3Z12ajeiqh3DR+c6jRyqSFpmYXGY=";

  version = "0.32.0";
  rust_nightly_version = "2023-06-24";
  hash = "sha256-igDbCbu7fhZOOdu2LAz8VdxXVPGTfsNqbWmc85SX9e0=";


  rust_targets = {
    "x86_64-linux" = "x86_64-unknown-linux-gnu";
  };

  bundle_hashes = {
    # "x86_64-linux" = "sha256:0b8xan1f09h7z5byb8z68n0x6fj5k64hwpz5yhsqg5cr7sfd0b4c";
    "x86_64-linux" = "sha256:1iqkwyvfq7w52hjvbj8vlq0331bch5m1ak0yzdmbvn6wp9k19bzq";
  };

  toolchain = rust-bin.nightly.${rust_nightly_version}.default.override {
    extensions = [
      "llvm-tools-preview"
      "rustc-dev"
      "rust-src"
      "rustfmt"
    ];
  };

  craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;

  src = fetchFromGitHub {
    pname = "${pname}-source";
    inherit version hash;

    owner = "model-checking";
    repo = "kani";

    rev = "kani-${version}";
  };

  commonArgs = {
    inherit src pname version;
  };
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

  kani = craneLib.buildPackage (commonArgs // {
    inherit cargoArtifacts;
    doCheck = false;

    cargoExtraArgs = "--package kani-verifier";

    passthru.bundle = kani-bundle;
    passthru.toolchain = toolchain;

    nativeBuildInputs = [
      pkgs.makeWrapper
    ];

    preBuild =
      ''
        substituteInPlace src/lib.rs \
          --replace '=> setup::setup(use_local_bundle)' '=> panic!("kani for nix is already setup")'
      '';

    postFixup =
      ''
        wrapProgram $out/bin/kani \
          --set KANI_HOME ${kani-bundle} \
          --prefix PATH : "${pkgs.universal-ctags}/bin" \
          --prefix PATH : "${pkgs.gcc}/bin" \
          --prefix PATH : "${kani-bundle}/kani-${version}/bin"
        wrapProgram $out/bin/cargo-kani \
          --set KANI_HOME ${kani-bundle} \
          --prefix PATH : "${pkgs.universal-ctags}/bin" \
          --prefix PATH : "${pkgs.gcc}/bin" \
          --prefix PATH : "${kani-bundle}/kani-${version}/bin"
      '';
  });

  # kani-driver = craneLib.buildPackage (commonArgs // {
  #   inherit cargoArtifacts;
  #   doCheck = false;

  #   # cargoExtraArgs = "--package kani-driver --package kani-compiler";

  #   # nativeBuildInputs = [
  #   #   pkgs.makeWrapper
  #   # ];

  #   buildInputs = [
  #     pkgs.cbmc
  #   ];

  #   RUSTUP_TOOLCHAIN = "nightly-${rust_nightly_version}-${rust_target}";

  #   preBuild =
  #     ''
  #       # There are no rustup shims
  #       substituteInPlace kani-driver/src/call_cargo.rs \
  #         --replace '.arg(session::toolchain_shorthand())' ""

  #       substituteInPlace kani-driver/src/concrete_playback/playback.rs \
  #         --replace '.arg(session::toolchain_shorthand())' ""

  #       substituteInPlace kani-compiler/build.rs \
  #         --replace 'let rustup_home = env::var("RUSTUP_HOME").unwrap();' "" \
  #         --replace 'let rustup_tc = env::var("RUSTUP_TOOLCHAIN").unwrap();' "" \
  #         --replace 'let rustup_lib = path_str!([&rustup_home, "toolchains", &rustup_tc, "lib"]);' 'let rustup_lib = "${toolchain}/lib";'
  #     '';

  #   cargoBuildCommand =
  #     ''
  #       cargo run --release -p build-kani -- bundle
  #     '';


  #   installPhaseCommand =
  #     ''
  #       mkdir -p $out/
  #       cp -r --reflink=auto kani-${version}/* $out/
  #     '';
  #   # postInstall =
  #   #   ''
  #   #     cp -r --reflink=auto library $out/library
  #   #   '';
  # });

  # kani-bundle = pkgs.stdenv.mkDerivation {
  #   pname = "kani-bundle";
  #   inherit version;

  #   src = builtins.fetchTarball {
  #     url = "https://github.com/model-checking/kani/releases/download/kani-${version}/kani-${version}-${rust_target}.tar.gz";
  #     sha256 = bundle_hashes.${pkgs.system};
  #   };

  #   toolchain = "nightly-${rust_nightly_version}-${rust_target}";
  #   dontPatchELF = true;

  #   nativeBuildInputs =
  #     [
  #       pkgs.makeWrapper
  #       autoPatchelfHook
  #     ];

  #   buildInputs =
  #     [
  #       # pkgs.gcc-unwrapped
  #       pkgs.zlib
  #       stdenv.cc.cc.lib
  #       toolchain
  #     ];

  #   runtimeDependencies =
  #     [
  #       # pkgs.gcc-unwrapped
  #       pkgs.zlib
  #       stdenv.cc.cc.lib
  #     ];

  #   buildPhase = ''
  #     # Ensure that the toolchain matches the one used to build kani
  #     TOOLCHAIN="$(cat rust-toolchain-version)"
  #     if [[ "$toolchain" != "$TOOLCHAIN" ]]; then
  #       echo "Toolchain mismatch: $toolchain != $TOOLCHAIN"
  #       exit 1
  #     fi

  #     bundle_dir="$out/kani-${version}"
  #     mkdir -p $bundle_dir
  #     cp -r --reflink=auto ./* $bundle_dir/
  #     ln -s ${toolchain} $bundle_dir/toolchain
  #     ln -s ${cbmc-viewer} $bundle_dir/pyroot

  #     # Replace kani-driver
  #     rm -rf $bundle_dir/bin/kani-driver
  #     ln -s ${kani-driver}/bin/kani-driver $bundle_dir/bin/kani-driver
  #     # Replace kani-compiler
  #     rm -rf $bundle_dir/bin/kani-compiler
  #     ln -s ${kani-driver}/bin/kani-compiler $bundle_dir/bin/kani-compiler

  #     wrapProgram $bundle_dir/bin/kani-compiler  \
  #       --prefix LD_LIBRARY_PATH : "${pkgs.zlib}/lib"
  #   '';
  # };

  # Make sure we have all the dependencies cached by building the bundle.
  # At this stage we only store the CARGO_HOME directory not the built artifacts.
  kani-bundle-deps = pkgs.stdenv.mkDerivation {
    pname = "kani-bundle";
    inherit version src;

    nativeBuildInputs =
      [
        # autoPatchelfHook
      ];

    buildInputs =
      [
        toolchain
        pkgs.cbmc
        pkgs.kissat
        pkgs.zlib
        stdenv.cc.cc.lib
      ];

    recordedDeps = [
      toolchain
      pkgs.cbmc
      pkgs.kissat
      pkgs.zlib
      stdenv.cc.cc.lib
    ];


    RUSTUP_TOOLCHAIN = "nightly-${rust_nightly_version}-${rust_target}";

    buildPhase =
      ''
        mkdir -p .cargo-home
        export CARGO_HOME=$PWD/.cargo-home
        

        # There are no rustup shims
        substituteInPlace kani-driver/src/call_cargo.rs \
          --replace '.arg(session::toolchain_shorthand())' ""

        substituteInPlace kani-driver/src/concrete_playback/playback.rs \
          --replace '.arg(session::toolchain_shorthand())' ""

        substituteInPlace kani-compiler/build.rs \
          --replace 'let rustup_home = env::var("RUSTUP_HOME").unwrap();' "" \
          --replace 'let rustup_tc = env::var("RUSTUP_TOOLCHAIN").unwrap();' "" \
          --replace 'let rustup_lib = path_str!([&rustup_home, "toolchains", &rustup_tc, "lib"]);' 'let rustup_lib = "${toolchain}/lib";'
    
        substituteInPlace tools/build-kani/src/main.rs \
          --replace 'bundle_cbmc(dir)?' "" \
          --replace 'bundle_kissat(dir)?' "" \
          --replace 'std::fs::remove_dir_all(dir)?;' ""
    
        cargo run --release -p build-kani -- bundle

        mkdir -p $out
        tar -C $CARGO_HOME -czf $out/cargo-home.tar.gz .
      '';

    # installPhase =
    #   ''
    #     rm -rf $out/bin
    #   '';

    # dontFixup = true;

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-8sFv0gkbJ50+Sc8IqpNkVbyAmvSokU+rE4eJwoc9T8I=";
  };

  # Now with the locked dependencies we can build the bundle
  kani-bundle = pkgs.stdenv.mkDerivation {
    pname = "kani-bundle";
    inherit version src;

    nativeBuildInputs =
      [
        # autoPatchelfHook
      ];

    buildInputs =
      [
        toolchain
        pkgs.cbmc
        pkgs.kissat
        pkgs.zlib
        stdenv.cc.cc.lib
      ];

    recordedDeps = [
      toolchain
      pkgs.cbmc
      pkgs.kissat
      pkgs.zlib
      stdenv.cc.cc.lib
    ];


    RUSTUP_TOOLCHAIN = "nightly-${rust_nightly_version}-${rust_target}";

    buildPhase =
      ''
        mkdir -p .cargo-home
        export CARGO_HOME=$PWD/.cargo-home
        tar -xzf ${kani-bundle-deps}/cargo-home.tar.gz -C $CARGO_HOME
        

        # There are no rustup shims
        substituteInPlace kani-driver/src/call_cargo.rs \
          --replace '.arg(session::toolchain_shorthand())' ""

        substituteInPlace kani-driver/src/concrete_playback/playback.rs \
          --replace '.arg(session::toolchain_shorthand())' ""

        substituteInPlace kani-compiler/build.rs \
          --replace 'let rustup_home = env::var("RUSTUP_HOME").unwrap();' "" \
          --replace 'let rustup_tc = env::var("RUSTUP_TOOLCHAIN").unwrap();' "" \
          --replace 'let rustup_lib = path_str!([&rustup_home, "toolchains", &rustup_tc, "lib"]);' 'let rustup_lib = "${toolchain}/lib";'
    
        substituteInPlace tools/build-kani/src/main.rs \
          --replace 'bundle_cbmc(dir)?' "" \
          --replace 'bundle_kissat(dir)?' "" \
          --replace 'std::fs::remove_dir_all(dir)?;' ""
    
        cargo run --release -p build-kani -- bundle
      '';

    installPhase =
      ''
        mkdir -p $out
        cp -r --reflink=auto kani-${version} $out/kani-${version}

        # Link cbmc and kissat
        for f in ${pkgs.cbmc}/bin/*; do
          ln -s $f $out/kani-${version}/bin/
        done
        for f in ${pkgs.kissat}/bin/*; do
          ln -s $f $out/kani-${version}/bin/
        done
      '';

    # dontFixup = true;

  };
in
kani
