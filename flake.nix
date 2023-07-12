{
  description = "Kani is a Rust library for symbolic execution of Rust programs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, crane, nixpkgs, flake-utils, rust-overlay }:
    let
      systems = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in
    flake-utils.lib.eachSystem systems (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };
      in
      rec {
        packages.default = packages.kani;
        packages.kani = pkgs.callPackage ./kani.nix {
          inherit crane;
          cbmc-viewer = packages.cbmc-viewer;
        };
        packages.cbmc-viewer = pkgs.callPackage ./cbmc-viewer.nix { };

        checks.version = pkgs.runCommand "kani-check-version"
          {
            buildInputs = [ packages.kani ];
          }
          ''
            kani --version
            mkdir -p $out
          '';

        checks.success = pkgs.runCommand "kani-check-success"
          {
            buildInputs = [ packages.kani ];
          }
          ''
            mkdir -p $out
            cd $out
            cp ${./test}/success.rs ./
            kani success.rs
          '';

        checks.failure = pkgs.runCommand "kani-check-failure"
          {
            buildInputs = [ packages.kani ];
          }
          ''
            mkdir -p $out
            cd $out
            cp ${./test}/failure.rs .
            kani failure.rs || exit 0
            exit 1
          '';

        checks.cargoSuccess = pkgs.runCommand "kani-check-cargo-success"
          {
            buildInputs = [ packages.kani packages.kani.toolchain ];
          }
          ''
            mkdir -p $out
            cd $out
            cp -r ${./test}/test-cargo/* ./
            cargo kani
          '';
      });
}

