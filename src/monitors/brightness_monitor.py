import asyncio
import sys
import pyudev
from ..utils import write_json


def brightness_thread_worker(loop, writer):
    """Worker function to run the pyudev monitor."""

    def send_update(p):
        approx = "medium"
        if p > 0.66:
            approx = "high"
        elif p < 0.33:
            approx = "low"
        asyncio.run_coroutine_threadsafe(
            write_json(
                writer, {"brightness": {"value": round(p, 2), "approx": approx}}
            ),
            loop,
        )

    try:
        context = pyudev.Context()
        monitor = pyudev.Monitor.from_netlink(context)
        monitor.filter_by(subsystem="backlight")

        # Get initial brightness
        try:
            for device in context.list_devices(subsystem="backlight"):
                if "backlight" in device.subsystem:
                    brightness = device.attributes.asint("brightness")
                    max_brightness = device.attributes.asint("max_brightness")
                    if max_brightness > 0:
                        send_update(brightness / max_brightness)
        except Exception as e:
            print(f"Could not get initial brightness: {e}", file=sys.stderr)

        for device in iter(monitor.poll, None):
            if device.action == "change":
                try:
                    brightness = device.attributes.asint("brightness")
                    max_brightness = device.attributes.asint("max_brightness")
                    if max_brightness > 0:
                        send_update(brightness / max_brightness)
                except (KeyError, ValueError):
                    pass
    except Exception as e:
        print(f"Error in brightness thread: {e}", file=sys.stderr)
