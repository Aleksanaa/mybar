import asyncio
import sys
import dbus
import dbus.mainloop.glib
from gi.repository import GLib
from ..utils import write_json
from ..tasks import long_running_task

DBUS_QUEUE = asyncio.Queue()

def power_profiles_dbus_worker(loop):
    """Worker function to run the GLib main loop for D-Bus signals."""
    SERVICE = "net.hadess.PowerProfiles"
    INTERFACE = "org.freedesktop.DBus.Properties"
    OBJECT_PATH = "/net/hadess/PowerProfiles"
    
    def properties_changed_handler(interface, changed_properties, invalidated_properties):
        """Signal handler for property changes."""
        if "ActiveProfile" in changed_properties:
            new_profile = changed_properties["ActiveProfile"]
            loop.call_soon_threadsafe(DBUS_QUEUE.put_nowait, new_profile)

    try:
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SystemBus()
        
        # Get initial value
        proxy = bus.get_object(SERVICE, OBJECT_PATH)
        props_interface = dbus.Interface(proxy, INTERFACE)
        initial_profile = props_interface.Get("net.hadess.PowerProfiles", "ActiveProfile")
        loop.call_soon_threadsafe(DBUS_QUEUE.put_nowait, initial_profile)

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
    except dbus.exceptions.DBusException as e:
        print(
            "Warning: D-Bus service 'net.hadess.PowerProfiles' not found. "
            "Power profile monitoring will be disabled.",
            file=sys.stderr,
        )
    except Exception as e:
        print(f"Error in D-Bus thread: {e}", file=sys.stderr)


@long_running_task
async def power_profile_monitor(writer):
    """Monitors for power profile changes by listening to the DBUS_QUEUE."""
    while True:
        new_profile = await DBUS_QUEUE.get()
        await write_json(writer, {"power_profile": new_profile})
        DBUS_QUEUE.task_done()
