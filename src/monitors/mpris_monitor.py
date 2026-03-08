import asyncio
import sys
import dbus
from dbus.mainloop.glib import DBusGMainLoop
from ..utils import write_json
from ..tasks import long_running_task

MPRIS_QUEUE = asyncio.Queue()


def get_mpris_metadata(proxy):
    try:
        props = dbus.Interface(proxy, "org.freedesktop.DBus.Properties")
        metadata = props.Get("org.mpris.MediaPlayer2.Player", "Metadata")
        status = props.Get("org.mpris.MediaPlayer2.Player", "PlaybackStatus")

        title = str(metadata.get("xesam:title", "Unknown"))
        artist = ", ".join([str(a) for a in metadata.get("xesam:artist", ["Unknown"])])
        album = str(metadata.get("xesam:album", ""))
        art_url = str(metadata.get("mpris:artUrl", ""))

        return {
            "title": title,
            "artist": artist,
            "album": album,
            "art_url": art_url,
            "status": str(status),
        }
    except Exception as e:
        return None


def mpris_worker(loop):
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    def on_properties_changed(
        interface, changed_properties, invalidated_properties, path=None, bus_name=None
    ):
        if interface == "org.mpris.MediaPlayer2.Player":
            # We don't have the proxy here easily, so we just signal a refresh is needed or send the changed props
            # Simplest: find the player again and get all data
            update_all_players()

    def update_all_players():
        players = [
            name
            for name in bus.list_names()
            if name.startswith("org.mpris.MediaPlayer2.")
        ]
        if not players:
            loop.call_soon_threadsafe(MPRIS_QUEUE.put_nowait, {"players": {}})
            return

        all_players_data = {}
        for player in players:
            try:
                proxy = bus.get_object(player, "/org/mpris/MediaPlayer2")
                data = get_mpris_metadata(proxy)
                if data:
                    all_players_data[player] = data
            except:
                continue

        loop.call_soon_threadsafe(MPRIS_QUEUE.put_nowait, {"players": all_players_data})

    bus.add_signal_receiver(
        on_properties_changed,
        dbus_interface="org.freedesktop.DBus.Properties",
        signal_name="PropertiesChanged",
        path="/org/mpris/MediaPlayer2",
        sender_keyword="bus_name",
    )

    # Also watch for new/removed players
    def on_name_owner_changed(name, old_owner, new_owner):
        if name.startswith("org.mpris.MediaPlayer2."):
            update_all_players()

    bus.add_signal_receiver(
        on_name_owner_changed,
        dbus_interface="org.freedesktop.DBus",
        signal_name="NameOwnerChanged",
    )

    update_all_players()
    # No need for a loop here as signals are handled by the main loop of the thread if it had one,
    # but dbus-python with DBusGMainLoop needs a GLib main loop.
    import gi
    from gi.repository import GLib

    ml = GLib.MainLoop()
    ml.run()


def mpris_thread_worker(loop):
    try:
        mpris_worker(loop)
    except Exception as e:
        print(f"Error in MPRIS thread: {e}", file=sys.stderr)


@long_running_task
async def mpris_monitor(writer):
    while True:
        data = await MPRIS_QUEUE.get()
        # For simplicity, just send the first active player found
        players = data.get("players", {})
        active_player = None
        if players:
            # Prefer playing ones
            for name, p in players.items():
                if p["status"] == "Playing":
                    active_player = p
                    active_player["bus_name"] = name
                    break
            if not active_player:
                # Just take the first one
                name = list(players.keys())[0]
                active_player = players[name]
                active_player["bus_name"] = name

        await write_json(writer, {"mpris": active_player})
        MPRIS_QUEUE.task_done()
