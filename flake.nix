{
  description = "nerdctl with eStargz and zstd:chunked support, as a NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    nerdctl-src = {
      url = "github:containerd/nerdctl/v2.3.4";
      flake = false;
    };
    stargz-snapshotter-src = {
      url = "github:containerd/stargz-snapshotter/v0.18.2";
      flake = false;
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , treefmt-nix
    , nerdctl-src
    , stargz-snapshotter-src
    ,
    }:
    let
      nerdctlVersion = "2.3.4";
      stargzVersion = "0.18.2";
    in
    flake-utils.lib.eachDefaultSystem
      (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          treefmt = treefmt-nix.lib.evalModule pkgs {
            projectRootFile = "flake.nix";
            programs.nixpkgs-fmt.enable = true;
          };
        in
        {
          packages = {
            nerdctl = pkgs.callPackage ./nix/nerdctl.nix {
              src = nerdctl-src;
              version = nerdctlVersion;
            };

            stargz-snapshotter = pkgs.callPackage ./nix/stargz-snapshotter.nix {
              src = stargz-snapshotter-src;
              version = stargzVersion;
            };

            default = self.packages.${system}.nerdctl;
          };

          formatter = treefmt.config.build.wrapper;

          devShells.default = pkgs.mkShell {
            packages = [
              self.packages.${system}.nerdctl
              self.packages.${system}.stargz-snapshotter
              pkgs.containerd
              pkgs.buildkit
              pkgs.cni-plugins
              treefmt.config.build.wrapper
            ];
          };

          checks = nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            nerdctl = self.packages.${system}.nerdctl;
            stargz-snapshotter = self.packages.${system}.stargz-snapshotter;
            formatting = treefmt.config.build.check self;
            integration = import ./nix/test.nix { inherit self; } { inherit pkgs; };
          };
        }
      )
    // {
      nixosModules.default = import ./nix/module.nix { inherit self; };
    };
}
