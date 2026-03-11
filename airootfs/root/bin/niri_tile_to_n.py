#!/usr/bin/env python3
# -*- coding: utf-8 -*-


# ---------------------------------------------------------------------------------------------------------------------
# %% Imports

import socket
import json
import os
import signal
import argparse
import select
import threading
from dataclasses import dataclass
from time import perf_counter, sleep
from collections import deque
from queue import Queue, Empty


# ---------------------------------------------------------------------------------------------------------------------
# %% Args

# Set built-in defaults (helpful for debugging)
default_N = 5
default_delay_ms = 1000 if perf_counter() < 5 else 0
default_maximize_solos = True
default_maximize_solo_on_close = True
default_collapse_solos_on_open = True
default_apply_on_move = True
default_debug_names = False
default_debug_data = False

# Define script arguments
parser = argparse.ArgumentParser(
    description="Script which makes niri behave like an auto-tiler when there are fewer than 'N' windows"
)
parser.add_argument(
    "-n",
    default=default_N,
    type=int,
    help=f"Number of windows handled with auto-tiling (default {default_N})",
)
parser.add_argument(
    "-delay",
    default=default_delay_ms,
    type=int,
    help=f"Number of milliseconds to delay before listening to niri IPC (default: {default_delay_ms})",
)
parser.add_argument(
    "-x",
    action="store_false" if default_maximize_solos else "store_true",
    help=f"Auto-maximize first window opened on a workspace (default: {default_maximize_solos})",
)
parser.add_argument(
    "-xc",
    action="store_false" if default_maximize_solo_on_close else "store_true",
    help=f"When closing windows, if one window remains, auto-maximize it (default: {default_maximize_solo_on_close})",
)
parser.add_argument(
    "-c",
    action="store_false" if default_collapse_solos_on_open else "store_true",
    help=f"Collapse solo maximized window when opening a second window (default: {default_collapse_solos_on_open})",
)
parser.add_argument(
    "-m",
    action="store_false" if default_apply_on_move else "store_true",
    help=f"Apply tiling logic to windows that are moved into other workspaces (default: {default_apply_on_move})",
)
parser.add_argument(
    "-e",
    "--maximize_to_edges",
    action="store_true",
    help="Use maximize-to-edges instead of maximize-column",
)
parser.add_argument(
    "-dn",
    action="store_false" if default_debug_names else "store_true",
    help="Enable event name printing, for debugging",
)
parser.add_argument(
    "-dd",
    action="store_false" if default_debug_data else "store_true",
    help="Enable event data printing, for debugging",
)

TAG_PATTERNS: dict[str, list[str]] = {
    "terminal": ["alacritty", "foot", "kitty", "wezterm", "ghostty"],
    "browser": ["firefox", "chromium", "chrome", "zen-browser"],
}

# tag_state: {tag_name: {win_id: {"workspace_id": int, "workspace_idx": int}}}
tag_state: dict[str, dict[int, dict]] = {}
# win_id -> destination workspace for windows currently being tag-pulled
tag_pull_win_ids: dict[int, int] = {}

# workspace_id -> state for an in-flight pull batch
# {
#   "base_count": <tiled windows already on workspace before pull>,
#   "arrived": 0,
#   "total": <number of windows being pulled>,
# }
tag_pull_batches: dict[int, dict] = {}
tag_pushback_win_ids: set[int] = set() 
cmd_queue: Queue = Queue()
TILER_SOCKET_PATH = f"/tmp/niri-tiler-{os.getenv('WAYLAND_DISPLAY', 'wayland-0')}.sock"

# Get script configs
args, _ = parser.parse_known_args()
TILE_TO_N = args.n
STARTUP_DELAY_MS = args.delay
MAXIMIZE_SOLOS = args.x
MAXIMIZE_SOLOS_ON_CLOSE = args.xc
COLLAPSE_SOLOS_ON_OPEN = args.c
APPLY_TO_MOVED_WINDOWS = args.m
USE_MAX_TO_EDGES = args.maximize_to_edges
ENABLE_EVENT_NAME_DEBUG_PRINT = args.dn
ENABLE_EVENT_DATA_DEBUG_PRINT = args.dd


