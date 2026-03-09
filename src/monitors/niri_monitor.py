import asyncio
from ..niri import niri_conn
from ..utils import write_json
from ..tasks import long_running_task


@long_running_task
async def niri_monitor(writer):
    """Monitors niri events and updates workspace state."""
    niri = niri_conn

    state = {"workspaces": [], "windows": []}

    # Track workspaces and windows that were recently closed or moved to signal deletion to QML
    # workspace_id -> list of window_ids
    recently_closed_windows = {}
    known_workspace_ids = set()

    pending_ws_ids = set()
    full_sync_pending = False
    sync_task = None

    async def emit_workspaces(ws_ids=None):
        """
        Actually formats and writes the JSON.
        If ws_ids is None, emits all workspaces.
        """
        workspace_id_to_data = {}
        current_ws_ids = set()

        for ws in state["workspaces"]:
            wid = ws["id"]
            current_ws_ids.add(wid)
            workspace_id_to_data[wid] = {
                "id": wid,
                "idx": ws["idx"],
                "output": ws["output"],
                "is_urgent": ws["is_urgent"],
                "is_focused": ws.get("is_focused", False),
                "active_window_id": ws.get("active_window_id"),
                "windows": {},
            }

        for win in state["windows"]:
            ws_id = win["workspace_id"]
            if ws_id in workspace_id_to_data:
                app_id = win.get("app_id") or ""
                if app_id.startswith(".") and app_id.endswith("-wrapped"):
                    app_id = app_id[1:-8]

                workspace_id_to_data[ws_id]["windows"][str(win["id"])] = {
                    "title": win["title"],
                    "app_id": app_id,
                    "pid": win["pid"],
                    "is_focused": win["is_focused"],
                }

        # Add null entries for recently closed/moved windows
        for ws_id, win_ids in list(recently_closed_windows.items()):
            if ws_id in workspace_id_to_data:
                for win_id in win_ids:
                    workspace_id_to_data[ws_id]["windows"][str(win_id)] = None
            del recently_closed_windows[ws_id]

        output = {}
        if ws_ids is None:
            # Full sync: detect removed workspaces
            removed_ws_ids = known_workspace_ids - current_ws_ids
            for rid in removed_ws_ids:
                output[str(rid)] = None

            # Add all current workspaces
            for wid, data in workspace_id_to_data.items():
                output[str(wid)] = data

            known_workspace_ids.clear()
            known_workspace_ids.update(current_ws_ids)
        else:
            # Partial update (diff)
            ids_to_send = ws_ids if isinstance(ws_ids, (list, set, tuple)) else [ws_ids]
            for wid in ids_to_send:
                if wid in workspace_id_to_data:
                    output[str(wid)] = workspace_id_to_data[wid]
                elif wid in known_workspace_ids:
                    # Workspace was removed
                    output[str(wid)] = None
                    known_workspace_ids.remove(wid)

        if output:
            await write_json(writer, {"workspaces": output})

    async def schedule_emit(ws_ids=None):
        """Schedules an emission after a short delay to batch events."""
        nonlocal sync_task, full_sync_pending

        if ws_ids is None:
            full_sync_pending = True
        else:
            ids = ws_ids if isinstance(ws_ids, (list, set, tuple)) else [ws_ids]
            pending_ws_ids.update(ids)

        if sync_task and not sync_task.done():
            return

        async def do_emit():
            nonlocal full_sync_pending
            await asyncio.sleep(0.01)  # 10ms batching window

            if full_sync_pending:
                await emit_workspaces(None)
            else:
                await emit_workspaces(list(pending_ws_ids))

            pending_ws_ids.clear()
            full_sync_pending = False

        sync_task = asyncio.create_task(do_emit())

    # Initial fetch
    ws_resp = await niri.send("Workspaces")
    if ws_resp and "Workspaces" in ws_resp:
        state["workspaces"] = ws_resp["Workspaces"]
        for ws in state["workspaces"]:
            known_workspace_ids.add(ws["id"])

    win_resp = await niri.send("Windows")
    if win_resp and "Windows" in win_resp:
        state["windows"] = win_resp["Windows"]

    if state["workspaces"]:
        await emit_workspaces()

    async for event in niri.stream_events():
        if "WorkspacesChanged" in event:
            state["workspaces"] = event["WorkspacesChanged"]["workspaces"]
            await schedule_emit(None)

        elif "WindowsChanged" in event:
            state["windows"] = event["WindowsChanged"]["windows"]
            await schedule_emit(None)

        elif "WindowOpenedOrChanged" in event:
            win = event["WindowOpenedOrChanged"]["window"]
            old_ws_id = None
            found = False
            for i, existing_win in enumerate(state["windows"]):
                if existing_win["id"] == win["id"]:
                    old_ws_id = existing_win["workspace_id"]
                    state["windows"][i] = win
                    found = True
                    break
            if not found:
                state["windows"].append(win)

            new_ws_id = win["workspace_id"]
            affected = {new_ws_id}
            if old_ws_id is not None and old_ws_id != new_ws_id:
                if old_ws_id not in recently_closed_windows:
                    recently_closed_windows[old_ws_id] = []
                recently_closed_windows[old_ws_id].append(win["id"])
                affected.add(old_ws_id)
            await schedule_emit(affected)

        elif "WorkspaceActivated" in event:
            activated = event["WorkspaceActivated"]
            target_id = activated["id"]
            is_focused = activated.get("focused", True)
            affected = set()
            for ws in state["workspaces"]:
                if ws.get("is_focused") and ws["id"] != target_id:
                    ws["is_focused"] = False
                    affected.add(ws["id"])
                if ws["id"] == target_id:
                    if ws.get("is_focused") != is_focused:
                        ws["is_focused"] = is_focused
                        affected.add(ws["id"])
            await schedule_emit(affected)

        elif "WorkspaceActiveWindowChanged" in event:
            changed = event["WorkspaceActiveWindowChanged"]
            for ws in state["workspaces"]:
                if ws["id"] == changed["workspace_id"]:
                    ws["active_window_id"] = changed["active_window_id"]
                    break
            await schedule_emit(changed["workspace_id"])

        elif "WindowFocusChanged" in event:
            focused_id = event["WindowFocusChanged"].get("id")
            affected = set()
            for win in state["windows"]:
                if win["is_focused"] and win["id"] != focused_id:
                    win["is_focused"] = False
                    affected.add(win["workspace_id"])
                if win["id"] == focused_id:
                    if not win["is_focused"]:
                        win["is_focused"] = True
                        affected.add(win["workspace_id"])
            await schedule_emit(affected)

        elif "WindowClosed" in event:
            closed_id = event["WindowClosed"]["id"]
            target_ws_id = None
            for i, win in enumerate(state["windows"]):
                if win["id"] == closed_id:
                    target_ws_id = win["workspace_id"]
                    state["windows"].pop(i)
                    break
            if target_ws_id is not None:
                if target_ws_id not in recently_closed_windows:
                    recently_closed_windows[target_ws_id] = []
                recently_closed_windows[target_ws_id].append(closed_id)
                await schedule_emit(target_ws_id)
