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
        expected = ["pre  tail"] if kind == "region" else [""]
        wait(lambda s: s["lines"] == expected and s["mode"] == "n", "reset " + kind)

    f5, f6, f7, f8 = b"\x1b[15~", b"\x1b[17~", b"\x1b[18~", b"\x1b[19~"
    try:
        wait(lambda s: s["mode"] == "n", "startup")
        reset("project")
        send(b"ipj\t")
        wait(lambda s: s["mode"] == "s" and s["lines"] == ["[value]=value"], "project wins global trigger")
        send(b"X" + f8 + b"Y")
        wait(lambda s: s["mode"] == "i" and s["lines"] == ["[XY]=XY"] and s["session"]["active"],
             "project reload retains the active field and mirror")
        send(b"\t!\x1bggdGipj\t")
        wait(lambda s: s["mode"] == "s" and s["lines"] == ["<new>"], "project replacement applies on next expansion")
        send(b"Z\t!\x1b:lua snippet_tui_outside()\r")
        wait(lambda s: s["mode"] == "n" and s["lines"] == [""], "outside buffer")
        send(b"ipj\t")
        wait(lambda s: s["mode"] == "s" and s["lines"] == ["global:outside"], "outside project uses global snippets")

        reset("mirror")
        send(b"i" + f5)
        selection = wait(lambda s: s["mode"] == "s" and "hello world / world!" in s["screen"], "rendered selection")
        assert selection["session"]["current"] == "root/1", selection
        send("中文".encode())
        wait(lambda s: s["lines"] == ["hello 中文 / 中文!"] and s["mode"] == "i", "live mirror")
        send(b"\t!")
        wait(lambda s: s["lines"] == ["hello 中文 / 中文!!"] and not s["session"]["active"], "final stop")

        reset("region")
        send(b"i" + f5)
        wait(lambda s: s["mode"] == "s" and s["session"]["range"] == [[0, 4], [0, 11]]
             and "pre [field] tail" in s["screen"], "same-line snippet with prefix and suffix")
        send(b"\x1b6l")
        wait(lambda s: s["mode"] == "n" and s["cursor"] == [1, 11] and not s["session"]["active"],
             "first suffix character ends the session")

        reset("region")
        send(b"i" + f5 + b"X")
        wait(lambda s: s["mode"] == "i" and s["lines"] == ["pre [X] tail"] and s["session"]["active"],
             "same-line field replacement stays active")
        send(b"\x1b[F\t!")
        wait(lambda s: s["mode"] == "i" and s["lines"] == ["pre [X] tail    !"]
             and not s["session"]["active"], "moving past suffix then Tab does not jump back")

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

        reset("formatted")
        send(b"i" + f5)
        wait(lambda s: s["mode"] == "s" and s["lines"] == ["\\begin{table}", "  ", "\\end{table}"]
             and "\\begin{table}" in s["screen"], "formatted environment rendered")
        send(b"figure")
        wait(lambda s: s["lines"] == ["\\begin{figure}", "  ", "\\end{figure}"]
             and "\\begin{figure}" in s["screen"], "repeated named placeholder mirrors through terminal")
        send(b"\tBody")
        wait(lambda s: s["lines"] == ["\\begin{figure}", "  Body", "\\end{figure}"]
             and not s["session"]["active"], "formatted final stop")

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
        assert shown["display_rows"][2].strip() == "e e", shown  # Distinct final-stop sign and marker.
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
        assert shown["screen"].split("[]-[]-", 1)[1].replace(" ", "") == "Iie", shown
        send(b"\t")
        shown = wait(lambda s: s["session"].get("current") == "root/2" and s["mode"] == "i", "second same-line field")
        assert shown["screen"].split("[]-[]-", 1)[1].replace(" ", "") == "iIe", shown
        send(b"X\x1b[Z")
        shown = wait(lambda s: s["session"].get("current") == "root/1" and s["mode"] == "i"
                     and s["lines"] == ["[]-[X]-"], "previous field retains first marker position")
        assert shown["screen"].split("[]-[X]-", 1)[1].replace(" ", "") == "Iie", shown
        send(b"A\t")
        shown = wait(lambda s: s["session"].get("current") == "root/2" and s["mode"] == "s", "next field retains second marker position")
        assert shown["screen"].split("[A]-[X]-", 1)[1].replace(" ", "") == "iIe", shown
        send(b"\t!")
        wait(lambda s: s["lines"] == ["[A]-[X]-!"] and not s["session"]["active"]
             and "I" not in s["screen"] and "i" not in s["screen"], "same-line markers cleared on exit")
        reset("display_overflow")
        send(b"i" + f5)
        source = "[]-" * 7
        shown = wait(lambda s: s["session"].get("current") == "root/1" and s["mode"] == "i",
                     "overflow markers ready")
        start = shown["screen"].index(source) + len(source)
        assert shown["screen"][start:].replace(" ", "") == "Iiiii...", shown
        active_attr = shown["display_attrs"][0][shown["screen"].index("I", start)]
        passive_attr = shown["display_attrs"][0][shown["screen"].index("...", start)]
        assert active_attr != passive_attr, shown
        for target in range(2, 8):
            send(b"\t")
            shown = wait(lambda s: s["session"].get("current") == f"root/{target}" and s["mode"] == "i",
                         f"overflow field {target}")
            markers = "i" * (target - 1) + "I" + "i" * (5 - target) if target <= 5 else "iiiii"
            assert shown["screen"][start:].replace(" ", "") == markers + "...", shown
            dot = shown["screen"].index("...", start)
            expected = active_attr if target > 5 else passive_attr
            assert shown["display_attrs"][0][dot:dot+3] == [expected] * 3, shown
        send(b"\x1b[Z" * 3)
        shown = wait(lambda s: s["session"].get("current") == "root/4" and s["mode"] == "i",
                     "return from hidden to visible field")
        assert shown["screen"][start:].replace(" ", "") == "iiiIi...", shown
        dot = shown["screen"].index("...", start)
        assert shown["display_attrs"][0][dot:dot+3] == [passive_attr] * 3, shown
        send(b"\t" * 4)
        wait(lambda s: not s["session"]["active"] and s["lines"] == [source]
             and not s["screen"][start:].strip(), "overflow marker clears on exit")
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
