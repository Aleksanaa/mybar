import asyncio
import sys
import os
import time
from datetime import datetime, timedelta
import dbus
import dbus.mainloop.glib
from gi.repository import GLib
from ..utils import write_json
from ..tasks import long_running_task

UPOWER_QUEUE = asyncio.Queue()

HISTORY_FILE = os.path.expanduser("~/.cache/mybar/battery_history")


def read_history():
    if not os.path.exists(HISTORY_FILE):
        return []
    try:
        with open(HISTORY_FILE, "r") as f:
            lines = f.readlines()
            history = []
            for line in lines:
                parts = line.strip().split(",")
                if len(parts) == 2:
                    try:
                        timestamp = float(parts[0])
                        value = float(parts[1])
                        history.append((timestamp, value))
                    except ValueError:
                        continue
            return history
    except Exception as e:
        print(f"Error reading battery history file: {e}", file=sys.stderr)
        return []


def write_history(history):
    try:
        os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
        with open(HISTORY_FILE, "w") as f:
            for timestamp, value in history:
                f.write(f"{timestamp},{value}\n")
    except Exception as e:
        print(f"Error writing battery history: {e}", file=sys.stderr)


def get_24h_history_list(history, current_percentage):
    now = datetime.now()
    # Align to current hour mark (:00)
    end_hour = now.replace(minute=0, second=0, microsecond=0)
    end_ts = end_hour.timestamp()

    # 24 timestamps from 23 hours ago to now (hour aligned)
    # This ensures index 23 is the current hour (rightmost bar)
    timestamps_needed = [
        (end_hour - timedelta(hours=i)).timestamp() for i in range(23, -1, -1)
    ]

    # Create a working copy of history
    working_history = list(history)

    # Ensure we have at least the current percentage as a baseline if history is sparse
    # The "virtual" current hour entry
    has_current_hour = any(abs(h[0] - end_ts) < 1 for h in working_history)
    if not has_current_hour:
        working_history.append((end_ts, current_percentage))

    working_history.sort()

    result = []
    for ts in timestamps_needed:
        # Find points before or exactly at this timestamp
        before = [h for h in working_history if h[0] <= ts]
        # Find points after or exactly at this timestamp
        after = [h for h in working_history if h[0] >= ts]

        if not before:
            # If nothing before, use the oldest available data (which might be our virtual current)
            result.append(after[0][1] if after else current_percentage)
        elif not after:
            # If nothing after (shouldn't happen with virtual entry), use newest before
            result.append(before[-1][1])
        else:
            # Linear interpolation
            h_before = before[-1]
            h_after = after[0]
            if h_before[0] == h_after[0]:
                result.append(h_before[1])
            else:
                ratio = (ts - h_before[0]) / (h_after[0] - h_before[0])
                val = h_before[1] + (h_after[1] - h_before[1]) * ratio
                result.append(round(val, 1))
    return result


