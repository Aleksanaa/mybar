import asyncio
import sys
from pulsectl_asyncio import PulseAsync
from ..utils import write_json


async def volume_worker(loop, writer):
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

                approx = "medium"
                if muted:
                    approx = "muted"
                elif volume > 0.66:
                    approx = "high"
                elif volume < 0.33:
                    approx = "low"

                return {
                    "volume": {
                        "value": round(volume, 2),
                        "approx": approx,
                        "sinks": sink_list,
                        "current_sink": current_sink_index,
                    }
                }

            # Get initial state
            initial_state = await get_state()
            asyncio.run_coroutine_threadsafe(write_json(writer, initial_state), loop)

            async for event in pulse.subscribe_events("sink", "server"):
                if event.t in ["change", "new", "remove"]:
                    state = await get_state()
                    asyncio.run_coroutine_threadsafe(write_json(writer, state), loop)
    except Exception as e:
        print(f"Error in volume thread: {e}", file=sys.stderr)


def volume_thread_worker(loop, writer):
    asyncio.run(volume_worker(loop, writer))
