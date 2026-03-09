import asyncio
import sys
import dbus
import dbus.mainloop.glib
from gi.repository import GLib
from ..utils import write_json


def get_swayidle_unit_path(bus):
    """Get the object path for the swayidle.service unit."""
    systemd = bus.get_object("org.freedesktop.systemd1", "/org/freedesktop/systemd1")
    manager = dbus.Interface(systemd, "org.freedesktop.systemd1.Manager")
    return manager.GetUnit("swayidle.service")


def swayidle_dbus_worker(loop, writer):
    """Worker function to run the GLib main loop for D-Bus signals."""

    def send_update(status):
        is_active = status == "active"
        asyncio.run_coroutine_threadsafe(
            write_json(writer, {"swayidle": {"active": is_active}}), loop
        )

    def properties_changed_handler(
        interface, changed_properties, invalidated_properties
    ):
        """Signal handler for property changes."""
        if "ActiveState" in changed_properties:
            send_update(changed_properties["ActiveState"])

    try:
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SessionBus()  # Use the session bus for user services

        unit_path = get_swayidle_unit_path(bus)

        # Get initial value
        unit_proxy = bus.get_object("org.freedesktop.systemd1", unit_path)
        props_interface = dbus.Interface(unit_proxy, "org.freedesktop.DBus.Properties")
        initial_state = props_interface.Get(
            "org.freedesktop.systemd1.Unit", "ActiveState"
        )
        send_update(initial_state)

        # Subscribe to signals
        bus.add_signal_receiver(
            properties_changed_handler,
            dbus_interface="org.freedesktop.DBus.Properties",
            signal_name="PropertiesChanged",
            path=unit_path,
            arg0="org.freedesktop.systemd1.Unit",
        )

        GLib.MainLoop().run()
    except dbus.exceptions.DBusException as e:
        if "org.freedesktop.systemd1.NoSuchUnit" in str(e):
            print(
                "Warning: D-Bus service 'swayidle.service' not found. "
                "Sway-idle monitoring will be disabled.",
                file=sys.stderr,
            )
        else:
            print(f"Error in D-Bus thread: {e}", file=sys.stderr)
    except Exception as e:
        print(f"Error in D-Bus thread: {e}", file=sys.stderr)
