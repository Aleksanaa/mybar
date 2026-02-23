import asyncio
import time
import psutil
from ..utils import write_json, _format_speed
from ..tasks import long_running_task

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
