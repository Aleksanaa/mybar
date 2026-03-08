pragma Singleton
import QtQuick
import Quickshell

QtObject {
    readonly property color bg: "#1e1e2e"
    readonly property color fg: "#cdd6f4"
    readonly property color capsule: "#45475a"
    readonly property color accent: "#89b4fa"
    readonly property color border: "#313244"
    readonly property color clock: "#a6e3a1"
    readonly property string globalFont: "JetBrainsMono Nerd Font Propo"

    // Helper to resolve application icons with normalization and fallback
    function resolveAppIcon(iconName, appName, fallback) {
        if (iconName && iconName !== "") {
            var p = Quickshell.iconPath(iconName, true);
            if (p !== "")
                return p;
        }

        if (appName && appName !== "") {
            // Normalize: lowercase and replace spaces/dots with hyphens
            var normalized = appName.toLowerCase().replace(/[\s\.]+/g, "-");
            var p2 = Quickshell.iconPath(normalized, true);
            if (p2 !== "")
                return p2;
        }

        return Quickshell.iconPath(fallback);
    }
}
