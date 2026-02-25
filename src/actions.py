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

import pyudev
import dbus

def _set_brightness_blocking(percent):
    """Blocking function to set brightness via D-Bus."""
    context = pyudev.Context()
    devices = list(context.list_devices(subsystem='backlight'))
    if not devices:
        return
    device = devices[0]
    
    try:
        max_brightness = device.attributes.asint('max_brightness')
        new_brightness = int(max_brightness * percent)

        bus = dbus.SystemBus()
        proxy = bus.get_object("org.freedesktop.login1", "/org/freedesktop/login1/session/auto")
        session_interface = dbus.Interface(proxy, "org.freedesktop.login1.Session")
        session_interface.SetBrightness("backlight", device.sys_name, dbus.UInt32(new_brightness))
    except Exception as e:
        print(f"Error setting brightness: {e}", file=sys.stderr)

@action_handler("set_brightness")
async def set_brightness(data, writer):
    """Sets the screen brightness."""
    percent = data.get("value")
    if percent is None:
        print("Error: Missing 'value' field in set_brightness", file=sys.stderr)
        return
    
    # Ensure percent is between 0 and 1
    percent = max(0.0, min(1.0, float(percent)))
    
    try:
        await asyncio.to_thread(_set_brightness_blocking, percent)
    except Exception as e:
        print(f"Error: An unexpected error occurred setting brightness: {e}", file=sys.stderr)

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

def _toggle_swayidle_blocking():
    """Blocking function to toggle swayidle.service, intended to be run in a thread."""
    bus = dbus.SessionBus()
    systemd = bus.get_object("org.freedesktop.systemd1", "/org/freedesktop/systemd1")
    manager = dbus.Interface(systemd, "org.freedesktop.systemd1.Manager")

    try:
        unit_path = manager.GetUnit("swayidle.service")
        unit_proxy = bus.get_object("org.freedesktop.systemd1", unit_path)
        props_interface = dbus.Interface(unit_proxy, "org.freedesktop.DBus.Properties")
        current_state = props_interface.Get("org.freedesktop.systemd1.Unit", "ActiveState")

        if current_state == "active":
            manager.StopUnit("swayidle.service", "replace")
        else:
            manager.StartUnit("swayidle.service", "replace")
    except dbus.exceptions.DBusException as e:
        print(f"Error toggling swayidle.service: {e}", file=sys.stderr)

@action_handler("toggle_swayidle")
async def toggle_swayidle(data, writer):
    """Toggles the swayidle.service using D-Bus."""
    try:
        await asyncio.to_thread(_toggle_swayidle_blocking)
    except Exception as e:
        print(f"Error: An unexpected error occurred toggling swayidle: {e}", file=sys.stderr)
