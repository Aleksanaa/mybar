#!/usr/bin/env python

import sys
import asyncio
import json
import threading

from src.actions import ACTION_HANDLERS
from src.tasks import LONG_RUNNING_TASKS
from src.utils import write_json

# Import monitors to register tasks
import src.monitors.net_monitor  # noqa: F401
import src.monitors.system_monitor  # noqa: F401
import src.monitors.audio_visualizer  # noqa: F401
import src.monitors.niri_monitor  # noqa: F401

from src.monitors.power_profile_monitor import power_profiles_dbus_worker
from src.monitors.swayidle_monitor import swayidle_dbus_worker
from src.monitors.brightness_monitor import brightness_thread_worker
from src.monitors.volume_monitor import volume_thread_worker
from src.monitors.upower_monitor import upower_dbus_worker
from src.monitors.mpris_monitor import mpris_thread_worker
from src.monitors.notification_monitor import notification_thread_worker


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
                "message": f"Unknown action: '{action}'",
            }
            await write_json(writer, error_response)


async def main():
    """Main function to set up streams and run tasks."""
    loop = asyncio.get_running_loop()

    # Create stream reader and writer for stdin/stdout
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(
        lambda: asyncio.StreamReaderProtocol(reader), sys.stdin
    )

    writer_transport, writer_protocol = await loop.connect_write_pipe(
        asyncio.streams.FlowControlMixin, sys.stdout
    )
    writer = asyncio.StreamWriter(writer_transport, writer_protocol, reader, loop)

    # Worker threads to start
    workers = [
        power_profiles_dbus_worker,
        swayidle_dbus_worker,
        upower_dbus_worker,
        brightness_thread_worker,
        volume_thread_worker,
        mpris_thread_worker,
        notification_thread_worker,
    ]

    for worker in workers:
        threading.Thread(target=worker, args=(loop, writer), daemon=True).start()

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