# ---------------------------------------------------------------------------------------------------------------------
# %% Data types


@dataclass
class TimeKeeper:
    t1: int = 0
    t2: int = 0

    def get_time_elapsed_ms(self) -> int:
        """Reports the time (in ms) since the last time this function was called"""
        self.t1 = self.t2
        self.t2 = round(perf_counter() * 1000)
        delta_ms = self.t2 - self.t1
        return delta_ms


@dataclass
class FocusState:
    workspace_id: int = None
    window_id: int = None

    def copy_inplace(self, other_focus_state):
        """Overwrite current data with data from another object (avoids creating new instances)"""
        self.workspace_id = other_focus_state.workspace_id
        self.window_id = other_focus_state.window_id
        return self


# ---------------------------------------------------------------------------------------------------------------------
# %% Classes


class NiriSocket:
    """Helper used to read & write json messages to a niri socket connection"""

    def __init__(self, socket_path: str, buffer_size: int = 4096):

        # Sanity check
        is_bad_path = socket_path is None or str(socket_path) == ""
        assert not is_bad_path, "Cannot connect to niri, no socket path given..."

        self._skt = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._skt.connect(skt_path)
        self._bufsize = buffer_size

        # Storage for
        self._msg_queue = deque([])
        self._inprog_str = None

    def _read_next(self, timeout: float | None = None):

        # Read from existing (buffered) messages, if any
        if len(self._msg_queue) > 0:
            next_msg = self._msg_queue.popleft()
            return json.loads(next_msg)

        while True:
            # If a timeout is given, use select() to avoid blocking forever.
            # Returns None on timeout so the caller can do other work (e.g. drain cmd_queue).
            if timeout is not None:
                ready, _, _ = select.select([self._skt], [], [], timeout)
                if not ready:
                    return None

            # Listen for raw (binary) string data from socket
            # -> Will return 0 bytes if connection closes
            resp_binstr = self._skt.recv(self._bufsize)
            if len(resp_binstr) == 0:
                print("DEBUG - READNEXT: No data received!")
                return {}

            # If we have an in-progress result, append the new data to it
            resp_str = resp_binstr.decode("utf-8")
            if self._inprog_str is not None:
                resp_str = "".join((self._inprog_str, resp_str))
                self._inprog_str = None

            # Stop listening if got at least 1 message
            # - Expect response to look like: "message 1\nmessage 2\nmessage 3\n"
            # - If incomplete, we'll see something not ending with '\n': "message 1\nmessa"
            msg_list = resp_str.split("\n")
            last_msg_piece = msg_list.pop()
            contains_incomplete_message = len(last_msg_piece) > 0
            self._inprog_str = last_msg_piece if contains_incomplete_message else None
            if len(msg_list) > 0:
                break

        # Sanity check, make sure we read something
        if len(msg_list) == 0:
            raise IOError("Error reading next message (empty message list)!")

        # If we have more than 1 message, return only the 'next one
        # (future calls to this function will return the queued up messages)
        out_msg_str = msg_list[0]
        if len(msg_list) > 1:
            self._msg_queue.extend(msg_list[1:])

        return json.loads(out_msg_str)

    def _send_string(self, string: str):
        """Helper used to send simple string messages (e.g. for requests)"""
        return self._skt.sendall(f'"{string}"\n'.encode("utf-8"))

    def _send_json(self, json_data: dict):
        """Helper used to send json message (e.g. for actions)"""
        json_as_str = json.dumps(json_data, indent=None, separators=(",", ":"))
        return self._skt.sendall(("".join([json_as_str, "\n"])).encode("utf-8"))

    def close(self):
        self._skt.close()

    @staticmethod
    def get_niri_socket_path():
        return os.environ.get("NIRI_SOCKET")


