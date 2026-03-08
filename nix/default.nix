{
  lib,
  quickshell,
  qt6,
  wrapGAppsNoGuiHook,
  gobject-introspection,
  wtype,
  pulseaudio,
  python3,
  runCommand,
}:

runCommand "mybar"
  {
    src = lib.cleanSource ../.;

    nativeBuildInputs = [
      qt6.wrapQtAppsHook
      wrapGAppsNoGuiHook
      gobject-introspection
    ];

    buildInputs = [
      qt6.qtbase
      qt6.qt5compat
    ];

    dontWrapGApps = true;
    dontWrapQtApps = true;
  }
  ''
    mkdir -p $out/share/mybar $out/bin
    cp -r $src/* $out/share/mybar
    makeWrapper ${lib.getExe quickshell} $out/bin/mybar \
      --add-flags "-p $out/share/mybar/main.qml" \
      --prefix PATH : ${
        lib.makeBinPath [
          wtype
          pulseaudio
          (python3.withPackages (ps: [
            ps.psutil
            ps.dbus-python
            ps.pygobject3
            ps.pyudev
            ps.pulsectl-asyncio
          ]))
        ]
      } \
      --chdir $out/share/mybar \
      ''${qtWrapperArgs[@]} ''${gappsWrapperArgs[@]}
  ''
