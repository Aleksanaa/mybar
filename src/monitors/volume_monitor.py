import asyncio
import sys
from pulsectl_asyncio import PulseAsync
from ..utils import write_json
from ..tasks import long_running_task

VOLUME_QUEUE = asyncio.Queue()


async def volume_worker(loop):
    """Worker function to run the pulsectl-asyncio monitor."""
    try:
        async with PulseAsync("volume-monitor") as pulse:

            async def get_state():
                server_info = await pulse.server_info()
                default_sink_name = server_info.default_sink_name
                sinks = await pulse.sink_list()

                volume = 0
                muted = False
                sink_list = []
                current_sink_index = 0

                for i, sink in enumerate(sinks):
                    sink_list.append({"id": sink.name, "name": sink.description})
                    if sink.name == default_sink_name:
                        volume = sink.volume.value_flat
                        muted = sink.mute
                        current_sink_index = i

                return {
                    "volume": volume,
                    "muted": muted,
                    "sinks": sink_list,
                    "current_sink": current_sink_index,
                }

            # Get initial state
            initial_state = await get_state()
            loop.call_soon_threadsafe(VOLUME_QUEUE.put_nowait, initial_state)

            async for event in pulse.subscribe_events("sink", "server"):
                if event.t in ["change", "new", "remove"]:
                    state = await get_state()
                    loop.call_soon_threadsafe(VOLUME_QUEUE.put_nowait, state)
    except Exception as e:
        print(f"Error in volume thread: {e}", file=sys.stderr)


def volume_thread_worker(loop):
    asyncio.run(volume_worker(loop))


@long_running_task
async def volume_monitor(writer):
    """Monitors for volume changes by listening to the VOLUME_QUEUE."""
    while True:
        data = await VOLUME_QUEUE.get()
        volume = data["volume"]
        muted = data["muted"]
        sinks = data["sinks"]
        current_sink = data["current_sink"]

        approx = "medium"
        if muted:
            approx = "muted"
        elif volume > 0.66:
            approx = "high"
        elif volume < 0.33:
            approx = "low"

        await write_json(
            writer,
            {
                "volume": {
                    "value": round(volume, 2),
                    "approx": approx,
                    "sinks": sinks,
                    "current_sink": current_sink,
                }
            },
        )
        VOLUME_QUEUE.task_done()
