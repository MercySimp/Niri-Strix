#!/usr/bin/env python3
# -*- coding: utf-8 -*-


# ---------------------------------------------------------------------------------------------------------------------
# %% Imports

import socket
import json
import os
import signal
import argparse
from dataclasses import dataclass
from time import perf_counter, sleep
from collections import deque
from queue import Queue, Empty
import threading
import re

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
    help=f"Number of milliseconds to delay before listening to niri IPC (default: {
        default_delay_ms
    })",
)
parser.add_argument(
    "-x",
    action="store_false" if default_maximize_solos else "store_true",
    help=f"Auto-maximize first window opened on a workspace (default: {
        default_maximize_solos
    })",
)
parser.add_argument(
    "-xc",
    action="store_false" if default_maximize_solo_on_close else "store_true",
    help=f"When closing windows, if one window remains, auto-maximize it (default: {
        default_maximize_solo_on_close
    })",
)
parser.add_argument(
    "-c",
    action="store_false" if default_collapse_solos_on_open else "store_true",
    help=f"Collapse solo maximized window when opening a second window (default: {
        default_collapse_solos_on_open
    })",
)
parser.add_argument(
    "-m",
    action="store_false" if default_apply_on_move else "store_true",
    help=f"Apply tiling logic to windows that are moved into other workspaces (default: {
        default_apply_on_move
    })",
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

# Define tag patterns (app_id substring match, case-insensitive)
# Keys become the command name sent over the socket
TAG_PATTERNS: dict[str, list[str]] = {
    "terminal": ["alacritty", "foot", "kitty", "wezterm", "ghostty"],
    "browser": ["firefox", "chromium", "chrome", "zen"],
    "coding": ["nvim", "vim", "code"],
    "files": ["spf", "nautilus", "thundar", "dolphin"],
}

# Tracks pulled windows per tag: {tag_name: {win_id: original_workspace_id}}
# None / missing key = not currently pulled
tag_state: dict[str, dict[int, int]] = {}

# workspace_id → how many tag-pulled windows are still in-flight
pending_retile_counts: dict[int, int] = {}

# win IDs currently in-flight from a tag pull (suppress normal tiling for them)
tag_pull_win_ids: set[int] = set()

# Thread-safe queue for commands arriving on the IPC socket
cmd_queue: Queue = Queue()

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

    def _read_next(self):

        # Read from existing (buffered) messages, if any
        if len(self._msg_queue) > 0:
            next_msg = self._msg_queue.popleft()
            return json.loads(next_msg)

        while True:
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
            event_json = self._read_next()
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


TILER_SOCKET_PATH = f"/tmp/niri-tiler-{os.getenv('WAYLAND_DISPLAY', 'wayland-0')}.sock"


