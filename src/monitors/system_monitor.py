import asyncio
import sys
import psutil
from ..utils import write_json
from ..tasks import long_running_task

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
