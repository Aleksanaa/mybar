{
  description = "workaround for touchscreen device";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [ "x86_64-linux" "aarch64-linux" ];
    perSystem = { pkgs, system, ... }: {
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
            ]))
            pkgs.gobject-introspection
            pkgs.wtype
          ];
        };
      };
      packages = {
        default = pkgs.callPackage ./nix/default.nix { };
      };
    };
  };
}
