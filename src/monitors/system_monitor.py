import asyncio
import os
import psutil
from ..utils import write_json
from ..tasks import long_running_task


def get_cpu_times():
    """Reads /proc/stat and returns (user, nice, system, idle, iowait, irq, softirq, steal) for total and each core."""
    try:
        with open("/proc/stat", "r") as f:
            cpu_data = []
            for line in f:
                if line.startswith("cpu"):
                    parts = line.split()
                    # Skip 'cpu ' and take the first 8 numeric values
                    times = [int(x) for x in parts[1:9]]
                    cpu_data.append(times)
                else:
                    # CPU lines are always at the top, so we can stop early
                    break
            return cpu_data
    except Exception:
        return None


def calculate_cpu_percent(old_times, new_times):
    """Calculates CPU usage percentage between two /proc/stat reads."""
    results = []
    for old, new in zip(old_times, new_times):
        old_total = sum(old)
        new_total = sum(new)
        total_diff = new_total - old_total

        # Idle time is the 4th value (index 3) + iowait (index 4)
        old_idle = old[3] + old[4]
        new_idle = new[3] + new[4]
        idle_diff = new_idle - old_idle

        if total_diff > 0:
            results.append(max(0.0, min(1.0, (total_diff - idle_diff) / total_diff)))
        else:
            results.append(0.0)
    return results


def get_mem_info():
    """Reads /proc/meminfo and returns a simplified stats dictionary."""
    try:
        mem = {}
        needed = {
            "MemTotal",
            "MemAvailable",
            "MemFree",
            "Cached",
            "SwapTotal",
            "SwapFree",
        }
        found = 0
        with open("/proc/meminfo", "r") as f:
            for line in f:
                parts = line.split(":")
                if len(parts) == 2:
                    name = parts[0].strip()
                    if name in needed:
                        value = int(parts[1].split()[0])
                        mem[name] = value
                        found += 1
                        if found == len(needed):
                            break

        total = mem.get("MemTotal", 1)
        available = mem.get(
            "MemAvailable", mem.get("MemFree", 0) + mem.get("Cached", 0)
        )
        used_percent = (total - available) / total

        swap_total = mem.get("SwapTotal", 0)
        swap_free = mem.get("SwapFree", 0)
        swap_percent = (swap_total - swap_free) / max(1, swap_total)

        return round(used_percent, 2), round(swap_percent, 2)
    except Exception:
        return 0.0, 0.0


@long_running_task
async def system_monitor(writer):
    """Monitors and reports CPU, memory, and temperature with high-efficiency direct reads."""
    # --- CPU Frequency Discovery ---
    cpu_freq_paths = []
    max_freq = 0.0
    try:
        for d in os.listdir("/sys/devices/system/cpu/"):
            if d.startswith("cpu") and d[3:].isdigit():
                path = f"/sys/devices/system/cpu/{d}/cpufreq/scaling_cur_freq"
                if os.path.exists(path):
                    cpu_freq_paths.append(path)

        if cpu_freq_paths:
            # Assume max_freq is the same for all cores or at least representative from cpu0
            with open(
                "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq", "r"
            ) as f:
                max_freq = round(int(f.read().strip()) / 1000000.0, 2)
    except Exception:
        pass

    # --- Temperature Sensor Discovery ---
    sensor_name, sensor_index, temp_min = None, None, 30.0
    temp_max = 100.0

    try:
        temps = psutil.sensors_temperatures()
        if temps:
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
    except Exception:
        pass

    # Find the specific hwmon file for the discovered sensor
    thermal_file = None
    if sensor_name:
        try:
            for hwmon in os.listdir("/sys/class/hwmon/"):
                try:
                    with open(f"/sys/class/hwmon/{hwmon}/name", "r") as f:
                        if f.read().strip() == sensor_name:
                            thermal_file = (
                                f"/sys/class/hwmon/{hwmon}/temp{sensor_index + 1}_input"
                            )
                            if os.path.exists(thermal_file):
                                break
                except Exception:
                    continue
        except Exception:
            thermal_file = None

    # --- Baseline CPU ---
    last_cpu_times = get_cpu_times()
    last_response = None

    while True:
        await asyncio.sleep(1)

        # --- CPU Usage (Direct) ---
        current_cpu_times = get_cpu_times()
        if last_cpu_times and current_cpu_times:
            percents = calculate_cpu_percent(last_cpu_times, current_cpu_times)
            cpu_total = percents[0]
            # OPTIMIZATION: Round to 1 decimal place (0.1%) to reduce noise
            cpus = [round(p, 1) for p in percents[1:]]
            last_cpu_times = current_cpu_times
        else:
            cpu_total, cpus = 0.0, []
            last_cpu_times = current_cpu_times

        # --- Memory (Direct) ---
        mem_used, swap_used = get_mem_info()

        # --- CPU Freq (Efficient cached paths) ---
        freq_data = {"current": 0.0, "max": max_freq}
        try:
            if cpu_freq_paths:
                freqs = []
                for path in cpu_freq_paths:
                    try:
                        with open(path, "r") as f:
                            freqs.append(int(f.read().strip()))
                    except Exception:
                        continue
                if freqs:
                    freq_data["current"] = round(
                        (sum(freqs) / len(freqs)) / 1000000.0, 1
                    )
            else:
                raise Exception("No paths")
        except Exception:
            cpu_freq = psutil.cpu_freq()
            if cpu_freq:
                freq_data = {
                    "current": round(cpu_freq.current / 1000.0, 1),
                    "max": round((cpu_freq.max or cpu_freq.current) / 1000.0, 1),
                }

        response = {
            "cpu": round(cpu_total, 1),
            "cpus": cpus,
            "mem": round(mem_used, 2),
            "swap": round(swap_used, 2),
            "cpu_freq": freq_data,
            "temp": 0.0,
            "temp_c": 0,
        }

        # --- Temperature (Direct) ---
        if thermal_file:
            try:
                with open(thermal_file, "r") as f:
                    current_temp = int(f.read().strip()) / 1000.0
                    response["temp_c"] = int(current_temp)
                    norm = (current_temp - temp_min) / (temp_max - temp_min)
                    response["temp"] = round(max(0.0, min(1.0, norm)), 2)
            except Exception:
                pass

        if response != last_response:
            await write_json(writer, response)
            last_response = response
