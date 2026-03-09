import asyncio
import sys
import os
import time
from datetime import datetime, timedelta
import dbus
import dbus.mainloop.glib
from gi.repository import GLib
from ..utils import write_json

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


def get_battery_path(bus):
    SERVICE = "org.freedesktop.UPower"
    UPOWER_INTERFACE = "org.freedesktop.UPower"
    UPOWER_PATH = "/org/freedesktop/UPower"
    try:
        proxy = bus.get_object(SERVICE, UPOWER_PATH)
        upower = dbus.Interface(proxy, UPOWER_INTERFACE)
        devices = upower.EnumerateDevices()
        for path in devices:
            if "battery_" in path:
                return path
        return "/org/freedesktop/UPower/devices/DisplayDevice"
    except Exception:
        return "/org/freedesktop/UPower/devices/DisplayDevice"


class BatteryStateParser:
    def __init__(self):
        self.current_state = {}

    def parse(self, properties):
        try:
            percentage = float(
                properties.get("Percentage", self.current_state.get("percentage", 0))
            )
            state = int(properties.get("State", self.current_state.get("state", 0)))
            time_to_empty = int(
                properties.get(
                    "TimeToEmpty", self.current_state.get("time_to_empty", 0)
                )
            )
            time_to_full = int(
                properties.get("TimeToFull", self.current_state.get("time_to_full", 0))
            )
            energy_rate = float(
                properties.get("EnergyRate", self.current_state.get("energy_rate", 0))
            )
            energy = float(
                properties.get("Energy", self.current_state.get("energy", 0))
            )
            voltage = float(
                properties.get("Voltage", self.current_state.get("voltage", 0))
            )
            capacity = float(
                properties.get("Capacity", self.current_state.get("capacity", 0))
            )

            charging = state == 1
            bat_value = str(int(percentage))
            bat_approx = f"{(int(percentage) // 10) * 10:03d}"
            if state == 4:
                bat_approx = "100"

            # Keep raw values for future incremental updates
            self.current_state.update(
                {
                    "percentage": percentage,
                    "state": state,
                    "time_to_empty": time_to_empty,
                    "time_to_full": time_to_full,
                    "energy_rate": energy_rate,
                    "energy": energy,
                    "voltage": voltage,
                    "capacity": capacity,
                }
            )

            return {
                "value": bat_value,
                "approx": bat_approx,
                "charging": charging,
                "time_to_empty": time_to_empty,
                "time_to_full": time_to_full,
                "state": state,
                "energy_rate": round(energy_rate, 1),
                "energy": round(energy, 2),
                "voltage": round(voltage, 1),
                "capacity": round(capacity, 2),
            }
        except Exception as e:
            print(f"Error parsing battery properties: {e}", file=sys.stderr)
            return None


class BatteryHistoryManager:
    def __init__(self, loop, writer):
        self.loop = loop
        self.writer = writer
        self.history = read_history()
        self.last_hour = -1
        self.current_percentage = -1.0
        self.last_sent_bat = None

    def check_hour_rollover(self):
        if self.current_percentage < 0:
            return

        now = datetime.now()
        if now.hour != self.last_hour:
            if self.last_hour != -1:
                cutoff = time.time() - 26 * 3600
                self.history = [h for h in self.history if h[0] >= cutoff]
                timestamp = now.replace(minute=0, second=0, microsecond=0).timestamp()
                self.history.append((timestamp, self.current_percentage))
                write_history(self.history)

            history_list = get_24h_history_list(self.history, self.current_percentage)
            asyncio.run_coroutine_threadsafe(
                write_json(self.writer, {"bat_history": history_list}), self.loop
            )
            self.last_hour = now.hour

    def update(self, state_dict):
        # Round values for comparison to reduce noise
        # Note: state_dict already contains some rounded values from parser.parse
        if state_dict == self.last_sent_bat:
            return

        asyncio.run_coroutine_threadsafe(
            write_json(self.writer, {"bat": state_dict}), self.loop
        )
        self.last_sent_bat = state_dict

        current_percentage = float(state_dict["value"])
        self.current_percentage = current_percentage
        self.check_hour_rollover()


def upower_dbus_worker(loop, writer):
    """Worker function to run the GLib main loop for UPower D-Bus signals."""
    SERVICE = "org.freedesktop.UPower"
    INTERFACE = "org.freedesktop.DBus.Properties"
    DEVICE_INTERFACE = "org.freedesktop.UPower.Device"

    parser = BatteryStateParser()
    history_manager = BatteryHistoryManager(loop, writer)

    def send_update(state_dict):
        history_manager.update(state_dict)

    def properties_changed_handler(
        interface, changed_properties, invalidated_properties
    ):
        relevant_props = {
            "Percentage",
            "State",
            "TimeToEmpty",
            "TimeToFull",
            "EnergyRate",
            "Energy",
            "Voltage",
            "Capacity",
        }
        if any(prop in changed_properties for prop in relevant_props):
            state_dict = parser.parse(changed_properties)
            if state_dict:
                send_update(state_dict)

    def check_history():
        history_manager.check_hour_rollover()
        return True

    try:
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SystemBus()
        OBJECT_PATH = get_battery_path(bus)

        proxy = bus.get_object(SERVICE, OBJECT_PATH)
        props_interface = dbus.Interface(proxy, INTERFACE)

        # Initial sync fetch of all properties
        all_props = props_interface.GetAll(DEVICE_INTERFACE)
        initial_state = parser.parse(all_props)

        if initial_state:
            send_update(initial_state)

        bus.add_signal_receiver(
            properties_changed_handler,
            dbus_interface=INTERFACE,
            signal_name="PropertiesChanged",
            path=OBJECT_PATH,
            bus_name=SERVICE,
        )

        # Check for hour rollover every minute
        GLib.timeout_add_seconds(60, check_history)
        GLib.MainLoop().run()
    except Exception as e:
        print(f"Error in UPower D-Bus thread: {e}", file=sys.stderr)
