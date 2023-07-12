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
  version = "0.31.0";
  rust_target = rust_targets.${pkgs.system};
  rust_nightly_version = "2023-04-30";
  hash = "sha256-HuYAH3ELJT2uphE3Z12ajeiqh3DR+c6jRyqSFpmYXGY=";


  rust_targets = {
    "x86_64-linux" = "x86_64-unknown-linux-gnu";
    "x86_64-darwin" = "x86_64-apple-darwin";
    "aarch64-darwin" = "aarch64-apple-darwin";
  };

  bundle_hashes = {
    "x86_64-linux" = "sha256:0b8xan1f09h7z5byb8z68n0x6fj5k64hwpz5yhsqg5cr7sfd0b4c";
    "x86_64-darwin" = "sha256:0c7fpn9fxd22166q0rkz61w72hy9di53q1q0zaa98qpki18dmg6j";
    "aarch64-darwin" = "sha256:1c91m2skb1xp75dp2rvdxyv0znqr6g4fh8vw5q9q9g2cj8j5cr09";
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

    buildInputs = [
      # Add additional build inputs here
    ] ++ lib.optionals pkgs.stdenv.isDarwin [
      # Additional darwin specific inputs can be set here
      pkgs.libiconv
    ];
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


  kani-bundle = pkgs.stdenv.mkDerivation {
    pname = "kani-bundle";
    inherit version;

    src = builtins.fetchTarball {
      url = "https://github.com/model-checking/kani/releases/download/kani-${version}/kani-${version}-${rust_target}.tar.gz";
      sha256 = bundle_hashes.${pkgs.system};
    };

    toolchain = "nightly-${rust_nightly_version}-${rust_target}";
    dontPatchELF = true;

    nativeBuildInputs =
      [
        pkgs.makeWrapper
      ]
      ++ (lib.optionals stdenv.isLinux [ autoPatchelfHook ]);

    buildInputs =
      [
        # pkgs.gcc-unwrapped
        pkgs.zlib
        stdenv.cc.cc.lib
        toolchain
      ]
      # ++ (lib.optionals stdenv.isLinux [ pkgs.glibc ])
    ;

    runtimeDependencies =
      [
        # pkgs.gcc-unwrapped
        pkgs.zlib
        stdenv.cc.cc.lib
      ]
      # ++ (lib.optionals stdenv.isLinux [ pkgs.glibc ])
    ;

    buildPhase = ''
      # Ensure that the toolchain matches the one used to build kani
      TOOLCHAIN="$(cat rust-toolchain-version)"
      if [[ "$toolchain" != "$TOOLCHAIN" ]]; then
        echo "Toolchain mismatch: $toolchain != $TOOLCHAIN"
        exit 1
      fi

      bundle_dir="$out/kani-${version}"
      mkdir -p $bundle_dir
      cp -r --reflink=auto ./* $bundle_dir/
      ln -s ${toolchain} $bundle_dir/toolchain
      ln -s ${cbmc-viewer} $bundle_dir/pyroot

      wrapProgram $bundle_dir/bin/kani-compiler  \
        --prefix LD_LIBRARY_PATH : "${pkgs.zlib}/lib"
    '';
  };
in
kani
