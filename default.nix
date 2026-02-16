{
  quickshell,
  qt6,
  callPackage,
}:

let
  qml-niri = callPackage ./niri.nix { };
in
quickshell.overrideAttrs (old: {
  buildInputs = old.buildInputs ++ [
    qt6.qt5compat
    qml-niri
  ];
})
