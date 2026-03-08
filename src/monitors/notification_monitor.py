import asyncio
from asyncio import QueueEmpty
import sys
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib
from ..utils import write_json
from ..tasks import long_running_task

NOTIFICATION_QUEUE = asyncio.Queue()


class NotificationService(dbus.service.Object):
    def __init__(self, bus, loop, queue):
        super().__init__(bus, "/org/freedesktop/Notifications")
        self.loop = loop
        self.queue = queue
        self.next_id = 1
        self.notifications = {}
        self.dnd = False

    @dbus.service.method(
        "org.freedesktop.Notifications", in_signature="susssasa{sv}i", out_signature="u"
    )
    def Notify(
        self,
        app_name,
        replaces_id,
        app_icon,
        summary,
        body,
        actions,
        hints,
        expire_timeout,
    ):
        if self.dnd:
            return 0

        notification_id = replaces_id if replaces_id != 0 else self.next_id
        if replaces_id == 0:
            self.next_id += 1

        notification = {
            "id": int(notification_id),
            "app_name": str(app_name),
            "app_icon": str(app_icon),
            "summary": str(summary),
            "body": str(body),
            "actions": [str(a) for a in actions],
            "hints": {},
            "expire_timeout": int(expire_timeout),
        }

        # Handle hints and icon extraction
        for k, v in hints.items():
            k_str = str(k)
            if k_str in ["image-path", "image_path"] and not notification["app_icon"]:
                notification["app_icon"] = str(v)
            # Basic conversion for other hints
            if isinstance(v, (dbus.String, dbus.Int32, dbus.UInt32, dbus.Boolean)):
                notification["hints"][k_str] = v

        self.notifications[notification_id] = notification
        self.loop.call_soon_threadsafe(
            self.queue.put_nowait, {"type": "notify", "notification": notification}
        )
        return notification_id

    def _close_notification(self, id, reason):
        if id in self.notifications:
            del self.notifications[id]
            self.loop.call_soon_threadsafe(
                self.queue.put_nowait, {"type": "close", "id": int(id)}
            )
            self.NotificationClosed(id, reason)

    @dbus.service.method("org.freedesktop.Notifications", in_signature="u")
    def CloseNotification(self, id):
        self._close_notification(id, 3)  # 3 = closed by call to CloseNotification

    def user_close_notification(self, id):
        self._close_notification(id, 2)  # 2 = closed by user

    @dbus.service.method("org.freedesktop.Notifications", out_signature="as")
    def GetCapabilities(self):
        return ["actions", "body", "icon-static", "persistence"]

    @dbus.service.method("org.freedesktop.Notifications", out_signature="ssss")
    def GetServerInformation(self):
        return ("mybar-notifications", "aleksana", "0.1", "1.2")

    @dbus.service.signal("org.freedesktop.Notifications", signature="us")
    def ActionInvoked(self, id, action_key):
        pass

    @dbus.service.signal("org.freedesktop.Notifications", signature="uu")
    def NotificationClosed(self, id, reason):
        pass

    def clear_all(self):
        ids = list(self.notifications.keys())
        for id in ids:
            self.NotificationClosed(id, 2)
        self.notifications.clear()
        self.loop.call_soon_threadsafe(self.queue.put_nowait, {"type": "clear_all"})

    def clear_app_notifications(self, app_name):
        ids_to_clear = [
            id for id, n in self.notifications.items() if n.get("app_name") == app_name
        ]
        for id in ids_to_clear:
            self._close_notification(id, 2)

    def set_dnd(self, dnd):
        self.dnd = dnd
        self.loop.call_soon_threadsafe(
            self.queue.put_nowait, {"type": "dnd", "value": dnd}
        )


def notification_worker(loop):
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    # Try to acquire the name, allowing us to replace an existing daemon
    # and also allowing future instances to replace us.
    try:
        name = dbus.service.BusName(
            "org.freedesktop.Notifications",
            bus,
            allow_replacement=True,
            replace_existing=True,
            do_not_queue=True,
        )
    except dbus.exceptions.NameExistsException:
        print(
            "Error: Another notification daemon is running and does not allow replacement.",
            file=sys.stderr,
        )
        return
    except Exception as e:
        print(f"Error acquiring D-Bus name: {e}", file=sys.stderr)
        return

    service = NotificationService(bus, loop, NOTIFICATION_QUEUE)

    # Store service in a global-ish way so actions can access it
    global _notification_service
    _notification_service = service

    GLib.MainLoop().run()


def notification_thread_worker(loop):
    try:
        notification_worker(loop)
    except Exception as e:
        print(f"Error in notification thread: {e}", file=sys.stderr)


@long_running_task
async def notification_monitor(writer):
    notifications_list = []
    dnd = False

    # Initial state
    await write_json(
        writer, {"notifications": {"list": notifications_list, "dnd": dnd}}
    )

    while True:
        # Wait for the first event
        event = await NOTIFICATION_QUEUE.get()

        # Process the first event and any others currently in the queue
        events_to_process = [event]
        while not NOTIFICATION_QUEUE.empty():
            try:
                events_to_process.append(NOTIFICATION_QUEUE.get_nowait())
            except QueueEmpty:
                break

        list_changed = False
        dnd_changed = False

        for ev in events_to_process:
            ev_type = ev.get("type")

            if ev_type == "notify":
                n = ev["notification"]
                # Check if it replaces an existing one
                replaced = False
                for i, existing in enumerate(notifications_list):
                    if existing["id"] == n["id"]:
                        notifications_list[i] = n
                        replaced = True
                        break
                if not replaced:
                    notifications_list.append(n)
                list_changed = True

                # Send the new notification specifically for the popup immediately
                await write_json(writer, {"notification_popup": n})

            elif ev_type == "close":
                original_len = len(notifications_list)
                notifications_list = [
                    n for n in notifications_list if n["id"] != ev["id"]
                ]
                if len(notifications_list) != original_len:
                    list_changed = True
                await write_json(writer, {"close_notification_popup": ev["id"]})

            elif ev_type == "clear_all":
                notifications_list = []
                list_changed = True
                await write_json(writer, {"clear_notification_popup": True})

            elif ev_type == "dnd":
                dnd = ev["value"]
                dnd_changed = True

            NOTIFICATION_QUEUE.task_done()

        # Send the full state update only once per batch of events
        if list_changed or dnd_changed:
            await write_json(
                writer, {"notifications": {"list": notifications_list, "dnd": dnd}}
            )


# Export for actions
def get_notification_service():
    return globals().get("_notification_service")
