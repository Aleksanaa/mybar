{
  lib,
  quickshell,
  qt6,
  wrapGAppsNoGuiHook,
  gobject-introspection,
  wtype,
  python3,
  callPackage,
  runCommand,
}:

let
  qml-niri = callPackage ./niri.nix { };
in
runCommand "mybar" {
  src = lib.cleanSource ../.;
  
  nativeBuildInputs = [
    qt6.wrapQtAppsHook
    wrapGAppsNoGuiHook
    gobject-introspection
  ];

  buildInputs = [
    qml-niri
    qt6.qtbase
    qt6.qt5compat
  ];

  dontWrapGApps = true;
  dontWrapQtApps = true;
} ''
  mkdir -p $out/share/mybar $out/bin
  cp -r $src/* $out/share/mybar
  makeWrapper ${lib.getExe quickshell} $out/bin/mybar \
    --add-flags "-p $out/share/mybar/main.qml" \
    --prefix PATH : ${lib.makeBinPath [
      wtype
      (python3.withPackages (ps: [
        ps.psutil
        ps.dbus-python
        ps.pygobject3
        ps.pyudev
        ps.pulsectl-asyncio
      ]))
    ]} \
    ''${qtWrapperArgs[@]} ''${gappsWrapperArgs[@]}
''
