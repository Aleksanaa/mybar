import asyncio
import sys
import dbus
import dbus.mainloop.glib
from gi.repository import GLib
from ..utils import write_json
from ..tasks import long_running_task

UPOWER_QUEUE = asyncio.Queue()

def upower_dbus_worker(loop):
    """Worker function to run the GLib main loop for UPower D-Bus signals."""
    SERVICE = "org.freedesktop.UPower"
    INTERFACE = "org.freedesktop.DBus.Properties"
    DEVICE_INTERFACE = "org.freedesktop.UPower.Device"
    OBJECT_PATH = "/org/freedesktop/UPower/devices/DisplayDevice"
    
    def get_battery_state(props_interface):
        try:
            percentage = float(props_interface.Get(DEVICE_INTERFACE, "Percentage"))
            state = int(props_interface.Get(DEVICE_INTERFACE, "State"))
            time_to_empty = int(props_interface.Get(DEVICE_INTERFACE, "TimeToEmpty"))
            time_to_full = int(props_interface.Get(DEVICE_INTERFACE, "TimeToFull"))

            charging = state == 1  # 1 is charging, 2 is discharging, 4 is fully charged
            
            # Format battery string appropriately
            bat_value = str(int(percentage))
            bat_approx = f"{(int(percentage) // 10) * 10:03d}"
            if state == 4:
                bat_approx = "100"

            return {
                "value": bat_value,
                "approx": bat_approx,
                "charging": charging,
                "time_to_empty": time_to_empty,
                "time_to_full": time_to_full,
                "state": state
            }
        except Exception as e:
            print(f"Error reading battery properties: {e}", file=sys.stderr)
            return None

    def properties_changed_handler(interface, changed_properties, invalidated_properties):
        """Signal handler for UPower property changes."""
        # Only process if battery properties changed
        relevant_props = {"Percentage", "State", "TimeToEmpty", "TimeToFull"}
        if any(prop in changed_properties for prop in relevant_props):
            try:
                bus = dbus.SystemBus()
                proxy = bus.get_object(SERVICE, OBJECT_PATH)
                props_interface = dbus.Interface(proxy, INTERFACE)
                state_dict = get_battery_state(props_interface)
                if state_dict:
                    loop.call_soon_threadsafe(UPOWER_QUEUE.put_nowait, state_dict)
            except Exception as e:
                 print(f"Error handling UPower change: {e}", file=sys.stderr)

    try:
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SystemBus()
        
        # Get initial value
        proxy = bus.get_object(SERVICE, OBJECT_PATH)
        props_interface = dbus.Interface(proxy, INTERFACE)
        initial_state = get_battery_state(props_interface)
        if initial_state:
            loop.call_soon_threadsafe(UPOWER_QUEUE.put_nowait, initial_state)

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
            "Warning: D-Bus service 'org.freedesktop.UPower' not found or DisplayDevice missing. "
            "Battery monitoring will be disabled.",
            file=sys.stderr,
        )
    except Exception as e:
        print(f"Error in UPower D-Bus thread: {e}", file=sys.stderr)


@long_running_task
async def upower_monitor(writer):
    """Monitors for UPower changes by listening to the UPOWER_QUEUE."""
    while True:
        bat_state = await UPOWER_QUEUE.get()
        await write_json(writer, {"bat": bat_state})
        UPOWER_QUEUE.task_done()
