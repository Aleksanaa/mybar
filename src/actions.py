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
from pulsectl_asyncio import PulseAsync


def _set_brightness_blocking(percent):
    """Blocking function to set brightness via D-Bus."""
    context = pyudev.Context()
    devices = list(context.list_devices(subsystem="backlight"))
    if not devices:
        return
    device = devices[0]

    try:
        max_brightness = device.attributes.asint("max_brightness")
        new_brightness = int(max_brightness * percent)

        bus = dbus.SystemBus()
        proxy = bus.get_object(
            "org.freedesktop.login1", "/org/freedesktop/login1/session/auto"
        )
        session_interface = dbus.Interface(proxy, "org.freedesktop.login1.Session")
        session_interface.SetBrightness(
            "backlight", device.sys_name, dbus.UInt32(new_brightness)
        )
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
        print(
            f"Error: An unexpected error occurred setting brightness: {e}",
            file=sys.stderr,
        )


pulse_setter = None


@action_handler("set_volume")
async def set_volume(data, writer):
    """Sets the system volume."""
    global pulse_setter
    percent = data.get("value")
    if percent is None:
        print("Error: Missing 'value' field in set_volume", file=sys.stderr)
        return

    # Ensure percent is between 0 and 1
    percent = max(0.0, min(1.0, float(percent)))

    try:
        if pulse_setter is None:
            pulse_setter = PulseAsync("volume-setter")
            await pulse_setter.connect()

        server_info = await pulse_setter.server_info()
        default_sink_name = server_info.default_sink_name
        sinks = await pulse_setter.sink_list()
        for sink in sinks:
            if sink.name == default_sink_name:
                await pulse_setter.volume_set_all_chans(sink, percent)
                break
    except Exception as e:
        print(f"Error setting volume: {e}", file=sys.stderr)
        pulse_setter = None


@action_handler("toggle_mute")
async def toggle_mute(data, writer):
    """Toggles the mute state of the default audio sink."""
    global pulse_setter
    try:
        if pulse_setter is None:
            pulse_setter = PulseAsync("volume-setter")
            await pulse_setter.connect()

        server_info = await pulse_setter.server_info()
        default_sink_name = server_info.default_sink_name
        sinks = await pulse_setter.sink_list()
        for sink in sinks:
            if sink.name == default_sink_name:
                await pulse_setter.mute(sink, not sink.mute)
                break
    except Exception as e:
        print(f"Error toggling mute: {e}", file=sys.stderr)
        pulse_setter = None


@action_handler("set_sink")
async def set_sink(data, writer):
    """Sets the default audio sink."""
    global pulse_setter
    sink_id = data.get("sink_id")
    if not sink_id:
        print("Error: Missing 'sink_id' field in set_sink", file=sys.stderr)
        return

    try:
        if pulse_setter is None:
            pulse_setter = PulseAsync("volume-setter")
            await pulse_setter.connect()

        sinks = await pulse_setter.sink_list()
        for sink in sinks:
            if sink.name == sink_id:
                await pulse_setter.default_set(sink)
                break
    except Exception as e:
        print(f"Error setting sink: {e}", file=sys.stderr)
        pulse_setter = None


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
        print(
            f"Error: An unexpected error occurred setting power profile: {e}",
            file=sys.stderr,
        )


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
        current_state = props_interface.Get(
            "org.freedesktop.systemd1.Unit", "ActiveState"
        )

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
        print(
            f"Error: An unexpected error occurred toggling swayidle: {e}",
            file=sys.stderr,
        )


_wtype_process = None
_niri_listener_task = None


async def _niri_window_focus_listener():
    global _wtype_process, _niri_listener_task
    try:
        async for event in NiriConnection().stream_events():
            if "WindowFocusChanged" in event:
                if _wtype_process and _wtype_process.returncode is None:
                    _wtype_process.terminate()
                    try:
                        await _wtype_process.wait()
                    except ProcessLookupError:
                        pass
                _wtype_process = None
                break
    except asyncio.CancelledError:
        pass
    finally:
        _niri_listener_task = None


@action_handler("toggle_super")
async def toggle_super(data, writer):
    """Toggles the SUPER key state using wtype and listens for Niri focus changes."""
    global _wtype_process, _niri_listener_task

    if _wtype_process and _wtype_process.returncode is None:
        # If running, kill it to release the key
        _wtype_process.terminate()
        try:
            await _wtype_process.wait()
        except ProcessLookupError:
            pass
        _wtype_process = None

        if _niri_listener_task and not _niri_listener_task.done():
            _niri_listener_task.cancel()
        _niri_listener_task = None
        print("SUPER key released (wtype killed).", file=sys.stderr)
    else:
        # If not running, start wtype to hold the key
        try:
            _wtype_process = await asyncio.create_subprocess_exec(
                "wtype", "-M", "logo", "-s", "100000", "-m", "logo"
            )
            print("SUPER key pressed via wtype.", file=sys.stderr)

            # Start listener to kill wtype on focus change
            if _niri_listener_task and not _niri_listener_task.done():
                _niri_listener_task.cancel()
            _niri_listener_task = asyncio.create_task(_niri_window_focus_listener())
        except Exception as e:
            print(f"Error starting wtype: {e}", file=sys.stderr)
