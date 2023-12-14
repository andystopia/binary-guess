{
  description = ''
    Create a development environment for a basic Rust program.

      - Create a devshell for development (with lld for linking)
      - Create builds for the current system.
      - Create linux MUSL-libc builds
      - Cross compile MUSL builds for docker OCI
  '';
  inputs = {
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    naersk = {
      url = "github:nix-community/naersk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "nixpkgs/nixos-23.05";
  };

  outputs = {
    self,
    nixpkgs,
    fenix,
    naersk,
  }: let
    supportedSystems = ["x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    pkgsFor = forAllSystems (system: import nixpkgs {inherit system;});
  in {
    packages = forAllSystems (system: let
      pkgs = pkgsFor.${system};

      legacyPkgs = nixpkgs.legacyPackages.${system};
      toolchain = fenix.packages.${system}.stable.toolchain;

      manifest = (nixpkgs.lib.importTOML ./Cargo.toml).package;

      # if your binary differs in name from
      # the package.name in Cargo.toml,
      # replace manifest.name with a string
      # containing the name of your binary
      binaryName = manifest.name;
    in rec {
      # compile the active rust project
      # default =
      #   (legacyPkgs.makeRustPlatform {
      #     cargo = toolchain;
      #     rustc = toolchain;
      #   })
      #   .buildRustPackage {
      #     # change the manifest.name to the binary file
      #     # if you're binary file does not match the
      #     # name of the library
      #     pname = binaryName;
      #     version = manifest.version;

      #     src = pkgs.lib.cleanSource ./.;
      #     cargoLock.lockFile = ./Cargo.lock;
      #     cargoLock.allowBuiltinFetchGit = true;

      #     buildInputs =
      #       [
      #         pkgs.llvmPackages_15.bintools # use lld for fast linking
      #       ]
      #       ++ nixpkgs.lib.optionals pkgs.stdenv.isDarwin [
      #         pkgs.darwin.apple_sdk.frameworks.CoreServices
      #         pkgs.libiconv
      #       ];
      #   };
      default =
        (naersk.lib.${system}.override {
          cargo = toolchain;
          rustc = toolchain;
        })
        .buildPackage {
          buildInputs = [pkgs.llvmPackages_15.bintools];
          src = pkgs.lib.cleanSource ./.;
        };

      app-arm-linux = let
        pkgs = nixpkgs.legacyPackages.${system};
        target = "x86_64-unknown-linux-musl";
        toolchain = with fenix.packages.${system};
          combine [
            stable.cargo
            stable.rustc
            targets.${target}.stable.rust-std
          ];
      in
        (naersk.lib.${system}.override {
          cargo = toolchain;
          rustc = toolchain;
        })
        .buildPackage {
          buildInputs = [pkgs.llvmPackages_15.bintools];
          src = pkgs.lib.cleanSource ./.;
          CARGO_BUILD_TARGET = target;
        };
      dockerImage = pkgs.dockerTools.buildImage {
        name = binaryName;
        tag = "latest";
        # copyToRoot = [ "${app-arm-linux}/bin" ];
        copyToRoot = pkgs.buildEnv {
          name = binaryName;
          paths = [app-arm-linux];
        };
        config = {
          Cmd = ["/bin/${binaryName}"];
        };
      };
    });

    devShells = forAllSystems (
      system: let
        pkgs = pkgsFor.${system};
        fenixPkgs = fenix.packages.${system};
        target = "aarch64-unknown-linux-musl";

        basePkgs = [
          (fenixPkgs.stable.withComponents [
            "cargo"
            "rustc"
            "rustfmt"
            "clippy"
          ])
          # fenixPkgs.stable.rust-analyzer
          pkgs.llvmPackages_15.bintools # we want lld for fast linking
        ];

        buildInputs = nixpkgs.lib.optionals pkgs.stdenv.isDarwin 
          (with pkgs.darwin.apple_sdk.frameworks; [CoreServices Foundation AppKit]) ++  
          [pkgs.libiconv];
      in {
        default = pkgs.mkShell {
          name = "rust-devshell";
          packages = basePkgs;
          inherit buildInputs;
        };
        nice = pkgs.mkShell {
          name = "rust-devshell-fancy";
          packages = basePkgs ++ (with pkgs; [just starship]);
          inherit buildInputs;
          shellHook = ''
            eval "$(starship init bash)"
          '';
        };
        cross = pkgs.gccStdenv.mkDerivation {
          name = "rust-devshell-cross";
          buildInputs =
            (with pkgs; [just starship zig llvmPackages_15.bintools])
            ++ [
              (with fenixPkgs;
                combine [
                  stable.rustc
                  stable.cargo
                  stable.clippy
                  stable.rustfmt
                  targets.${target}.stable.rust-std
                ])
              fenixPkgs.rust-analyzer
            ];
          # inherit buildInputs;

          shellHook = ''
            eval "$(starship init bash)"
            export BUILD_TARGET="${target}"
          '';
        };
      }
    );

    formatter = forAllSystems (
      system:
        pkgsFor.${system}.alejandra
    );
  };
}
