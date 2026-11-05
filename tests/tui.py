"""Exercise real terminal input and intermediate selection/rendered states."""
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import struct
import subprocess
import tempfile
import termios
import time

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="snippet-tools-tui-") as temporary:
    state = Path(temporary) / "state.json"
    env = dict(os.environ, TERM="xterm-256color", SNIPPET_TUI_STATE=str(state),
               XDG_CONFIG_HOME=temporary + "/config", XDG_STATE_HOME=temporary + "/state",
               XDG_CACHE_HOME=temporary + "/cache", NVIM_LOG_FILE=temporary + "/nvim.log")
    primary, secondary = pty.openpty()
    fcntl.ioctl(secondary, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    child = subprocess.Popen([os.environ.get("NVIM", shutil.which("nvim")), "-u", "tests/tui_init.lua",
                              "-i", "NONE", "-n"], cwd=root, env=env, stdin=secondary,
                             stdout=secondary, stderr=secondary, start_new_session=True)
    os.close(secondary)
    output = bytearray()
    frames = []

    def wait(predicate, label):
        deadline = time.monotonic() + 4
        latest = None
        while time.monotonic() < deadline:
            if select.select([primary], [], [], 0.01)[0]:
                try:
                    output.extend(os.read(primary, 65536))
                except OSError:
                    break
            try:
                latest = json.loads(state.read_text())
            except (FileNotFoundError, json.JSONDecodeError):
                continue
            assert not latest["errors"], latest
            if predicate(latest):
                frames.append(dict(label=label, **latest))
                return latest
        raise AssertionError(f"{label}: {latest}, exit={child.poll()}, tail={output[-1400:]!r}")

    def send(data):
        os.write(primary, data)

    def reset(kind):
        send(b"\x1b\x1b")
        wait(lambda s: s["mode"] == "n", "normal")
        send(f":lua snippet_tui_reset('{kind}')\r".encode())
        wait(lambda s: s["lines"] == [""] and s["mode"] == "n", "reset " + kind)

    f5, f6, f7, f8 = b"\x1b[15~", b"\x1b[17~", b"\x1b[18~", b"\x1b[19~"
    try:
        wait(lambda s: s["mode"] == "n", "startup")
        reset("mirror")
        send(b"i" + f5)
        selection = wait(lambda s: s["mode"] == "s" and "hello world / world!" in s["screen"], "rendered selection")
        assert selection["session"]["current"] == "root/1", selection
        send("中文".encode())
        wait(lambda s: s["lines"] == ["hello 中文 / 中文!"] and s["mode"] == "i", "live mirror")
        send(b"\t!")
        wait(lambda s: s["lines"] == ["hello 中文 / 中文!!"] and not s["session"]["active"], "final stop")

        reset("choice")
        send(b"i" + f5 + b"green" + f6)
        wait(lambda s: s["lines"] == ["blue=blue"] and s["mode"] == "s", "choice switched")
        send(f7)
        wait(lambda s: s["lines"] == ["green=green"] and s["mode"] == "s", "choice restored")

        reset("dynamic")
        send(b"i" + f5 + b"60")
        wait(lambda s: s["lines"] == ["60/38"] and "60/38" in s["screen"], "dependent function rendered")
        send(b"\t!")
        wait(lambda s: s["lines"] == ["60/38!"], "function final stop")

        reset("nested")
        send(b"i" + f5)
        wait(lambda s: s["mode"] == "s", "outer selection")
        send(f8)
        wait(lambda s: s["mode"] == "s" and s["session"]["depth"] == 2, "inner selection")
        send(b"X\t\tY\t!")
        wait(lambda s: s["lines"] == ["[(X)]=(X):Y!"] and not s["session"]["active"], "nested burst")

        reset("auto")
        send(b"imk")
        wait(lambda s: s["lines"] == ["[]"] and s["mode"] == "i", "auto expansion")
        send(b"\x1bu")
        wait(lambda s: s["lines"] == ["mk"] and not s["session"]["active"], "auto undo restores trigger")
        send(b"\x12")
        wait(lambda s: s["lines"] == ["[]"], "auto redo")

        reset("auto")
        send(b"imkX\t!")
        wait(lambda s: s["lines"] == ["[X]!"] and not s["session"]["active"], "auto burst")

        if env.get("COMPLETION_TOOLS_PATH"):
            reset("completion")
            send(b"igr")
            wait(lambda s: s["menu"], "completion menu")
            send(b"\t")
            wait(lambda s: s["mode"] == "s" and not s["menu"], "completion placeholder selection")
            send(b"user\t!")
            wait(lambda s: s["lines"] == ["hello user / user!"] and not s["session"]["active"], "completion burst")
        reset("display")
        send(b"i" + f5)
        shown = wait(lambda s: s["session"]["active"] and s["mode"] == "i"
                     and "I" in s["display_rows"][0] and "cred" in s["display_rows"][1],
                     "empty field and passive choice markers rendered")
        assert shown["display_rows"][0].count("I") == 2, shown  # Sign and inline marker.
        send(b"X\t")
        shown = wait(lambda s: s["mode"] == "s" and "Cred" in s["display_rows"][1]
                     and "iX" in s["display_rows"][0], "active choice marker and passive insert rendered")
        assert shown["display_rows"][1].count("C") == 2, shown
        send(f6)
        wait(lambda s: "Cblue" in s["display_rows"][1], "choice rebuild retains decoration")
        send(b"\tBody")
        wait(lambda s: s["lines"] == ["X", "blue", "Body"] and not s["session"]["active"]
             and "I" not in s["display_rows"][0] and "C" not in s["display_rows"][1]
             and "i" not in "".join(s["display_rows"]), "all field markers removed on finish")
        reset("display_eol")
        send(b"i" + f5)
        shown = wait(lambda s: s["session"]["active"] and s["mode"] == "i" and s["lines"] == ["[]-[]-"],
                     "same-line markers ready")
        assert shown["screen"].split("[]-[]-", 1)[1].replace(" ", "") == "Iii", shown
        send(b"\t")
        shown = wait(lambda s: s["session"].get("current") == "root/2" and s["mode"] == "i", "second same-line field")
        assert shown["screen"].split("[]-[]-", 1)[1].replace(" ", "") == "iIi", shown
        send(b"X\x1b[Z")
        shown = wait(lambda s: s["session"].get("current") == "root/1" and s["mode"] == "i"
                     and s["lines"] == ["[]-[X]-"], "previous field retains first marker position")
        assert shown["screen"].split("[]-[X]-", 1)[1].replace(" ", "") == "Iii", shown
        send(b"A\t")
        shown = wait(lambda s: s["session"].get("current") == "root/2" and s["mode"] == "s", "next field retains second marker position")
        assert shown["screen"].split("[A]-[X]-", 1)[1].replace(" ", "") == "iIi", shown
        send(b"\t!")
        wait(lambda s: s["lines"] == ["[A]-[X]-!"] and not s["session"]["active"]
             and "I" not in s["screen"] and "i" not in s["screen"], "same-line markers cleared on exit")
        if env.get("SNIPPET_TUI_TRACE"):
            Path(env["SNIPPET_TUI_TRACE"]).write_text(json.dumps(frames, ensure_ascii=False, indent=2))
        print(f"PTY: {len(frames)} intermediate states passed")
    finally:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        os.close(primary)
