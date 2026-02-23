import asyncio
import functools
import sys
import dbus
from .niri import NiriConnection

# Registry for action handlers
ACTION_HANDLERS = {}

def action_handler(name):
    """Decorator to register a function as an action handler."""
    def decorator(func):
        @functools.wraps(func)
        async def wrapper(*args, **kwargs):
            return await func(*args, **kwargs)
        ACTION_HANDLERS[name] = wrapper
        return wrapper
    return decorator

def _set_power_profile_blocking(profile_to_set):
    """Blocking function to set power profile, intended to be run in a thread."""
    SERVICE = "net.hadess.PowerProfiles"
    INTERFACE = "org.freedesktop.DBus.Properties"
    OBJECT_PATH = "/net/hadess/PowerProfiles"
    
    bus = dbus.SystemBus()
    proxy = bus.get_object(SERVICE, OBJECT_PATH)
    props_interface = dbus.Interface(proxy, INTERFACE)
    props_interface.Set("net.hadess.PowerProfiles", "ActiveProfile", profile_to_set)

@action_handler("set_power_profile")
async def set_power_profile(data, writer):
    """Sets the power profile via D-Bus using a thread."""
    profile_to_set = data.get("profile")
    if not profile_to_set:
        print("Error: Missing 'profile' field in set_power_profile", file=sys.stderr)
        return

    try:
        await asyncio.to_thread(_set_power_profile_blocking, profile_to_set)
    except dbus.exceptions.DBusException as e:
        print(f"Error: Failed to set power profile: {e}", file=sys.stderr)
    except Exception as e:
        print(f"Error: An unexpected error occurred setting power profile: {e}", file=sys.stderr)

@action_handler("close-window")
async def handle_close_window(data, writer):
    """Closes the currently focused window."""
    await NiriConnection().send({"Action": {"CloseWindow": {"id": None}}})

@action_handler("maximize-column")
async def handle_maximize_column(data, writer):
    """Maximizes the currently focused column."""
    await NiriConnection().send({"Action": {"MaximizeColumn": {}}})

@action_handler("toggle-fullscreen")
async def handle_toggle_fullscreen(data, writer):
    """Toggles fullscreen mode for the currently focused window."""
    await NiriConnection().send({"Action": {"FullscreenWindow": {"id": None}}})
