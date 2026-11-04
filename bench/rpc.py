"""Small MessagePack RPC client; multiplexes native PTY output while receiving UI frames."""
import os
import select
import socket
import struct
import time

def answer_terminal(pty, data, state=None):
    if state is None: state={}
    tail=state.get("tail",b"")
    stream=tail+data
    responses = {b"\x1b[5n": b"\x1b[0n", b"\x1b[6n": b"\x1b[1;1R", b"\x1b[?u": b"\x1b[?0u",
                 b"\x1b[c": b"\x1b[?1;2c", b"\x1b[>c": b"\x1b[>0;1;0c",
                 b"\x1b]11;?\x07": b"\x1b]11;rgb:0000/0000/0000\x07",
                 b"\x1b]10;?\x07": b"\x1b]10;rgb:dddd/dddd/dddd\x07"}
    responses[b"\x1b]11;?\x1b\\"] = b"\x1b]11;rgb:0000/0000/0000\x1b\\"
    responses[b"\x1b]10;?\x1b\\"] = b"\x1b]10;rgb:dddd/dddd/dddd\x1b\\"
    for query, response in responses.items():
        at=stream.find(query)
        while at>=0:
            if at+len(query)>len(tail): os.write(pty,response)
            at=stream.find(query,at+1)
    state["tail"]=stream[-32:]


def pack(value):
    if value is None:
        return b"\xc0"
    if isinstance(value, bool):
        return b"\xc3" if value else b"\xc2"
    if isinstance(value, int):
        return b"\xd3" + struct.pack(">q", value)
    if isinstance(value, float):
        return b"\xcb" + struct.pack(">d", value)
    if isinstance(value, str):
        raw = value.encode()
        return b"\xdb" + struct.pack(">I", len(raw)) + raw
    if isinstance(value, (list, tuple)):
        return b"\xdd" + struct.pack(">I", len(value)) + b"".join(pack(v) for v in value)
    if isinstance(value, dict):
        return b"\xdf" + struct.pack(">I", len(value)) + b"".join(pack(k) + pack(v) for k, v in value.items())
    raise TypeError(type(value).__name__)


def unpack(read):
    def number(fmt):
        return struct.unpack(fmt, read(struct.calcsize(fmt)))[0]

    head = read(1)[0]
    if head < 0x80:
        return head
    if head >= 0xE0:
        return head - 256
    if 0xA0 <= head <= 0xBF:
        return read(head & 31).decode()
    if 0x90 <= head <= 0x9F:
        return [unpack(read) for _ in range(head & 15)]
    if 0x80 <= head <= 0x8F:
        return {unpack(read): unpack(read) for _ in range(head & 15)}
    if head in (0xC0, 0xC2, 0xC3):
        return {0xC0: None, 0xC2: False, 0xC3: True}[head]
    formats = {0xCA: ">f", 0xCB: ">d", 0xCC: ">B", 0xCD: ">H", 0xCE: ">I", 0xCF: ">Q",
               0xD0: ">b", 0xD1: ">h", 0xD2: ">i", 0xD3: ">q"}
    if head in formats:
        return number(formats[head])
    sizes = {0xC4: ">B", 0xC5: ">H", 0xC6: ">I", 0xD9: ">B", 0xDA: ">H", 0xDB: ">I",
             0xDC: ">H", 0xDD: ">I", 0xDE: ">H", 0xDF: ">I", 0xC7: ">B", 0xC8: ">H", 0xC9: ">I"}
    if head in sizes:
        size = number(sizes[head])
        if head in (0xDC, 0xDD):
            return [unpack(read) for _ in range(size)]
        if head in (0xDE, 0xDF):
            return {unpack(read): unpack(read) for _ in range(size)}
        if head in (0xC7, 0xC8, 0xC9):
            read(1)
        raw = read(size)
        return raw.decode() if head in (0xD9, 0xDA, 0xDB) else raw
    if 0xD4 <= head <= 0xD8:
        read(1)
        return read(1 << (head - 0xD4))
    raise ValueError(f"Unsupported MessagePack prefix {head:#x}")


