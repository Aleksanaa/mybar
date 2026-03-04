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
    temp_max = None  # Will be set during discovery

    try:
        temps = psutil.sensors_temperatures()
        if temps:
            # First pass: look for known CPU sensors
            for name, entries in temps.items():
                if any(
                    x in name.lower()
                    for x in ["coretemp", "k10temp", "cpu_thermal", "zenpower"]
                ):
                    for i, entry in enumerate(entries):
                        if entry.current is not None:
                            temp_max = (
                                entry.high
                                if (entry.high and entry.high > temp_min)
                                else 100.0
                            )
                            sensor_name, sensor_index = name, i
                            break
                if sensor_name:
                    break

            # Second pass: fallback to any sensor with a reasonable value if none found
            if not sensor_name:
                for name, entries in temps.items():
                    for i, entry in enumerate(entries):
                        if entry.current is not None and 20.0 < entry.current < 110.0:
                            temp_max = (
                                entry.high
                                if (entry.high and entry.high > temp_min)
                                else 100.0
                            )
                            sensor_name, sensor_index = name, i
                            break
                    if sensor_name:
                        break
    except Exception as e:
        print(f"Error initializing temperature sensor: {e}", file=sys.stderr)
        sensor_name = None

    if sensor_name is None:
        print("Warning: No suitable temperature sensor found.", file=sys.stderr)

    # --- CPU Usage Initialization ---
    psutil.cpu_percent(interval=None)

    while True:
        await asyncio.sleep(1)

        # --- CPU and Memory ---
        cpu_percent = psutil.cpu_percent(interval=None) / 100.0
        cpu_percents = [
            round(p / 100.0, 2) for p in psutil.cpu_percent(interval=None, percpu=True)
        ]
        mem = psutil.virtual_memory()
        swap = psutil.swap_memory()
        cpu_freq = psutil.cpu_freq()

        response = {
            "cpu": round(cpu_percent, 2),
            "cpus": cpu_percents,
            "mem": round(mem.percent / 100.0, 2),
            "swap": round(swap.percent / 100.0, 2),
            "temp": 0.0,
            "temp_c": 0,
        }

        if cpu_freq:
            response["cpu_freq"] = {
                "current": round(cpu_freq.current / 1000.0, 2),
                "max": round((cpu_freq.max or cpu_freq.current) / 1000.0, 2),
            }
        else:
            response["cpu_freq"] = {"current": 0.0, "max": 0.0}

        # --- Temperature ---
        if sensor_name:
            try:
                current_temp_entry = psutil.sensors_temperatures().get(sensor_name)
                if current_temp_entry and sensor_index < len(current_temp_entry):
                    current_temp = current_temp_entry[sensor_index].current
                    if current_temp is not None:
                        response["temp_c"] = int(current_temp)
                        if (temp_max - temp_min) > 0:
                            normalized_temp = (current_temp - temp_min) / (
                                temp_max - temp_min
                            )
                            response["temp"] = round(
                                max(0.0, min(1.0, normalized_temp)), 2
                            )
                        else:
                            response["temp"] = 0.0 if current_temp <= temp_min else 1.0
            except Exception as e:
                print(f"Error reading temperature sensor: {e}", file=sys.stderr)
                sensor_name = None

        await write_json(writer, response)
