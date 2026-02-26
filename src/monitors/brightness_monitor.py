import asyncio
import sys
import pyudev
from ..utils import write_json
from ..tasks import long_running_task

BRIGHTNESS_QUEUE = asyncio.Queue()


def brightness_thread_worker(loop):
    """Worker function to run the pyudev monitor."""
    try:
        context = pyudev.Context()
        monitor = pyudev.Monitor.from_netlink(context)
        monitor.filter_by(subsystem="backlight")

        # Get initial brightness
        # We wrap this in a separate try/except because the device might not be there
        # at startup, but the monitor should still run.
        try:
            for device in context.list_devices(subsystem="backlight"):
                if "backlight" in device.subsystem:
                    brightness = device.attributes.asint("brightness")
                    max_brightness = device.attributes.asint("max_brightness")
                    if max_brightness > 0:
                        percent = brightness / max_brightness
                        loop.call_soon_threadsafe(BRIGHTNESS_QUEUE.put_nowait, percent)
        except Exception as e:
            print(f"Could not get initial brightness: {e}", file=sys.stderr)

        for device in iter(monitor.poll, None):
            if device.action == "change":
                try:
                    brightness = device.attributes.asint("brightness")
                    max_brightness = device.attributes.asint("max_brightness")
                    if max_brightness > 0:
                        percent = brightness / max_brightness
                        loop.call_soon_threadsafe(BRIGHTNESS_QUEUE.put_nowait, percent)
                except (KeyError, ValueError):
                    # This can happen if attributes are not immediately available.
                    pass
    except Exception as e:
        print(f"Error in brightness thread: {e}", file=sys.stderr)


@long_running_task
async def brightness_monitor(writer):
    """Monitors for brightness changes by listening to the BRIGHTNESS_QUEUE."""
    while True:
        percent = await BRIGHTNESS_QUEUE.get()
        approx = "medium"
        if percent > 0.66:
            approx = "high"
        elif percent < 0.33:
            approx = "low"
        await write_json(
            writer, {"brightness": {"value": round(percent, 2), "approx": approx}}
        )
        BRIGHTNESS_QUEUE.task_done()
