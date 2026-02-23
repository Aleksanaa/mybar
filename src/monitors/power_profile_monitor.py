import asyncio
from ..utils import write_json
from .dbus_monitor import DBUS_QUEUE
from ..tasks import long_running_task

@long_running_task
async def power_profile_monitor(writer):
    """Monitors for power profile changes by listening to the DBUS_QUEUE."""
    while True:
        new_profile = await DBUS_QUEUE.get()
        await write_json(writer, {"power_profile": new_profile})
        DBUS_QUEUE.task_done()
