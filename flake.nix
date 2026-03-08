{
  description = "workaround for touchscreen device";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.flake-parts.flakeModules.easyOverlay
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      perSystem =
        { config, pkgs, ... }:
        {
          devShells = {
            default = pkgs.mkShell {
              packages = [
                (pkgs.callPackage ./nix/quickshell.nix { })
                (pkgs.python3.withPackages (ps: [
                  ps.psutil
                  ps.dbus-python
                  ps.pygobject3
                  ps.pyudev
                  ps.pulsectl-asyncio
                  ps.numpy
                ]))
                pkgs.gobject-introspection
                pkgs.wtype
                pkgs.pulseaudio
              ];
            };
          };
          packages = {
            default = pkgs.callPackage ./nix/default.nix { };
          };
          overlayAttrs = {
            mybar = config.packages.default;
          };
          treefmt = {
            programs.black.enable = true;

            programs.nixfmt.enable = true;

            programs.qmlformat.enable = true;
          };
        };
    };
}