class NiriRequests(NiriSocket):
    """
    Helper used to make requests to niri
    See: https://yalter.github.io/niri/niri_ipc/enum.Request.html
    """

    def get_version(self):
        return self.request("Version")

    def request(self, message: str):
        self._send_string(message)

        # Listen for ok/err response
        resp_json = self._read_next()
        is_ok_resp = "Ok" in resp_json.keys()
        resp_data = resp_json["Ok" if is_ok_resp else "Err"]
        return is_ok_resp, resp_data

    def read_eventstream(self):

        is_ok, evt_resp = self.request("EventStream")
        if not is_ok:
            print("DEBUG - EventStream response:", evt_resp, sep="\n")
            raise IOError("Error requesting EventStream")

        # Read events from stream, forever
        while True:
            event_json = self._read_next(timeout=0.05)
            if event_json is None:
                # No event received within timeout, return to main loop to do other work (e.g. drain cmd_queue)
                yield None, None
                continue
            event_name = tuple(event_json.keys())[0]
            event_data = event_json.get(event_name, None)
            yield event_name, event_data
        return


class NiriActions(NiriSocket):
    """
    Helper used to trigger actions through the niri IPC
    See: https://yalter.github.io/niri/niri_ipc/enum.Action.html
    """

    def action(self, message: str, **kwargs):

        # Build action request
        json_data = {"Action": {message: kwargs}}
        self._send_json(json_data)

        # Listen for ok/err response
        resp_json = self._read_next()
        is_ok_resp = "Err" not in resp_json.keys()
        resp_data = resp_json if is_ok_resp else resp_json["Err"]
        return is_ok_resp, resp_data


class TilerCommandServer:
    """
    Minimal Unix socket server that receives plain-text commands
    (one per connection) and enqueues them for the main loop.
    e.g. echo "tag:terminal" | socat - UNIX-CONNECT:/tmp/niri-tiler-*.sock
    """
    def __init__(self, socket_path: str, queue: Queue):
        self._path = socket_path
        self._queue = queue
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        if os.path.exists(self._path):
            os.remove(self._path)
        self._thread.start()

    def stop(self):
        self._stop.set()
        try:
            import socket as _s
            _s.socket(_s.AF_UNIX, _s.SOCK_STREAM).connect(self._path)
        except Exception:
            pass
        self._thread.join(timeout=2)
        if os.path.exists(self._path):
            os.remove(self._path)

    def _run(self):
        import socket as _s
        srv = _s.socket(_s.AF_UNIX, _s.SOCK_STREAM)
        srv.bind(self._path)
        srv.listen(8)
        while not self._stop.is_set():
            try:
                conn, _ = srv.accept()
                with conn:
                    data = conn.recv(256).decode("utf-8").strip()
                    if data:
                        self._queue.put(data)
            except Exception:
                pass
        srv.close()


# ---------------------------------------------------------------------------------------------------------------------
# %% Functions


def catch_sigterm(signum, frame):
    """Turn SIGTERM events into exceptions for graceful shutdown"""
    raise InterruptedError


def make_workspace_state_from_WorkspacesChanged(event_data: dict) -> dict[int, dict]:
    return {info_dict["id"]: info_dict for info_dict in event_data["workspaces"]}


def make_window_state_from_WindowsChanged(event_data: dict, workspace_state, output_width_lut: dict) -> dict[int, dict]:
    state = {}
    for info_dict in event_data["windows"]:
        win_id = info_dict["id"]
        win_aug_data = get_additional_window_data(info_dict, workspace_state, output_width_lut)
        info_dict.update(win_aug_data)
        state[win_id] = info_dict
    return state


def get_windows_by_conditions(window_state: dict[int, dict], **conditions) -> dict[int, dict]:
    """Function used to filter window state data according to key-value conditions"""
    meets_conditions = lambda data: all(data[k] == v for k, v in conditions.items())
    return {winid: windata for winid, windata in window_state.items() if meets_conditions(windata)}


