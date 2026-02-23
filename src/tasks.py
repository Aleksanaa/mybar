import functools

LONG_RUNNING_TASKS = []

def long_running_task(func):
    """Decorator to register a a long-running task."""
    @functools.wraps(func)
    async def wrapper(*args, **kwargs):
        return await func(*args, **kwargs)
    LONG_RUNNING_TASKS.append(wrapper)
    return wrapper
