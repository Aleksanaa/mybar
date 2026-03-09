import asyncio
import sys
import dbus
from dbus.mainloop.glib import DBusGMainLoop
from ..utils import write_json
from ..tasks import long_running_task
from .audio_visualizer import PLAYBACK_EVENT

MPRIS_QUEUE = asyncio.Queue()


def parse_mpris_metadata(metadata, status):
    try:
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
    except Exception:
        return None


def mpris_worker(loop):
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    players_state = {}
    player_proxies = {}

    def fetch_player_data(bus_name):
        try:
            if bus_name not in player_proxies:
                proxy = bus.get_object(bus_name, "/org/mpris/MediaPlayer2")
                props = dbus.Interface(proxy, "org.freedesktop.DBus.Properties")
                player_proxies[bus_name] = props
            else:
                props = player_proxies[bus_name]

            metadata = props.Get("org.mpris.MediaPlayer2.Player", "Metadata")
            status = props.Get("org.mpris.MediaPlayer2.Player", "PlaybackStatus")
            return parse_mpris_metadata(metadata, status)
        except Exception:
            player_proxies.pop(bus_name, None)
            return None

    def on_properties_changed(
        interface, changed_properties, invalidated_properties, path=None, bus_name=None
    ):
        if interface == "org.mpris.MediaPlayer2.Player":
            updated = False
            state = players_state.get(bus_name)

            if state:
                if "PlaybackStatus" in changed_properties:
                    state["status"] = str(changed_properties["PlaybackStatus"])
                    updated = True
                if "Metadata" in changed_properties:
                    new_meta = parse_mpris_metadata(
                        changed_properties["Metadata"], state["status"]
                    )
                    if new_meta:
                        state.update(new_meta)
                        updated = True
            else:
                # New or previously unknown unique sender, fetch full state
                data = fetch_player_data(bus_name)
                if data:
                    players_state[bus_name] = data
                    updated = True

            if updated:
                loop.call_soon_threadsafe(
                    MPRIS_QUEUE.put_nowait, {"players": dict(players_state)}
                )

    def update_all_players():
        well_known_names = [
            name
            for name in bus.list_names()
            if name.startswith("org.mpris.MediaPlayer2.")
        ]
        if not well_known_names:
            players_state.clear()
            player_proxies.clear()
            loop.call_soon_threadsafe(MPRIS_QUEUE.put_nowait, {"players": {}})
            return

        current_unique_players = {}
        for wk_name in well_known_names:
            try:
                # Resolve well-known name to unique name for consistent tracking
                unique_name = bus.get_name_owner(wk_name)
                data = fetch_player_data(unique_name)
                if data:
                    current_unique_players[unique_name] = data
            except Exception:
                continue

        players_state.clear()
        players_state.update(current_unique_players)

        # Cleanup stale proxies
        active_uniques = set(current_unique_players.keys())
        stale_proxies = set(player_proxies.keys()) - active_uniques
        for s in stale_proxies:
            player_proxies.pop(s, None)

        loop.call_soon_threadsafe(
            MPRIS_QUEUE.put_nowait, {"players": dict(players_state)}
        )

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
            # Re-sync when a player appears or disappears
            update_all_players()

    bus.add_signal_receiver(
        on_name_owner_changed,
        dbus_interface="org.freedesktop.DBus",
        signal_name="NameOwnerChanged",
    )

    update_all_players()
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

        # Signal the audio visualizer to start/stop
        if active_player and active_player.get("status") == "Playing":
            PLAYBACK_EVENT.set()
        else:
            PLAYBACK_EVENT.clear()

        await write_json(writer, {"mpris": active_player})
        MPRIS_QUEUE.task_done()
