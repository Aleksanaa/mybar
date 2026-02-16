import sys
import json
import asyncio
import functools
import time
# This script requires the 'psutil' library. Please install it with: pip install psutil
import psutil
import dbus
import dbus.mainloop.glib
from gi.repository import GLib
import threading

# --- D-Bus setup for threaded execution ---
DBUS_QUEUE = asyncio.Queue()
DBUS_THREAD = None

def dbus_thread_worker(loop):
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

# --- End D-Bus setup ---


# Registry for action handlers
ACTION_HANDLERS = {}
# Registry for long-running tasks
LONG_RUNNING_TASKS = []

def action_handler(name):
    """Decorator to register a function as an action handler."""
    def decorator(func):
        @functools.wraps(func)
        async def wrapper(*args, **kwargs):
            return await func(*args, **kwargs)
        ACTION_HANDLERS[name] = wrapper
        return wrapper
    return decorator

def long_running_task(func):
    """Decorator to register a function as a long-running task."""
    @functools.wraps(func)
    async def wrapper(*args, **kwargs):
        return await func(*args, **kwargs)
    LONG_RUNNING_TASKS.append(wrapper)
    return wrapper

async def write_json(writer, data):
    """Asynchronously write a JSON object to a stream writer."""
    writer.write(json.dumps(data).encode('utf-8') + b'\n')
    await writer.drain()

@action_handler("echo")
async def handle_echo(data, writer):
    """Echoes the input data back to the writer."""
    response = {
        "status": "success",
        "action": "echo",
        "original_payload": data
    }
    await write_json(writer, response)

@action_handler("reverse")
async def handle_reverse(data, writer):
    """Reverses the 'payload' string in the input data."""
    if "payload" in data and isinstance(data["payload"], str):
        response = {
            "status": "success",
            "action": "reverse",
            "reversed_payload": data["payload"][::-1]
        }
    else:
        response = {
            "status": "error",
            "action": "reverse",
            "message": "Missing or invalid 'payload' field for reverse action."
        }
    await write_json(writer, response)


def _format_speed(speed_bps):
    """Formats speed in bytes per second to a human-readable string with specific length constraints."""
    if speed_bps == 0:
        return "0.00", "B/s"

    value = speed_bps
    unit = "B/s"

    # Scale the value to appropriate units
    if value >= 1_000_000_000:
        value /= 1_000_000_000
        unit = "GB/s"
    elif value >= 1_000_000:
        value /= 1_000_000
        unit = "MB/s"
    elif value >= 1000:
        value /= 1000
        unit = "KB/s"

    # Apply specific formatting rules
    if value >= 100:
        formatted_value = f"{value:.0f}." # e.g., "123."
    elif value >= 10:
        formatted_value = f"{value:.1f}" # e.g., "12.3"
    elif value >= 1:
        formatted_value = f"{value:.2f}" # e.g., "1.23"
    else: # value < 1
        formatted_value = f"{value:.2f}" # e.g., "0.12"
    
    return formatted_value, unit


@long_running_task
async def net_usage_monitor(writer):
    """Monitors and reports network usage once per second."""
    last_net_io = psutil.net_io_counters()
    last_time = time.monotonic()

    while True:
        await asyncio.sleep(1)

        current_net_io = psutil.net_io_counters()
        current_time = time.monotonic()

        time_delta = current_time - last_time
        bytes_sent_delta = current_net_io.bytes_sent - last_net_io.bytes_sent
        bytes_recv_delta = current_net_io.bytes_recv - last_net_io.bytes_recv

        # Avoid division by zero on the first run or if time hasn't passed
        if time_delta == 0:
            continue

        upload_speed = bytes_sent_delta / time_delta
        download_speed = bytes_recv_delta / time_delta

        last_net_io = current_net_io
        last_time = current_time

        up_val, up_unit = _format_speed(upload_speed)
        down_val, down_unit = _format_speed(download_speed)

        response = {
            "net": {
                "up": up_val,
                "up_unit": up_unit,
                "down": down_val,
                "down_unit": down_unit,
            }
        }
        await write_json(writer, response)


