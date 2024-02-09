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

  version = "0.45.0";
  rust_nightly_version = "2024-01-17";
  hash = "sha256-iWscv+x6MbI9O56vewkCvf2lvEcfVi0o3nRfqpoccDA=";
  dependenciesHash = "sha256-cKugBXGhdy6P54Sn/sowaZOl8ln/Qpk/N0y5ZGoRs3o=";

  rust_targets = {
    "x86_64-linux" = "x86_64-unknown-linux-gnu";
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

  # Make sure we have all the dependencies cached by building the bundle.
  # At this stage we only store the CARGO_HOME directory not the built artifacts.
  kani-bundle-deps = pkgs.stdenv.mkDerivation {
    pname = "kani-bundle";
    inherit version src;

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

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = dependenciesHash;
  };

  # Now with the locked dependencies we can build the bundle
  kani-bundle = pkgs.stdenv.mkDerivation {
    pname = "kani-bundle";
    inherit version src;

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

  };
in
kani
