import asyncio
import sys
from pulsectl_asyncio import PulseAsync
from ..utils import write_json
from ..tasks import long_running_task

VOLUME_QUEUE = asyncio.Queue()

async def volume_worker(loop):
    """Worker function to run the pulsectl-asyncio monitor."""
    try:
        async with PulseAsync('volume-monitor') as pulse:
            # Get initial volume
            server_info = await pulse.server_info()
            default_sink_name = server_info.default_sink_name
            sinks = await pulse.sink_list()
            for sink in sinks:
                if sink.name == default_sink_name:
                    volume = sink.volume.value_flat
                    loop.call_soon_threadsafe(VOLUME_QUEUE.put_nowait, {'volume': volume, 'muted': sink.mute})
                    break

            async for event in pulse.subscribe_events('sink'):
                if event.t == 'change':
                    sinks = await pulse.sink_list()
                    for sink in sinks:
                        if sink.name == default_sink_name:
                            volume = sink.volume.value_flat
                            loop.call_soon_threadsafe(VOLUME_QUEUE.put_nowait, {'volume': volume, 'muted': sink.mute})
                            break
    except Exception as e:
        print(f"Error in volume thread: {e}", file=sys.stderr)


def volume_thread_worker(loop):
    asyncio.run(volume_worker(loop))

@long_running_task
async def volume_monitor(writer):
    """Monitors for volume changes by listening to the VOLUME_QUEUE."""
    while True:
        data = await VOLUME_QUEUE.get()
        volume = data['volume']
        muted = data['muted']
        
        approx = "medium"
        if muted:
            approx = "muted"
        elif volume > 0.66:
            approx = "high"
        elif volume < 0.33:
            approx = "low"
            
        await write_json(writer, {"volume": {"value": round(volume, 2), "approx": approx}})
        VOLUME_QUEUE.task_done()