import asyncio
import sys
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib
from ..utils import write_json


class NotificationService(dbus.service.Object):
    def __init__(self, bus, loop, writer):
        super().__init__(bus, "/org/freedesktop/Notifications")
        self.loop = loop
        self.writer = writer
        self.next_id = 1
        self.notifications = {}
        self.dnd = False
        self.batch_timer = None

    def _send_full_update(self):
        self.batch_timer = None
        notifications_list = list(self.notifications.values())
        asyncio.run_coroutine_threadsafe(
            write_json(
                self.writer,
                {"notifications": {"list": notifications_list, "dnd": self.dnd}},
            ),
            self.loop,
        )
        return False

    def _schedule_update(self):
        if self.batch_timer is None:
            self.batch_timer = GLib.timeout_add(10, self._send_full_update)

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

        for k, v in hints.items():
            k_str = str(k)
            if k_str in ["image-path", "image_path"] and not notification["app_icon"]:
                notification["app_icon"] = str(v)
            if isinstance(v, (dbus.String, dbus.Int32, dbus.UInt32, dbus.Boolean)):
                notification["hints"][k_str] = v

        self.notifications[notification_id] = notification
        if not self.dnd:
            asyncio.run_coroutine_threadsafe(
                write_json(self.writer, {"notification_popup": notification}), self.loop
            )

        self._schedule_update()
        return notification_id

    def _close_notification(self, id, reason):
        if id in self.notifications:
            del self.notifications[id]
            asyncio.run_coroutine_threadsafe(
                write_json(self.writer, {"close_notification_popup": int(id)}),
                self.loop,
            )
            self._schedule_update()
            self.NotificationClosed(id, reason)

    @dbus.service.method("org.freedesktop.Notifications", in_signature="u")
    def CloseNotification(self, id):
        self._close_notification(id, 3)

    def user_close_notification(self, id):
        self._close_notification(id, 2)

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
        asyncio.run_coroutine_threadsafe(
            write_json(self.writer, {"clear_notification_popup": True}), self.loop
        )
        self._schedule_update()

    def clear_app_notifications(self, app_name):
        ids_to_clear = [
            id for id, n in self.notifications.items() if n.get("app_name") == app_name
        ]
        for id in ids_to_clear:
            self._close_notification(id, 2)

    def set_dnd(self, dnd):
        self.dnd = dnd
        self._schedule_update()


def notification_worker(loop, writer):
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    try:
        bus_name = dbus.service.BusName(
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

    service = NotificationService(bus, loop, writer)

    global _notification_service
    _notification_service = service

    # Initial state
    asyncio.run_coroutine_threadsafe(
        write_json(writer, {"notifications": {"list": [], "dnd": False}}), loop
    )

    GLib.MainLoop().run()


def notification_thread_worker(loop, writer):
    try:
        notification_worker(loop, writer)
    except Exception as e:
        print(f"Error in notification thread: {e}", file=sys.stderr)


# Export for actions
def get_notification_service():
    return globals().get("_notification_service")
