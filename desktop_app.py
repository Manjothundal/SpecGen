"""
desktop_app.py - Run SpecGen as a native desktop window instead of
"start app.py, open a browser to localhost:5000".

Wraps app.py's existing Flask app UNCHANGED — starts it on a background
thread, then opens a pywebview window (the OS's native webview: WebView2/
Edge on Windows) pointed at it. Own window, own icon/taskbar entry, no
browser address bar or tabs. Every route, background job, and template in
app.py works exactly as it does today; this file only adds the window.

Still needs Python and this project's dependencies installed on the
machine running it (see requirements.txt) — a fully standalone .exe with
no Python required is a separate, bigger step (PyInstaller bundling
chromadb/onnxruntime, pyreadstat, langgraph, ...; see ROADMAP.md's
"Package as Windows .exe" backlog item).

Usage:
  python desktop_app.py
"""

import socket
import threading
import time

import webview

import app as app_module

HOST = "127.0.0.1"
PORT = 5000


def _run_flask():
    # debug=False here (unlike app.py's own __main__, which wants
    # traceback pages for local dev over a browser) — a debugger/reloader
    # restart inside a background thread is more likely to wedge the
    # whole desktop window than help. use_reloader=False for the same
    # file-watcher-misfires-mid-request reason app.py's own __main__
    # already disables it.
    app_module.app.run(host=HOST, port=PORT, debug=False, use_reloader=False)


def _wait_for_server(timeout=15):
    """create_window() loads its URL immediately — poll the port first so
    the window doesn't race Flask's own startup and show a connection
    error before the server has finished binding."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((HOST, PORT), timeout=0.5):
                return
        except OSError:
            time.sleep(0.2)
    raise RuntimeError(f"SpecGen server didn't start on {HOST}:{PORT} within {timeout}s")


if __name__ == "__main__":
    server_thread = threading.Thread(target=_run_flask, daemon=True)
    server_thread.start()
    _wait_for_server()

    webview.create_window(
        "SpecGen",
        f"http://{HOST}:{PORT}/",
        width=1280,
        height=860,
        min_size=(900, 600),
    )
    webview.start()