class Client:
    def __init__(self, path, pty, timeout=5, terminal_state=None):
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.connect(str(path))
        self.socket.setblocking(False)
        self.pty, self.timeout = pty, timeout
        self.buffer, self.terminal = bytearray(), bytearray()
        self.serial, self.responses = 0, {}
        self.results, self.flush_ns = {}, 0
        self.awaiting_id = None
        self.received_ns = 0
        self.terminal_state=terminal_state or {}
        self.grid, self.frame_results = [], {}
        self.channel = self.request("nvim_get_api_info", [])[0]

    def terminal_output(self, data):
        self.terminal.extend(data)
        if len(self.terminal)>65536:
            del self.terminal[:-65536]
        answer_terminal(self.pty,data,self.terminal_state)

    def read(self, count):
        deadline = time.monotonic() + self.timeout
        while len(self.buffer) < count:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"RPC stream timed out; terminal tail {self.terminal[-700:]!r}")
            ready, _, _ = select.select([self.socket, self.pty], [], [], remaining)
            if self.pty in ready:
                try:
                    self.terminal_output(os.read(self.pty, 262144))
                except OSError:
                    pass
            if self.socket in ready:
                data = self.socket.recv(max(65536, count))
                self.received_ns = time.perf_counter_ns()
                if not data:
                    raise EOFError("Neovim closed RPC")
                self.buffer.extend(data)
        result = bytes(self.buffer[:count])
        del self.buffer[:count]
        return result

    def redraw(self, events):
        for name, *calls in events:
            if name == "flush":
                self.flush_ns = self.received_ns
                if self.awaiting_id in self.results:
                    self.frame_results[self.awaiting_id] = self.flush_ns
            for args in calls:
                if name == "grid_resize" and args[0] == 1:
                    self.grid = [[" "] * args[1] for _ in range(args[2])]
                elif name == "grid_clear" and args[0] == 1:
                    self.grid = [[" "] * len(self.grid[0]) for _ in self.grid]
                elif name == "grid_line" and args[0] == 1:
                    _, row, col, cells, *_ = args
                    for cell in cells:
                        for _ in range(cell[2] if len(cell) > 2 else 1):
                            self.grid[row][col] = cell[0]
                            col += 1

    def pump(self):
        message = unpack(self.read)
        if message[0] == 1:
            self.responses[message[1]] = message[2:]
        elif message[0] == 2 and message[1] == "redraw":
            self.redraw(message[2])
        elif message[0] == 2 and message[1] == "snippet_bench_done":
            result = message[2][0]
            self.results[result["id"]] = result
        return message

    def request(self, method, args):
        self.serial += 1
        serial = self.serial
        self.socket.sendall(pack([0, serial, method, args]))
        while serial not in self.responses:
            self.pump()
        error, result = self.responses.pop(serial)
        if error is not None:
            raise RuntimeError(error)
        return result

    def lua(self, code, *args):
        return self.request("nvim_exec_lua", [code, list(args)])

    def sample(self, sample_id, payload):
        self.lua("SnippetBench.arm(...)", sample_id, self.channel)
        self.awaiting_id = sample_id
        started = time.perf_counter_ns()
        os.write(self.pty, b"\x1b[21~" + payload.encode() + b"\x1b[24~")  # F10, input, F12
        while sample_id not in self.frame_results:
            self.pump()
        frame = self.frame_results.pop(sample_id)
        result = self.results.pop(sample_id)
        result["ui_ms"] = (frame - started) / 1e6
        self.awaiting_id = None
        if result["valid"]:
            # Text/state validation is performed in Lua. Also verify that an
            # ext_linegrid frame was actually delivered for this operation.
            result["frame_rows"] = len(self.grid)
        return result

    def close(self):
        self.socket.close()