class TilerCommandServer:
    """
    Minimal Unix socket server that receives plain-text commands
    (one per connection) and enqueues them for the main loop.
    e.g.  echo "tag:terminal" | socat - UNIX-CONNECT:/tmp/niri-tiler-*.sock
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
        # Unblock the accept() by connecting briefly
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


def make_window_state_from_WindowsChanged(
    event_data: dict, workspace_state, output_width_lut: dict
) -> dict[int, dict]:
    state = {}
    for info_dict in event_data["windows"]:
        win_id = info_dict["id"]
        win_aug_data = get_additional_window_data(
            info_dict, workspace_state, output_width_lut
        )
        info_dict.update(win_aug_data)
        state[win_id] = info_dict
    return state


def get_windows_by_conditions(
    window_state: dict[int, dict], **conditions
) -> dict[int, dict]:
    """Function used to filter window state data according to key-value conditions"""

    def meets_conditions(data):
        return all(data[k] == v for k, v in conditions.items())

    return {
        winid: windata
        for winid, windata in window_state.items()
        if meets_conditions(windata)
    }


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
        niri_action.action(
            "MaximizeWindowToEdges" if USE_MAX_TO_EDGES else "MaximizeColumn"
        )
    else:
        niri_action.action("FocusWindow", id=target_window_id)
        niri_action.action(
            "MaximizeWindowToEdges" if USE_MAX_TO_EDGES else "MaximizeColumn"
        )
        niri_action.action("FocusWindow", id=focused_window_id)

    return


def maximize_window(
    window_state: dict, focus_state: FocusState, target_window_id: int
) -> bool:
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


def collapse_window(
    window_state: dict, focus_state: FocusState, target_window_id: int
) -> bool:
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
        # ── Push back ──────────────────────────────────────────────────────
        for win_id, orig_wspace_id in list(origin_map.items()):
            if win_id in win_state:
                ok, resp = niri_action.action(
                    "MoveWindowToWorkspace",
                    window_id=win_id,
                    reference={"Id": orig_wspace_id},
                    focus=False,
                )
                if ok:
                    # Remove immediately so retile sees the correct remaining count
                    win_state.pop(win_id, None)
                else:
                    print(f"  [tag] push-back failed: {resp}")

        tag_state.pop(tag_name, None)

        # Remaining windows have valid col_idx, retile is safe to call now
        retile_workspace(current_wspace_id)

    else:
        # ── Pull ───────────────────────────────────────────────────────────
        patterns = TAG_PATTERNS[tag_name]
        new_origin_map: dict[int, int] = {}

        for win_id, win_data in win_state.items():
            if win_data.get("workspace_id") == current_wspace_id:
                continue
            if win_data.get("is_floating"):
                continue
            app_id = (win_data.get("app_id") or "").lower()
            if any(p in app_id for p in patterns):
                new_origin_map[win_id] = win_data["workspace_id"]

        if not new_origin_map:
            print(f"No off-workspace windows matched tag '{tag_name}'")
            return

        for win_id in new_origin_map:
            ok, resp = niri_action.action(
                "MoveWindowToWorkspace",
                window_id=win_id,
                reference={"Id": current_wspace_id},
                focus=False,
            )
            if not ok:
                print(f"  [tag] pull failed: {resp}")
                new_origin_map.pop(win_id, None)

        if new_origin_map:
            tag_state[tag_name] = new_origin_map
            # Register in-flight windows — retile fires when the last one arrives
            tag_pull_win_ids.update(new_origin_map.keys())
            pending_retile_counts[current_wspace_id] = pending_retile_counts.get(
                current_wspace_id, 0
            ) + len(new_origin_map)


def retile_workspace(workspace_id: int):
    """Apply current tiling rules to one workspace based on its current window count."""
    if workspace_id is None or win_state is None:
        return

    curr_tile_wins = get_windows_by_conditions(
        win_state, workspace_id=workspace_id, is_floating=False
    )
    num_tile_wins = len(curr_tile_wins)

    if num_tile_wins == 0 or num_tile_wins > TILE_TO_N:
        return

    # 1 window -> maximize if enabled
    if MAXIMIZE_SOLOS and num_tile_wins == 1:
        solo_id = tuple(curr_tile_wins.keys())[0]
        maximize_window(win_state, focus_state, solo_id)
        return

    curr_max_wins = get_windows_by_conditions(curr_tile_wins, is_maximized=True)
    num_max_wins = len(curr_max_wins)

    # 2 windows -> collapse solo maximize if needed
    if COLLAPSE_SOLOS_ON_OPEN and num_max_wins == 1 and num_tile_wins == 2:
        solo_max_id = tuple(curr_max_wins.keys())[0]
        collapse_window(win_state, focus_state, solo_max_id)
        num_max_wins -= 1

    if num_max_wins != 0:
        return

    # 3 windows -> force 2|1 layout
    if num_tile_wins == 3:
        niri_action.action("FocusColumnRight")
        sleep(0.02)

        curr_tile_wins = get_windows_by_conditions(
            win_state, workspace_id=workspace_id, is_floating=False
        )
        right_col_wins = [
            wid for wid, wdata in curr_tile_wins.items() if wdata.get("col_idx") == 1
        ]
        if right_col_wins:
            target_id = right_col_wins[0]
            niri_action.action("ConsumeOrExpelWindowRight", id=target_id)
        return

    # 4+ windows -> keep stacking right side
    if 3 < num_tile_wins <= TILE_TO_N:
        newest_id = max(
            curr_tile_wins.keys(),
            key=lambda wid: curr_tile_wins[wid].get("focus_timestamp", 0),
        )
        niri_action.action("ConsumeOrExpelWindowLeft", id=newest_id)


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

# Sanity check. Make sure we have the right version
is_version_ok, version_resp = niri_reader.request("Version")
expected_version, actual_version = (
    "25.11 (b35bcae)",
    version_resp.get("Version", "unknown"),
)
if actual_version != expected_version:
    print(
        "",
        "WARNING - Unexpected niri version!",
        f"expected: {expected_version}",
        f"  actual: {actual_version}",
        "Errors may occur...",
        sep="\n",
    )

cmd_server = TilerCommandServer(TILER_SOCKET_PATH, cmd_queue)
cmd_server.start()
print(f"Command socket: {TILER_SOCKET_PATH}")


# ---------------------------------------------------------------------------------------------------------------------
# %% *** IPC listening loop ***

# Get monitor into
is_outputs_ok, outputs_resp = niri_reader.request("Outputs")
if not is_outputs_ok:
    print("Error requesting info about monitors", outputs_resp, sep="\n")
    quit()
output_full_info = {
    out_key: out_dict["logical"]
    for out_key, out_dict in outputs_resp["Outputs"].items()
}
output_width_lut = {
    out_key: out_info["width"]
    for out_key, out_info in output_full_info.items()
    if out_info is not None
}

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
    pending_retile_wspace: int | None = None
    for evt_name, evt_data in niri_reader.read_eventstream():
        # ── Process any pending tiler commands ─────────────────────────
        while True:
            try:
                cmd = cmd_queue.get_nowait()
                if cmd.startswith("tag:") and win_state and wspace_state:
                    handle_tag_toggle(cmd[4:])
            except Empty:
                break

        # For debugging printouts, add spaces between events that don't occur together
        time_elapsed_ms = timekeeper.get_time_elapsed_ms()
        if ENABLE_EVENT_NAME_DEBUG_PRINT or ENABLE_EVENT_DATA_DEBUG_PRINT:
            if time_elapsed_ms > 250:
                print(
                    "",
                    f"Time elapsed (sec): {(timekeeper.t2 - init_time) // 1000}",
                    sep="\n",
                )
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
            win_state = make_window_state_from_WindowsChanged(
                evt_data, wspace_state, output_width_lut
            )
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
            win_aug_data = get_additional_window_data(
                evt_data["window"], wspace_state, output_width_lut
            )
            win_state[evt_win_id] = {**evt_data["window"], **win_aug_data}
            need_check_rearrange = evt_is_new_window or (
                evt_is_moved_window and APPLY_TO_MOVED_WINDOWS
            )
            newest_window_data = win_state[evt_win_id] if need_check_rearrange else None

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
                win_aug_data = get_additional_window_data(
                    win_state[evt_win_id], wspace_state, output_width_lut
                )
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

        # Handle max-on-close and split-restore-on-close
        if closed_window_data is not None:
            curr_wspace_id = closed_window_data["workspace_id"]
            curr_wins = get_windows_by_conditions(
                win_state, workspace_id=curr_wspace_id, is_floating=False
            )

            if MAXIMIZE_SOLOS_ON_CLOSE and len(curr_wins) == 1:
                # 2 → 1 windows: maximize the remaining solo window
                solo_id = tuple(curr_wins.keys())[0]
                maximize_window(win_state, focus_state, solo_id)

            elif len(curr_wins) == 2:
                # 3 → 2 windows: if both remaining windows are stacked in the same
                # column (because win2 was consumed left when win3 opened), expel
                # the lower one rightward to restore the 1|1 split layout.
                col_indices = {
                    wdata.get("col_idx")
                    for wdata in curr_wins.values()
                    if wdata.get("col_idx") is not None
                }
                if len(col_indices) == 1:  # both windows share the same column
                    expel_win_id = max(
                        curr_wins.keys(),
                        key=lambda wid: curr_wins[wid].get("row_idx") or 0,
                    )
                    niri_action.action("ConsumeOrExpelWindowRight", id=expel_win_id)

        # Handle window-creation behaviors
        if newest_window_data is not None:
            # Ignore newly created maximized or floating windows
            # -> Assume opened maximized windows are done by user window rules (don't want to interfere)
            # -> Tiling logic shouldn't apply to floating windows
            if newest_window_data["is_maximized"] or newest_window_data["is_floating"]:
                continue

            # Don't bother trying to re-arrange/tile if we already have more than 'N' windows
            curr_wspace_id = newest_window_data["workspace_id"]
            curr_tile_wins = get_windows_by_conditions(
                win_state, workspace_id=curr_wspace_id, is_floating=False
            )
            num_tile_wins = len(curr_tile_wins)
            if num_tile_wins == 0 or num_tile_wins > TILE_TO_N:
                continue

            # Auto-maximize solo windows, if needed
            if MAXIMIZE_SOLOS and num_tile_wins == 1:
                solo_id = tuple(curr_tile_wins.keys())[0]
                maximize_window(win_state, focus_state, solo_id)

            # Collapse maximized windows, if needed
            curr_max_wins: dict = get_windows_by_conditions(
                curr_tile_wins, is_maximized=True
            )
            num_max_wins = len(curr_max_wins)
            if COLLAPSE_SOLOS_ON_OPEN and num_max_wins == 1 and num_tile_wins == 2:
                solo_max_id = tuple(curr_max_wins.keys())[0]
                collapse_window(win_state, focus_state, solo_max_id)
                num_max_wins -= 1

            # Apply tiling if needed
            is_zero_max_windows = num_max_wins == 0
            if is_zero_max_windows and (2 < num_tile_wins <= TILE_TO_N):
                if num_tile_wins == 3:
                    mid_wins = [
                        wid
                        for wid, wdata in curr_tile_wins.items()
                        if wdata.get("col_idx") == 1 and wid != newest_window_data["id"]
                    ]
                    target_id = mid_wins[0] if mid_wins else newest_window_data["id"]
                    niri_action.action("FocusColumnRight")
                    niri_action.action("ConsumeOrExpelWindowRight", id=target_id)
                else:
                    niri_action.action(
                        "ConsumeOrExpelWindowLeft", id=newest_window_data["id"]
                    )
            pass

            # ── Deferred retile from tag pull ──────────────────────────────────
            if pending_retile_wspace is not None:
                retile_workspace(pending_retile_wspace)
                pending_retile_wspace = None

except (KeyboardInterrupt, InterruptedError):
    pass

finally:
    cmd_server.stop()
    niri_action.close()
    niri_reader.close()
    print("", f"({os.path.basename(__file__)}) - Closed niri IPC connection", sep="\n")
