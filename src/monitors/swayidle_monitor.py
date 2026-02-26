import asyncio
import sys
import dbus
import dbus.mainloop.glib
from gi.repository import GLib
from ..tasks import long_running_task
from ..utils import write_json

DBUS_QUEUE = asyncio.Queue()


def get_swayidle_unit_path(bus):
    """Get the object path for the swayidle.service unit."""
    systemd = bus.get_object("org.freedesktop.systemd1", "/org/freedesktop/systemd1")
    manager = dbus.Interface(systemd, "org.freedesktop.systemd1.Manager")
    return manager.GetUnit("swayidle.service")


def swayidle_dbus_worker(loop):
    """Worker function to run the GLib main loop for D-Bus signals."""

    def properties_changed_handler(
        interface, changed_properties, invalidated_properties
    ):
        """Signal handler for property changes."""
        if "ActiveState" in changed_properties:
            new_state = changed_properties["ActiveState"]
            loop.call_soon_threadsafe(DBUS_QUEUE.put_nowait, new_state)

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
        loop.call_soon_threadsafe(DBUS_QUEUE.put_nowait, initial_state)

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


@long_running_task
async def swayidle_monitor(writer):
    """Monitors for swayidle service changes by listening to the DBUS_QUEUE."""
    while True:
        try:
            # Wait for an update from the D-Bus thread
            status = await DBUS_QUEUE.get()
            is_active = status == "active"
            response = {"swayidle": {"active": is_active}}
            await write_json(writer, response)
            DBUS_QUEUE.task_done()
        except asyncio.CancelledError:
            # Properly handle task cancellation
            break
