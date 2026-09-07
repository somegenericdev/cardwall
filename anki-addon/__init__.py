"""
Cardwall add-on
───────────────
Opens a Unix domain socket at CARDWALL_SOCKET_PATH (default
/run/user/<uid>/cardwall.sock) and answers simple JSON queries
from the Cardwall session binary.

Protocol (newline-terminated JSON):
  request : {"cmd": "due_count"}
  response: {"due": <int>}
  response: {"error": "<message>"}
"""

import json
import os
import socket
import threading

from aqt import gui_hooks, mw
from aqt.theme import Theme, theme_manager
from aqt.utils import showInfo

SOCKET_ENV = "CARDWALL_SOCKET_PATH"
DARK_MODE = os.environ.get("CARDWALL_DARK_MODE", "1") != "0"


def _socket_path() -> str:
    env = os.environ.get(SOCKET_ENV)
    if env:
        return env
    uid = os.getuid()
    run_dir = f"/run/user/{uid}"
    os.makedirs(run_dir, exist_ok=True)
    return os.path.join(run_dir, "cardwall.sock")


def _due_count() -> int:
    """Return the number of cards due right now across all decks.

    col.sched.counts() is scoped to whatever deck is currently
    "selected" (e.g. the last deck opened in the Reviewer) and does
    NOT reflect the whole collection, so it can read 0 even while
    other decks still have cards due. deck_due_tree() gives per-deck
    totals that already include each deck's subdecks, so summing the
    top-level decks yields a real collection-wide total.
    """
    col = mw.col
    if col is None:
        raise RuntimeError("collection not loaded")
    tree = col.sched.deck_due_tree()
    return sum(
        child.new_count + child.learn_count + child.review_count
        for child in tree.children
    )


def _handle_client(conn: socket.socket) -> None:
    try:
        data = b""
        while not data.endswith(b"\n"):
            chunk = conn.recv(256)
            if not chunk:
                return
            data += chunk

        try:
            req = json.loads(data.decode().strip())
        except json.JSONDecodeError as exc:
            _send(conn, {"error": f"invalid JSON: {exc}"})
            return

        if req.get("cmd") == "due_count":
            try:
                count = _due_count()
                _send(conn, {"due": count})
            except Exception as exc:  # noqa: BLE001
                _send(conn, {"error": str(exc)})
        else:
            _send(conn, {"error": "unknown command"})
    finally:
        conn.close()


def _send(conn: socket.socket, payload: dict) -> None:
    conn.sendall((json.dumps(payload) + "\n").encode())


def _server_loop(sock: socket.socket) -> None:
    while True:
        try:
            conn, _ = sock.accept()
        except OSError:
            # socket was closed – time to exit
            break
        threading.Thread(target=_handle_client, args=(conn,), daemon=True).start()


_server_sock: socket.socket | None = None


def _start_server() -> None:
    global _server_sock
    path = _socket_path()

    # Remove stale socket file if it exists
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(path)
    os.chmod(path, 0o600)
    sock.listen(4)
    _server_sock = sock

    t = threading.Thread(target=_server_loop, args=(sock,), daemon=True)
    t.start()


def _force_dark_mode() -> None:
    if not DARK_MODE:
        return
    mw.pm.set_theme(Theme.DARK)
    mw.pm.save()
    theme_manager.apply_style()


# Anki calls this when the add-on is loaded.
_start_server()
gui_hooks.profile_did_open.append(_force_dark_mode)