def get_additional_window_data(
    window_data: dict,
    workspace_state: dict,
    output_width_lut: dict,
    max_width_threshold: float = 0.8,
) -> dict:
    """Helper used to generate addition windowing data (particularly 'is_maximized' flag)"""
    # Set up augmentation data
    win_pos = window_data["layout"]["pos_in_scrolling_layout"]
    win_col, win_row = win_pos if win_pos is not None else (None, None)
    augment_dict = {
        "col_idx": win_col,
        "row_idx": win_row,
        "is_maximized": False,
    }

    # Try to figure out if window is maximized
    win_wspace_id = window_data["workspace_id"]
    win_output = workspace_state.get(win_wspace_id, {}).get("output", None)
    output_width = output_width_lut.get(win_output, None)
    if output_width is not None:
        win_width = window_data["layout"]["window_size"][0]
        augment_dict["is_maximized"] = (win_width / output_width) > max_width_threshold

    return augment_dict


def toggle_window_maximization(target_window_id: int, focused_window_id: int):
    """Helper used to toggle the maximization state of a window, without messing with current focused window"""

    if target_window_id == focused_window_id:
        niri_action.action("MaximizeWindowToEdges" if USE_MAX_TO_EDGES else "MaximizeColumn")
    else:
        niri_action.action("FocusWindow", id=target_window_id)
        niri_action.action("MaximizeWindowToEdges" if USE_MAX_TO_EDGES else "MaximizeColumn")
        niri_action.action("FocusWindow", id=focused_window_id)

    return


def maximize_window(window_state: dict, focus_state: FocusState, target_window_id: int) -> bool:
    """
    Helper used to maximize a window if it's not already maximized.
    This function assumes window state includes 'is_maximized' flag!
    Returns True if the window needed maximization, false otherwise
    """

    solo_win_data = window_state[target_window_id]
    need_maximization = not solo_win_data["is_maximized"]
    if need_maximization:
        solo_id = solo_win_data["id"]
        toggle_window_maximization(solo_id, focus_state.window_id)
        win_state[solo_id]["is_maximized"] = True

    return need_maximization


def collapse_window(window_state: dict, focus_state: FocusState, target_window_id: int) -> bool:
    """
    Helperused to collapse a maximized window. This function assumes
    that the window state includes 'is_maximized' flag!
    Returns: True if window needed collapse, false otherwise
    """

    solo_win_data = window_state[target_window_id]
    need_collapse = solo_win_data["is_maximized"]
    if need_collapse:
        solo_id = solo_win_data["id"]
        toggle_window_maximization(solo_id, focus_state.window_id)
        win_state[solo_id]["is_maximized"] = False

    return need_collapse