@long_running_task
async def system_monitor(writer):
    """Monitors and reports CPU, memory, CPU temperature, and battery usage once per second."""
    # --- Temperature Sensor Initialization ---
    sensor_name, sensor_index, temp_min = None, None, 30.0
    temp_max = None # Will be set during discovery

    try:
        temps = psutil.sensors_temperatures()
        if temps:
            for name, entries in temps.items():
                # Prioritize common CPU temperature sensor names
                if "coretemp" in name or "k10temp" in name or "cpu_thermal" in name:
                    for i, entry in enumerate(entries):
                        # Ensure the sensor reports a current temperature
                        if entry.current is not None:
                            # Use entry.high if valid, otherwise default to 110.0
                            if entry.high is not None and entry.high > temp_min:
                                temp_max = entry.high
                            else:
                                temp_max = 110.0 # Default max temp if 'high' is not available or too low
                            sensor_name, sensor_index = name, i
                            break # Found a suitable entry for this sensor name
                if sensor_name: # Found a suitable sensor name and entry
                    break
    except Exception as e:
        print(f"Error initializing temperature sensor: {e}", file=sys.stderr)
        # If an error occurs during initialization, treat as if no sensor was found
        sensor_name = None

    if sensor_name is None: # Only print warning if NO sensor (even with default high) was found
        print(
            "Warning: No CPU temperature sensor found. Temp monitoring will be disabled.",
            file=sys.stderr,
        )

    # --- CPU Usage Initialization ---
    psutil.cpu_percent(interval=None)

    while True:
        await asyncio.sleep(1)

        # --- CPU and Memory ---
        cpu_percent = psutil.cpu_percent(interval=None) / 100.0
        mem_percent = psutil.virtual_memory().percent / 100.0
        
        response = {
            "cpu": round(cpu_percent, 2),
            "mem": round(mem_percent, 2),
        }

        # --- Temperature ---
        if sensor_name and temp_max is not None:
            try:
                current_temp_entry = psutil.sensors_temperatures().get(sensor_name)
                if current_temp_entry and sensor_index < len(current_temp_entry):
                    current_temp = current_temp_entry[sensor_index].current
                    if current_temp is not None:
                        # Normalize the temperature
                        # Avoid division by zero if temp_max somehow ended up <= temp_min
                        if (temp_max - temp_min) > 0:
                            normalized_temp = (current_temp - temp_min) / (temp_max - temp_min)
                            # Clamp the value between 0.0 and 1.0
                            clamped_temp = max(0.0, min(1.0, normalized_temp))
                            response["temp"] = round(clamped_temp, 2)
                        else:
                            # If for some reason temp_max is not greater than temp_min,
                            # report 0.0 or 1.0 based on current_temp relation to temp_min
                            response["temp"] = 0.0 if current_temp <= temp_min else 1.0
            except Exception as e:
                # Handle cases where sensor might become unavailable or error out mid-run
                print(f"Error reading temperature sensor at runtime: {e}", file=sys.stderr)
                sensor_name = None # Stop trying if it fails consistently

        # --- Battery ---
        try:
            battery = psutil.sensors_battery()
            if battery:
                bat_value = str(int(battery.percent))
                bat_approx = f"{(int(battery.percent) // 10) * 10:03d}"
                bat_charging = battery.power_plugged
                response["bat"] = {
                    "value": bat_value,
                    "approx": bat_approx,
                    "charging": bat_charging
                }
        except Exception as e:
            # If battery sensor fails, just omit the field.
            print(f"Error reading battery sensor: {e}", file=sys.stderr)

        await write_json(writer, response)


@long_running_task
async def power_profile_monitor(writer):
    """Monitors for power profile changes by listening to the DBUS_QUEUE."""
    while True:
        new_profile = await DBUS_QUEUE.get()
        await write_json(writer, {"power_profile": new_profile})
        DBUS_QUEUE.task_done()


def _set_power_profile_blocking(profile_to_set):
    """Blocking function to set power profile, intended to be run in a thread."""
    SERVICE = "net.hadess.PowerProfiles"
    INTERFACE = "org.freedesktop.DBus.Properties"
    OBJECT_PATH = "/net/hadess/PowerProfiles"
    
    bus = dbus.SystemBus()
    proxy = bus.get_object(SERVICE, OBJECT_PATH)
    props_interface = dbus.Interface(proxy, INTERFACE)
    props_interface.Set("net.hadess.PowerProfiles", "ActiveProfile", profile_to_set)

@action_handler("set_power_profile")
async def set_power_profile(data, writer):
    """Sets the power profile via D-Bus using a thread."""
    profile_to_set = data.get("profile")
    if not profile_to_set:
        await write_json(writer, {"status": "error", "message": "Missing 'profile' field."})
        return

    try:
        await asyncio.to_thread(_set_power_profile_blocking, profile_to_set)
        await write_json(writer, {"status": "success", "action": "set_power_profile", "profile": profile_to_set})
    except dbus.exceptions.DBusException as e:
        await write_json(writer, {"status": "error", "message": f"Failed to set power profile: {e}"})
    except Exception as e:
        await write_json(writer, {"status": "error", "message": f"An unexpected error occurred: {e}"})


async def read_stdin(reader, writer):
    """Reads and processes JSON lines from a stream reader."""
    while not reader.at_eof():
        line = await reader.readline()
        if not line:
            continue

        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue

        action = data.get("action")
        if action in ACTION_HANDLERS:
            # Schedule the handler to run without blocking the main loop
            asyncio.create_task(ACTION_HANDLERS[action](data, writer))
        else:
            error_response = {
                "status": "error",
                "message": f"Unknown action: '{action}'"
            }
            await write_json(writer, error_response)

async def main():
    """Main function to set up streams and run tasks."""
    loop = asyncio.get_running_loop()

    # Start the D-Bus worker thread
    global DBUS_THREAD
    DBUS_THREAD = threading.Thread(target=dbus_thread_worker, args=(loop,), daemon=True)
    DBUS_THREAD.start()

    # Create stream reader and writer for stdin/stdout
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)

    writer_transport, writer_protocol = await loop.connect_write_pipe(
        asyncio.streams.FlowControlMixin, sys.stdout
    )
    writer = asyncio.StreamWriter(writer_transport, writer_protocol, reader, loop)

    # Start long-running tasks from the registry
    background_tasks = [
        asyncio.create_task(task(writer)) for task in LONG_RUNNING_TASKS
    ]

    # Start the stdin reader task
    stdin_task = asyncio.create_task(read_stdin(reader, writer))

    # Run until the stdin reader is complete
    await stdin_task

    # Cleanly shut down the long-running tasks
    for task in background_tasks:
        task.cancel()
    await asyncio.gather(*background_tasks, return_exceptions=True)

    writer.close()
    await writer.wait_closed()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nExiting.", file=sys.stderr)
