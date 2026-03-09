import json
import asyncio

# Global state for batching
_pending_updates = {}
_batch_lock = asyncio.Lock()
_flush_task = None


def _recursive_update(target, source):
    """Deep merge source dict into target dict."""
    for key, value in source.items():
        if isinstance(value, dict) and key in target and isinstance(target[key], dict):
            _recursive_update(target[key], value)
        else:
            target[key] = value


async def _flush_updates(writer, interval):
    """Internal task to flush pending updates after a delay."""
    global _flush_task
    await asyncio.sleep(interval)
    async with _batch_lock:
        if _pending_updates:
            try:
                writer.write(json.dumps(_pending_updates).encode("utf-8") + b"\n")
                await writer.drain()
            except Exception:
                pass
            _pending_updates.clear()
        _flush_task = None


async def write_json(writer, data):
    """
    Asynchronously write a JSON object to a stream writer with batching.
    Updates within a 50ms window are merged into a single message to reduce
    event loop wakeups and QML re-evaluations.
    """
    global _flush_task

    # Check if we are running in the main loop or a thread
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        # Fallback for when called outside of an active loop (shouldn't happen with current architecture)
        writer.write(json.dumps(data).encode("utf-8") + b"\n")
        await writer.drain()
        return

    async with _batch_lock:
        _recursive_update(_pending_updates, data)
        if _flush_task is None or _flush_task.done():
            _flush_task = loop.create_task(_flush_updates(writer, 0.05))