def handle_tag_toggle(tag_name: str):
    if tag_name not in TAG_PATTERNS:
        print(f"Unknown tag: '{tag_name}'")
        return

    current_wspace_id = focus_state.workspace_id
    if current_wspace_id is None:
        return

    origin_map = tag_state.get(tag_name)

    if origin_map:
        for win_id, origin in list(origin_map.items()):
            if win_id not in win_state:
                continue

            orig_id = origin["workspace_id"]
            orig_idx = origin["workspace_idx"]
            orig_name = origin.get("workspace_name")
            orig_output = origin.get("workspace_output")

            # Verify the stored ID still points to the right output
            current_wspace_data = wspace_state.get(orig_id, {})
            id_output_matches = current_wspace_data.get("output") == orig_output

            if orig_id in wspace_state and id_output_matches:
                reference = {"Id": orig_id}
            elif orig_name:
                print(f"[tag] ID output mismatch or gone, pushing back by name '{orig_name}'")
                reference = {"Name": orig_name}
            else:
                # Last resort: find workspace on the correct output by index
                correct_wspace = next(
                    (
                        ws for ws in wspace_state.values()
                        if ws.get("output") == orig_output and ws.get("idx") == orig_idx
                    ),
                    None,
                )
                if correct_wspace:
                    print(f"[tag] falling back to output-matched workspace ID {correct_wspace['id']}")
                    reference = {"Id": correct_wspace["id"]}
                else:
                    print(f"[tag] could not find workspace on output {orig_output}, using index {orig_idx}")
                    reference = {"Index": orig_idx}

            print(f"[tag] pushing back win {win_id} using reference {reference}")
            ok, resp = niri_action.action(
                "MoveWindowToWorkspace",
                window_id=win_id,
                reference=reference,
                focus=False,
            )
            if ok:
                tag_pushback_win_ids.add(win_id)
            else:
                print(f"[tag] push-back failed for {win_id}: {resp}")

        tag_state.pop(tag_name, None)


    else:
        # Pull
        patterns = TAG_PATTERNS[tag_name]
        new_origin_map: dict[int, int] = {}
        for win_id, win_data in win_state.items():
            if win_data.get("workspace_id") == current_wspace_id:
                continue
            if win_data.get("is_floating"):
                continue

            app_id = (win_data.get("app_id") or "").lower()
            if any(p in app_id for p in patterns):
                orig_wspace_id = win_data["workspace_id"]
                orig_wspace_data = wspace_state.get(orig_wspace_id, {})
                orig_wspace_idx = wspace_state.get(orig_wspace_id, {}).get("idx", 0)
                orig_wspace_output = orig_wspace_data.get("output", None)
                new_origin_map[win_id] = {
                    "workspace_id": orig_wspace_id,
                    "workspace_idx": orig_wspace_idx,
                    "workspace_name": orig_wspace_data.get("name", None),
                    "workspace_output": orig_wspace_output,
                }

        if not new_origin_map:
            print(f"No off-workspace windows matched tag '{tag_name}'")
            return

        existing_wins = get_windows_by_conditions(
            win_state,
            workspace_id=current_wspace_id,
            is_floating=False,
        )
        base_count = len(existing_wins)

        moved_origin_map: dict[int, int] = {}
        moved_ids: list[int] = []

        for win_id, orig_wspace_id in new_origin_map.items():
            ok, resp = niri_action.action(
                "MoveWindowToWorkspace",
                window_id=win_id,
                reference={"Id": current_wspace_id},
                focus=False,
            )
            if ok:
                moved_origin_map[win_id] = orig_wspace_id
                moved_ids.append(win_id)
            else:
                print(f"[tag] pull failed for {win_id}: {resp}")

        if moved_origin_map:
            tag_state[tag_name] = moved_origin_map
            tag_pull_batches[current_wspace_id] = {
                "base_count": base_count,
                "arrived": 0,
                "total": len(moved_ids),
            }
            for win_id in moved_ids:
                tag_pull_win_ids[win_id] = current_wspace_id

# ---------------------------------------------------------------------------------------------------------------------
# %% Setup

# Handle startup delay (prevent listening to niri during potentially busy startup)
if STARTUP_DELAY_MS > 0:
    sleep(STARTUP_DELAY_MS / 1000)

# Get niri socket from env
skt_path = NiriSocket.get_niri_socket_path()
if skt_path is None or skt_path == "":
    print("Couldn't find niri socket! (from env: NIRI_SOCKET)")
    quit()

# Create separate read/write sockets, since eventstream reader cannot issue actions
niri_reader = NiriRequests(skt_path)
niri_action = NiriActions(skt_path)
cmd_server = TilerCommandServer(TILER_SOCKET_PATH, cmd_queue)
cmd_server.start()
print(f"Command socket: {TILER_SOCKET_PATH}")


# Sanity check. Make sure we have the right version
is_version_ok, version_resp = niri_reader.request("Version")
expected_version, actual_version = "25.11 (b35bcae)", version_resp.get("Version", "unknown")
if actual_version != expected_version:
    print(
        "",
        "WARNING - Unexpected niri version!",
        f"expected: {expected_version}",
        f"  actual: {actual_version}",
        "Errors may occur...",
        sep="\n",
    )


# ---------------------------------------------------------------------------------------------------------------------
# %% *** IPC listening loop ***