def upower_dbus_worker(loop):
    """Worker function to run the GLib main loop for UPower D-Bus signals."""
    SERVICE = "org.freedesktop.UPower"
    INTERFACE = "org.freedesktop.DBus.Properties"
    DEVICE_INTERFACE = "org.freedesktop.UPower.Device"
    UPOWER_INTERFACE = "org.freedesktop.UPower"
    UPOWER_PATH = "/org/freedesktop/UPower"

    def get_battery_path():
        try:
            bus = dbus.SystemBus()
            proxy = bus.get_object(SERVICE, UPOWER_PATH)
            upower = dbus.Interface(proxy, UPOWER_INTERFACE)
            devices = upower.EnumerateDevices()
            for path in devices:
                if "battery_" in path:
                    return path
            return "/org/freedesktop/UPower/devices/DisplayDevice"
        except Exception:
            return "/org/freedesktop/UPower/devices/DisplayDevice"

    OBJECT_PATH = get_battery_path()

    def get_battery_state(props_interface, device_proxy):
        try:
            percentage = float(props_interface.Get(DEVICE_INTERFACE, "Percentage"))
            state = int(props_interface.Get(DEVICE_INTERFACE, "State"))
            time_to_empty = int(props_interface.Get(DEVICE_INTERFACE, "TimeToEmpty"))
            time_to_full = int(props_interface.Get(DEVICE_INTERFACE, "TimeToFull"))
            energy_rate = float(props_interface.Get(DEVICE_INTERFACE, "EnergyRate"))
            energy = float(props_interface.Get(DEVICE_INTERFACE, "Energy"))
            voltage = float(props_interface.Get(DEVICE_INTERFACE, "Voltage"))
            capacity = float(props_interface.Get(DEVICE_INTERFACE, "Capacity"))
            charging = state == 1
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
                "state": state,
                "energy_rate": round(energy_rate, 2),
                "energy": round(energy, 2),
                "voltage": round(voltage, 2),
                "capacity": round(capacity, 2),
            }
        except Exception as e:
            print(f"Error reading battery properties: {e}", file=sys.stderr)
            return None

    def properties_changed_handler(
        interface, changed_properties, invalidated_properties
    ):
        relevant_props = {"Percentage", "State", "TimeToEmpty", "TimeToFull"}
        if any(prop in changed_properties for prop in relevant_props):
            try:
                bus = dbus.SystemBus()
                proxy = bus.get_object(SERVICE, OBJECT_PATH)
                props_interface = dbus.Interface(proxy, INTERFACE)
                state_dict = get_battery_state(props_interface, proxy)
                if state_dict:
                    loop.call_soon_threadsafe(UPOWER_QUEUE.put_nowait, state_dict)
            except Exception as e:
                print(f"Error handling UPower change: {e}", file=sys.stderr)

    try:
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SystemBus()
        proxy = bus.get_object(SERVICE, OBJECT_PATH)
        props_interface = dbus.Interface(proxy, INTERFACE)
        initial_state = get_battery_state(props_interface, proxy)
        if initial_state:
            loop.call_soon_threadsafe(UPOWER_QUEUE.put_nowait, initial_state)

        bus.add_signal_receiver(
            properties_changed_handler,
            dbus_interface=INTERFACE,
            signal_name="PropertiesChanged",
            path=OBJECT_PATH,
            bus_name=SERVICE,
        )
        GLib.MainLoop().run()
    except Exception as e:
        print(f"Error in UPower D-Bus thread: {e}", file=sys.stderr)


@long_running_task
async def upower_monitor(writer):
    """Monitors for UPower changes and manages 24h battery history."""
    last_hour = datetime.now().hour
    current_percentage = -1.0

    while True:
        try:
            # Wait for battery update
            try:
                bat_state = await asyncio.wait_for(UPOWER_QUEUE.get(), timeout=30)
                current_percentage = float(bat_state["value"])
                await write_json(writer, {"bat": bat_state})

                # Push history update immediately when we have a valid percentage
                history = read_history()
                history_list = get_24h_history_list(history, current_percentage)
                await write_json(writer, {"bat_history": history_list})

                UPOWER_QUEUE.task_done()
            except asyncio.TimeoutError:
                # If we haven't even got the first update yet, skip history push
                if current_percentage < 0:
                    continue

            # Check for hour roll-over
            now = datetime.now()
            if now.hour != last_hour:
                history = read_history()
                cutoff = time.time() - 26 * 3600
                history = [h for h in history if h[0] >= cutoff]

                # Record percentage for the new hour
                timestamp = now.replace(minute=0, second=0, microsecond=0).timestamp()
                history.append((timestamp, current_percentage))
                write_history(history)

                history_list = get_24h_history_list(history, current_percentage)
                await write_json(writer, {"bat_history": history_list})
                last_hour = now.hour

        except Exception as e:
            print(f"Error in upower_monitor task: {e}", file=sys.stderr)
