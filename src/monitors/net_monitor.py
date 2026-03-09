import asyncio
import time
import psutil
from ..utils import write_json
from ..tasks import long_running_task


def _format_speed(speed_bps):
    """Formats speed in bytes per second to a human-readable string with specific length constraints."""
    if speed_bps == 0:
        return "0.00", "B/s"

    value = speed_bps
    unit = "B/s"

    # Scale the value to appropriate units
    if value >= 100_000_000:
        value /= 1_000_000_000
        unit = "GB/s"
    elif value >= 100_000:
        value /= 1_000_000
        unit = "MB/s"
    elif value >= 100:
        value /= 1000
        unit = "KB/s"

    # Apply specific formatting rules
    if value >= 100:
        formatted_value = f"{value:.0f}"
    elif value >= 10:
        formatted_value = f"{value:.1f}"
    elif value >= 1:
        formatted_value = f"{value:.2f}"
    else:  # value < 1
        formatted_value = f"{value:.2f}"

    return formatted_value, unit


@long_running_task
async def net_usage_monitor(writer):
    """Monitors and reports network usage once per second."""
    last_net_io = psutil.net_io_counters()
    last_time = time.monotonic()
    last_response = None

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
                "up_raw": round(upload_speed, 1),
                "down": down_val,
                "down_unit": down_unit,
                "down_raw": round(download_speed, 1),
            }
        }

        if response != last_response:
            await write_json(writer, response)
            last_response = response
