import asyncio
import sys
import dbus
import dbus.mainloop.glib
from gi.repository import GLib
from ..utils import write_json


def power_profiles_dbus_worker(loop, writer):
    """Worker function to run the GLib main loop for D-Bus signals."""
    SERVICE = "net.hadess.PowerProfiles"
    INTERFACE = "org.freedesktop.DBus.Properties"
    OBJECT_PATH = "/net/hadess/PowerProfiles"

    def send_update(profile):
        asyncio.run_coroutine_threadsafe(
            write_json(writer, {"power_profile": profile}), loop
        )

    def properties_changed_handler(
        interface, changed_properties, invalidated_properties
    ):
        """Signal handler for property changes."""
        if "ActiveProfile" in changed_properties:
            send_update(changed_properties["ActiveProfile"])

    try:
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SystemBus()

        # Get initial value
        proxy = bus.get_object(SERVICE, OBJECT_PATH)
        props_interface = dbus.Interface(proxy, INTERFACE)
        initial_profile = props_interface.Get(
            "net.hadess.PowerProfiles", "ActiveProfile"
        )
        send_update(initial_profile)

        # Subscribe to signals
        bus.add_signal_receiver(
            properties_changed_handler,
            dbus_interface=INTERFACE,
            signal_name="PropertiesChanged",
            path=OBJECT_PATH,
            bus_name=SERVICE,
        )

        # Start the GLib event loop
        GLib.MainLoop().run()
    except dbus.exceptions.DBusException:
        print(
            "Warning: D-Bus service 'net.hadess.PowerProfiles' not found. "
            "Power profile monitoring will be disabled.",
            file=sys.stderr,
        )
    except Exception as e:
        print(f"Error in D-Bus thread: {e}", file=sys.stderr)
