{
  description = "Kani is a Rust library for symbolic execution of Rust programs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, crane, nixpkgs, flake-utils, rust-overlay }:
    let
      systems = [ "x86_64-linux" ];
    in
    flake-utils.lib.eachSystem systems (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };
      in
      {
        packages.default = self.packages.${system}.kani;
        packages.kani = pkgs.callPackage ./kani.nix {
          inherit crane;
          cbmc-viewer = self.packages.${system}.cbmc-viewer;
        };
        packages.cbmc-viewer = pkgs.callPackage ./cbmc-viewer.nix { };

        checks.version = pkgs.testers.testVersion {
          package = self.packages.${system}.kani;
        };

        checks.success = pkgs.runCommand "kani-check-success"
          {
            buildInputs = [ self.packages.${system}.kani ];
          }
          ''
            mkdir -p $out
            cd $out
            cp ${./test}/success.rs ./
            kani success.rs
          '';

        checks.failure = pkgs.runCommand "kani-check-failure"
          {
            buildInputs = [ self.packages.${system}.kani ];
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
            buildInputs = [ self.packages.${system}.kani pkgs.rust-bin.stable.latest.default ];
          }
          ''
            mkdir -p $out
            cd $out
            cp -r ${./test}/test-cargo-success/* ./
            cargo kani
          '';

        checks.cargoFailure = pkgs.runCommand "kani-check-cargo-failure"
          {
            buildInputs = [ self.packages.${system}.kani pkgs.rust-bin.stable.latest.default ];
          }
          ''
            mkdir -p $out
            cd $out
            cp -r ${./test}/test-cargo-failure/* ./
            cargo kani || exit 0
            exit 1
          '';

        checks.cargoZerocopy = pkgs.runCommand "kani-check-cargo-zerocopy"
          {
            buildInputs = [ self.packages.${system}.kani pkgs.rust-bin.stable.latest.default ];
          }
          ''
            mkdir -p $out
            cd $out
            
            # include hidden files in glob
            shopt -s dotglob

            cp -r ${./test}/test-cargo-zerocopy/* ./
            cargo kani
          '';

        checks.crane =
          let
            toolchain = pkgs.rust-bin.stable.latest.default;
            craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;
            src = ./test/test-cargo-success;
            pname = "test-cargo";
            version = "0.1.0";
            commonArgs = {
              inherit src pname version;
            };
            cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          in
          craneLib.mkCargoDerivation (commonArgs // {
            inherit cargoArtifacts;
            pnameSuffix = "-kani";
            buildPhaseCargoCommand = "cargo kani";
            nativeBuildInputs = [ self.packages.${system}.kani ];
            installPhase = ''
              mkdir -p $out
            '';
          });

        checks.crane-zerocopy =
          let
            toolchain = pkgs.rust-bin.stable.latest.default;
            craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;
            src = pkgs.runCommand "prep-src" { } ''
              mkdir -p $out
              cp -r ${./test}/test-cargo-zerocopy/* $out
              chmod -R u+w $out
              rm -rf $out/vendor $out/.cargo
            '';
            pname = "test-cargo";
            version = "0.1.0";
            commonArgs = {
              inherit src pname version;
            };
            cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          in
          craneLib.mkCargoDerivation (commonArgs // {
            inherit cargoArtifacts;
            pnameSuffix = "-kani";
            buildPhaseCargoCommand = "cargo kani";
            nativeBuildInputs = [ self.packages.${system}.kani ];
            installPhase = ''
              mkdir -p $out
            '';
          });

        devShells.default = pkgs.mkShell {
          buildInputs = [ self.packages.${system}.kani pkgs.rust-bin.stable.latest.default ];
        };
      });
}