# Get monitor into
is_outputs_ok, outputs_resp = niri_reader.request("Outputs")
if not is_outputs_ok:
    print("Error requesting info about monitors", outputs_resp, sep="\n")
    quit()
output_full_info = {out_key: out_dict["logical"] for out_key, out_dict in outputs_resp["Outputs"].items()}
output_width_lut = {out_key: out_info["width"] for out_key, out_info in output_full_info.items() if out_info is not None}

# Initialize state tracking
prev_focus_state = FocusState()
focus_state = FocusState()
timekeeper = TimeKeeper()
win_state = None
wspace_state = None

# Main listening loop
signal.signal(signal.SIGTERM, catch_sigterm)
try:
    init_time = timekeeper.get_time_elapsed_ms()
    for evt_name, evt_data in niri_reader.read_eventstream():
        
        while True:
            try:
                cmd = cmd_queue.get_nowait()
                if cmd.startswith("tag:") and win_state and wspace_state:
                    handle_tag_toggle(cmd[4:])
            except Empty:
                break
        
        if evt_name is None:
            continue

        # For debugging printouts, add spaces between events that don't occur together
        time_elapsed_ms = timekeeper.get_time_elapsed_ms()
        if ENABLE_EVENT_NAME_DEBUG_PRINT or ENABLE_EVENT_DATA_DEBUG_PRINT:
            if time_elapsed_ms > 250:
                print("", f"Time elapsed (sec): {(timekeeper.t2 - init_time) // 1000}", sep="\n")
            if ENABLE_EVENT_NAME_DEBUG_PRINT:
                print(evt_name)
            if ENABLE_EVENT_DATA_DEBUG_PRINT:
                print(evt_data)

        # Handle all IPC stream events
        prev_focus_state.copy_inplace(focus_state)
        closed_window_data, newest_window_data = None, None
        if evt_name == "WorkspacesChanged":
            # Replace existing workspace info
            wspace_state = make_workspace_state_from_WorkspacesChanged(evt_data)
            for item in wspace_state.values():
                if item["is_focused"]:
                    focus_state.workspace_id = item["id"]

        elif evt_name == "WorkspaceUrgencyChanged":
            # Update our existing workspace state
            evt_wspace_id = evt_data["id"]
            wspace_state[evt_wspace_id]["is_urgent"] = evt_data["urgent"]

        elif evt_name == "WorkspaceActivated":
            # Record new focused workspace (ignore 'active' state, we don't use it)
            if evt_data["focused"]:
                focus_state.workspace_id = evt_data["id"]
                wspace_state[prev_focus_state.workspace_id]["is_focused"] = False
            pass

        elif evt_name == "WorkspaceActiveWindowChanged":
            # Not using this...?
            # print(
            #     f"DEBUG EVENT - *{evt_name}*  |  Not using...?",
            #     "  Data:",
            #     f"    active_window_id: {evt_data['active_window_id']}",
            #     f"        workspace_id: {evt_data['workspace_id']}",
            #     sep="\n",
            # )
            pass

        elif evt_name == "WindowsChanged":
            # Replace existing window state
            win_state = make_window_state_from_WindowsChanged(evt_data, wspace_state, output_width_lut)
            for item in win_state.values():
                if item["is_focused"]:
                    focus_state.window_id = item["id"]

        elif evt_name == "WindowOpenedOrChanged":
            # Decide if we have a new/moved window
            evt_win_id = evt_data["window"]["id"]
            evt_win_wspace_id = evt_data["window"]["workspace_id"]
            evt_is_new_window = evt_win_id not in win_state.keys()
            evt_is_moved_window, prev_win_wspace_id = False, None
            if not evt_is_new_window:
                prev_win_wspace_id = win_state[evt_win_id]["workspace_id"]
                evt_is_moved_window = prev_win_wspace_id != evt_win_wspace_id

            # Update focus, if needed
            if evt_data["window"]["is_focused"]:
                focus_state.window_id = evt_win_id

            # Replace existing window state for the target window
            win_aug_data = get_additional_window_data(evt_data["window"], wspace_state, output_width_lut)
            win_state[evt_win_id] = {**evt_data["window"], **win_aug_data}
            effective_num_tile_wins = None
            is_tag_pulled_window = evt_is_moved_window and (evt_win_id in tag_pull_win_ids)

            if is_tag_pulled_window:
                batch_wspace_id = tag_pull_win_ids[evt_win_id]
                batch = tag_pull_batches.get(batch_wspace_id)

                if batch is not None:
                    batch["arrived"] += 1
                    effective_num_tile_wins = batch["base_count"] + batch["arrived"]
                    print(
                        f"[tag] pulled window {evt_win_id} arrived on workspace {batch_wspace_id}; "
                        f"base={batch['base_count']} arrived={batch['arrived']} "
                        f"effective_num_tile_wins={effective_num_tile_wins}"
                    )

                    if batch["arrived"] >= batch["total"]:
                        tag_pull_batches.pop(batch_wspace_id, None)

                tag_pull_win_ids.pop(evt_win_id, None)
            need_check_rearrange = (
                evt_is_new_window
                or (evt_is_moved_window and APPLY_TO_MOVED_WINDOWS)
                or is_tag_pulled_window
            )

            newest_window_data = win_state[evt_win_id] if need_check_rearrange else None

            if newest_window_data is not None and effective_num_tile_wins is not None:
                newest_window_data["_effective_num_tile_wins"] = effective_num_tile_wins

        elif evt_name == "WindowClosed":
            # Delete closed window state data & remove from windows-per-workspace mapping
            evt_win_id = evt_data["id"]
            closed_window_data = win_state.pop(evt_win_id)

        elif evt_name == "WindowFocusChanged":
            # Update existing focus state
            focus_state.window_id = evt_data["id"]

        elif evt_name == "WindowFocusTimestampChanged":
            # Update existing focus-timestamp state
            evt_win_id = evt_data["id"]
            win_state[evt_win_id]["focus_timestamp"] = evt_data["focus_timestamp"]

        elif evt_name == "WindowUrgencyChanged":
            # Update our existing window state
            evt_win_id = evt_data["id"]
            win_state[evt_win_id]["is_urgent"] = evt_data["urgent"]

        elif evt_name == "WindowLayoutsChanged":
            # Replace existing window layout data
            for evt_win_id, evt_new_layout in evt_data["changes"]:
                win_state[evt_win_id]["layout"] = evt_new_layout
                win_aug_data = get_additional_window_data(win_state[evt_win_id], wspace_state, output_width_lut)
                win_state[evt_win_id].update(win_aug_data)
            pass

        elif evt_name == "KeyboardLayoutsChanged":
            # Not doing anything with keyboard...
            pass

        elif evt_name == "KeyboardLayoutSwitched":
            # Not doing anything with keyboard...
            pass

        elif evt_name == "OverviewOpenedOrClosed":
            # Not doing anything with overview...
            evt_is_overview_open = evt_data["is_open"]

        elif evt_name == "ConfigLoaded":
            # Not doing anything with config...
            pass

        else:
            print("Unknown event:", evt_name)

        # Handle max-on-close
        if closed_window_data is not None:
            if MAXIMIZE_SOLOS_ON_CLOSE:
                curr_wspace_id = closed_window_data["workspace_id"]
                curr_wins = get_windows_by_conditions(win_state, workspace_id=curr_wspace_id, is_floating=False)
                if len(curr_wins) == 1:
                    solo_id = tuple(curr_wins.keys())[0]
                    maximize_window(win_state, focus_state, solo_id)
                pass

        # Handle window-creation behaviors
        if newest_window_data is not None:

            # Ignore newly created maximized or floating windows
            # -> Assume opened maximized windows are done by user window rules (don't want to interfere)
            # -> Tiling logic shouldn't apply to floating windows
            if newest_window_data["is_floating"]:
                continue

            # Don't bother trying to re-arrange/tile if we already have more than 'N' windows
            curr_wspace_id = newest_window_data["workspace_id"]
            curr_tile_wins = get_windows_by_conditions(win_state, workspace_id=curr_wspace_id, is_floating=False)
            actual_num_tile_wins = len(curr_tile_wins)
            num_tile_wins = newest_window_data.get("_effective_num_tile_wins", actual_num_tile_wins)

            # Auto-maximize solo windows, if needed
            if MAXIMIZE_SOLOS and num_tile_wins == 1:
                print(f"DEBUG - Auto-maximizing solo window {newest_window_data['id']}")
                solo_id = tuple(curr_tile_wins.keys())[0]
                #maximize_window(win_state, focus_state, solo_id)

            # Collapse maximized windows, if needed
            curr_max_wins: dict = get_windows_by_conditions(curr_tile_wins, is_maximized=True)
            num_max_wins = len(curr_max_wins)
            if COLLAPSE_SOLOS_ON_OPEN and num_max_wins == 1 and num_tile_wins == 2:
                solo_max_id = tuple(curr_max_wins.keys())[0]
                collapse_window(win_state, focus_state, solo_max_id)
                num_max_wins -= 1

            print(
                f"DEBUG - newest={newest_window_data['id']} "
                f"is_maximized={newest_window_data['is_maximized']} "
                f"is_floating={newest_window_data['is_floating']} "
                f"num_tile_wins={num_tile_wins} "
                f"curr_tile_ids={list(curr_tile_wins.keys())} "
                f"num_max_wins={num_max_wins} "
                f"max_ids={list(curr_max_wins.keys())}"
                )


            # Apply tiling if needed
            is_zero_max_windows = num_max_wins == 0
            cycle_pos = ((num_tile_wins - 1) % TILE_TO_N) + 1
            print(f"DEBUG - Applying tiling action for new window (cycle pos: {cycle_pos})...")

            if cycle_pos == 1:
                # 1, 6, 11, ...
                print(f"DEBUG - cycle 1 focused new window {newest_window_data['id']} for maximization")
                niri_action.action("FocusWindow", id=newest_window_data["id"])
                niri_action.action("MaximizeColumn")


            elif cycle_pos == 2:
                # 2, 7, 12, ...
                curr_max_wins = get_windows_by_conditions(curr_tile_wins, is_maximized=True)
                if len(curr_max_wins) == 1:
                    solo_max_id = tuple(curr_max_wins.keys())[0]
                    collapse_window(win_state, focus_state, solo_max_id)

            elif cycle_pos == 3:
                # 3, 8, 13, ...
                target_id = newest_window_data["id"]
                target_index = 1 + 2 * ((num_tile_wins - 1) // TILE_TO_N)

                print(f"DEBUG - cycle 3 target_id={target_id} target_index={target_index}")
                niri_action.action("FocusWindow", id=target_id)
                niri_action.action("MoveColumnToIndex", index=target_index)
                niri_action.action("ConsumeOrExpelWindowRight")

            else:
                # 4/5, 9/10, 14/15, ...
                target_id = newest_window_data["id"]
                expected_col = 2 + 2 * ((num_tile_wins - 1) // TILE_TO_N)
                actual_col = newest_window_data.get("col_idx")
                is_new_win_onscreen = actual_col == expected_col

                print(
                    f"DEBUG - cycle {cycle_pos} target_id={target_id} "
                    f"actual_col={actual_col} expected_col={expected_col} "
                    f"is_new_win_onscreen={is_new_win_onscreen}"
                )

                niri_action.action("FocusWindow", id=target_id)

                consume_action = (
                    "ConsumeOrExpelWindowRight"
                    if is_new_win_onscreen
                    else "ConsumeOrExpelWindowLeft"
                )
                niri_action.action(consume_action, id=target_id)


            pass

except (KeyboardInterrupt, InterruptedError):
    pass

finally:
    niri_action.close()
    niri_reader.close()
    cmd_server.stop()
    print("", f"({os.path.basename(__file__)}) - Closed niri IPC connection", sep="\n")