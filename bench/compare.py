#!/usr/bin/env python3
"""Reproducible LuaSnip/snippet-tools component and real-PTY comparison.

Only benchmark child processes are configured; the user's active editor and
configuration files are never changed. Outputs include every raw sample.
"""
import argparse
import atexit
import datetime
import errno
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import pty
import random
import select
import shutil
import statistics
import subprocess
import tempfile
import termios
import tty
import time
import struct

from rpc import Client, answer_terminal

ROOT = Path(__file__).resolve().parent.parent
ENGINES = ("snippet-tools", "luasnip")


def command(args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True, stderr=subprocess.STDOUT).strip()


def revision(path):
    try:
        return {"path": str(path), "head": command(["git", "rev-parse", "HEAD"], path),
                "status": command(["git", "status", "--short"], path)}
    except subprocess.CalledProcessError:
        return {"path": str(path)}


def summary(values):
    if not values:
        return None
    values = sorted(values)
    def quantile(q):
        return values[max(0, math.ceil(q * len(values)) - 1)]
    return {"n": len(values), "median": statistics.median(values), "p95": quantile(.95),
            "p99": quantile(.99), "min": values[0], "max": values[-1]}


def environment(args, directory, engine, track):
    for sub in ("cache","state/nvim","config"):
        (directory/sub).mkdir(parents=True,exist_ok=True)
    env = dict(os.environ, SNIPPET_BENCH_ROOT=str(ROOT), SNIPPET_BENCH_LUASNIP=str(args.luasnip),
               SNIPPET_BENCH_ENGINE=engine, SNIPPET_BENCH_TRACK=track,
               SNIPPET_BENCH_RESULT=str(directory / "core.json"),
               SNIPPET_BENCH_CORE_SAMPLES=str(args.core_samples),
               NVIM_LOG_FILE=str(directory / "nvim.log"),
               XDG_CACHE_HOME=str(directory / "cache"), XDG_STATE_HOME=str(directory / "state"),
               TERM="xterm-256color", NVIM_SMOKE_TEST="1", SSH_CONNECTION="")
    if track != "configured":
        env["XDG_CONFIG_HOME"] = str(directory / "config")
    return env


def core(args, engine, load_only):
    with tempfile.TemporaryDirectory(prefix="snippet-core-") as name:
        directory = Path(name)
        env = environment(args, directory, engine, "isolated")
        if load_only:
            env["SNIPPET_BENCH_LOAD_ONLY"] = "1"
        subprocess.run([args.nvim, "--headless", "-u", "NONE", "--noplugin", "-i", "NONE",
                        "-n", "-l", str(ROOT / "bench/isolated.lua")],
                       env=env, cwd=ROOT, check=True, capture_output=True, timeout=180)
        return json.loads((directory / "core.json").read_text())


class InputProcess:
    def __init__(self, args, engine, track):
        self.closed=False
        atexit.register(self.close)
        self.args, self.engine, self.track = args, engine, track
        self.temporary = tempfile.TemporaryDirectory(prefix="snippet-pty-")
        directory = Path(self.temporary.name)
        env = environment(args, directory, engine, track)
        env["SNIPPET_BENCH_READY"] = str(directory / "ready")
        path = directory / "rpc.sock"
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 36, 120, 0, 0))
        tty.setraw(slave)
        filename = directory / ("trial.md" if track == "configured" else "trial.txt")
        filename.write_text("")
        env["SNIPPET_BENCH_FILE"] = str(filename)
        if track == "configured":
            env.update(NVIM_CONFIG_ROOT=str(args.config_root), NVIM_TEST_SCENARIO="writing")
            shutil.copy2(args.config_root / "lazy-lock.json", directory / "lazy-lock.json")
            env["NVIM_LAZY_LOCKFILE"] = str(directory / "lazy-lock.json")
            cmd = [args.nvim, "-i", "NONE", "-n", "--listen", str(path), "--cmd",
                   "lua dofile(vim.env.NVIM_CONFIG_ROOT .. '/tests/setup.lua')",
                   "-u", str(args.config_root / "init.lua"), "-c",
                   "lua dofile(vim.env.SNIPPET_BENCH_ROOT .. '/bench/configured.lua')", str(filename)]
        else:
            cmd = [args.nvim, "--noplugin", "-i", "NONE", "-n", "--listen", str(path),
                   "-u", str(ROOT / "bench/init.lua"), str(filename)]
        cmd += ["-c", "lua vim.fn.writefile({'ready'},vim.env.SNIPPET_BENCH_READY)"]
        self.process = subprocess.Popen(cmd, cwd=ROOT, env=env, stdin=slave, stdout=slave,
                                        stderr=slave, start_new_session=True)
        os.close(slave)
        terminal = bytearray()
        terminal_state={}
        deadline = time.monotonic() + 10
        while not path.exists() or not (directory / "ready").exists():
            if self.process.poll() is not None or time.monotonic() > deadline:
                self.close()
                raise RuntimeError(f"Neovim failed to expose its socket: {terminal[-1200:]!r}")
            if select.select([self.master], [], [], .01)[0]:
                data=os.read(self.master, 262144)
                answer_terminal(self.master,data,terminal_state)
                terminal.extend(data)
        self.client = Client(path, self.master,terminal_state=terminal_state)
        self.client.request("nvim_ui_attach", [120, 36, {"rgb": True, "ext_linegrid": True}])
        self.wait("return SnippetBench~=nil")
        self.cases = self.client.lua("return SnippetBench.cases")
        self.policy = self.client.lua("return SnippetBench.engine_policy")
        self.editor_pid = self.client.lua("return vim.fn.getpid()")
        self.policy["startup_messages"]=self.client.lua("return vim.api.nvim_exec2('messages',{output=true}).output")
        if "E1568" in self.policy["startup_messages"]:
            raise RuntimeError("Terminal handshake timed out; refusing to collect timings")
        self.serial = 0

    def wait(self, code, *args):
        deadline = time.monotonic() + 5
        while not self.client.lua(code, *args):
            if time.monotonic() > deadline:
                state = self.client.lua("local labels={};local cmp=package.loaded.completion_tools;if cmp then for _,v in ipairs(cmp.get_items())do labels[#labels+1]=v.label end end;return {mode=vim.api.nvim_get_mode().mode,lines=vim.api.nvim_buf_get_lines(0,0,-1,false),items=labels,context=cmp and cmp.get_context(),errors=SnippetBench and SnippetBench.errors,messages=vim.api.nvim_exec2('messages',{output=true}).output}")
                raise TimeoutError(f"Preparation failed: {code}: {state}")
            time.sleep(.001)  # Preparation only; never used for measured completion.

    def prepare(self, case):
        self.client.request("nvim_input", ["<Esc><Esc>"])
        self.wait("return vim.api.nvim_get_mode().mode=='n'")
        self.client.lua("return SnippetBench.prepare(...)", case["name"])
        for stage in case["pre"]:
            if case.get("normalize_undo_key")==stage["keys"]:
                self.client.lua("vim.o.undolevels=vim.o.undolevels")
            os.write(self.master, stage["keys"].encode())
            self.wait("return SnippetBench.matches(...)", stage)
        # Drain the preparation's UI updates before arming a measured operation.
        self.client.lua("vim.cmd('redraw!')")

    def sample(self, case):
        self.prepare(case)
        self.serial += 1
        result = self.client.sample(self.serial, case["action"])
        if result["valid"]:
            prefix = case["lines"][0][:50].rstrip()
            frame = "\n".join("".join(row) for row in self.client.grid)
            if prefix and prefix not in frame:
                result["valid"] = False
                result["diagnostic"] = {"reason": "Expected visible text missing from UI frame", "prefix": prefix, "frame": frame}
        return result

    def snapshot(self):
        self.client.request("nvim_input", ["<Esc><Esc>"])
        self.wait("return vim.api.nvim_get_mode().mode=='n'")
        self.client.lua("SnippetBench.prepare('session_cycle')")
        self.client.lua("vim.wait(1)")
        result = self.client.lua("return SnippetBench.snapshot()")
        result["rss_kib"] = int(command(["ps", "-o", "rss=", "-p", str(self.editor_pid)]))
        return result

    def close(self):
        if self.closed:return
        self.closed=True
        atexit.unregister(self.close)
        if hasattr(self, "client"):
            # The native TUI may be a frontend for an embedded editor. Ask the
            # editor to exit before removing caches that its workers still write.
            try:
                self.client.lua("vim.cmd('qa!')")
            except (EOFError, OSError, RuntimeError, TimeoutError):
                pass
            self.client.close()
        if hasattr(self, "process") and self.process.poll() is None:
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill(); self.process.wait()
        if hasattr(self, "master"):
            os.close(self.master)
        for attempt in range(3):
            try:
                self.temporary.cleanup()
                break
            except OSError as error:
                if error.errno != errno.ENOTEMPTY or attempt == 2:
                    raise
                time.sleep(.02)  # Exit/cache race only; outside every timed interval.


def input_run(args, engine, track, round_id):
    proc = InputProcess(args, engine, track)
    result = {"engine": engine, "track": track, "round": round_id, "policy": proc.policy, "cases": []}
    try:
        cases = [case for case in proc.cases if not case.get("memory")]
        random.Random(args.seed + round_id).shuffle(cases)
        for case in cases:
            samples, failures = [], []
            for i in range(args.warmup + args.samples):
                try:
                    sample = proc.sample(case)
                except (TimeoutError,RuntimeError) as error:
                    sample={"valid":False,"diagnostic":{"error":str(error)}}
                if not sample["valid"]:
                    failures.append(sample)
                    print(f"    validation failure: {sample.get('diagnostic')}",flush=True)
                    # Stop a broken case rather than timing an incorrect fast path.
                    break
                if i >= args.warmup:
                    samples.append({"state_ms": sample["state_ms"], "ui_ms": sample["ui_ms"]})
            result["cases"].append({"name": case["name"], "samples": samples, "failures": failures,
                "semantics":case.get("semantics"),"normalized_undo":bool(case.get("normalize_undo_key"))})
            print(f"  {track}/{engine}/{case['name']}: n={len(samples)} failed={len(failures)}", flush=True)
    finally:
        proc.close()
    return result


def memory_run(args, engine):
    proc = InputProcess(args, engine, "isolated")
    try:
        case = next(case for case in proc.cases if case.get("memory"))
        memory_warmup=max(args.warmup,100)
        for _ in range(memory_warmup):
            assert proc.sample(case)["valid"]
        phases = [{"cycles": 0, **proc.snapshot()}]
        checkpoints = sorted(set([min(100, args.memory_cycles), args.memory_cycles // 2, args.memory_cycles]))
        for i in range(1, args.memory_cycles + 1):
            sample = proc.sample(case)
            assert sample["valid"], sample
            if i in checkpoints:
                phases.append({"cycles": i, **proc.snapshot()})
        return {"engine": engine, "policy": proc.policy, "warmup_cycles":memory_warmup,"phases": phases}
    finally:
        proc.close()


def aggregate(result):
    groups = {}
    def group(key):
        return groups.setdefault(key, {"samples": [], "failures": 0, "rounds": []})
    for run in result["startup"]:
        for name in ("require_ms", "setup_ms", "module_heap_kib"):
            g=group(("startup", run["engine"], name))
            g["samples"].append(run[name])
            if name=="module_heap_kib": g["unit"]="KiB"
    for run in result["core"]:
        for case in run["cases"]:
            g = group(("core", run["engine"], case["name"]))
            g["samples"].extend(case["samples"])
            g["unit"] = case["unit"]
    for run in result["input"]:
        for case in run["cases"]:
            for endpoint in ("state_ms", "ui_ms"):
                g = group((run["track"], run["engine"], case["name"] + "/" + endpoint))
                values = [s[endpoint] for s in case["samples"]]
                g["samples"].extend(values)
                g["failures"] += len(case["failures"])
                g["rounds"].append({"round": run["round"], "summary": summary(values)})
    result["summary"] = [{"track": key[0], "engine": key[1], "name": key[2],
        "stats": summary(g["samples"]), "failures": g["failures"], "rounds": g["rounds"], "unit": g.get("unit", "ms")}
        for key, g in sorted(groups.items())]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nvim", default=shutil.which("nvim"))
    parser.add_argument("--luasnip", type=Path, default=Path.home() / ".local/share/nvim/lazy/LuaSnip")
    parser.add_argument("--config-root", type=Path, default=Path.home() / ".config/nvim")
    parser.add_argument("--mode", choices=("all", "isolated", "configured"), default="all")
    parser.add_argument("--samples", type=int, default=250, help="input samples per case per round")
    parser.add_argument("--warmup", type=int, default=50)
    parser.add_argument("--rounds", type=int, default=4)
    parser.add_argument("--startup-runs", type=int, default=20)
    parser.add_argument("--core-samples", type=int, default=200)
    parser.add_argument("--memory-cycles", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=20261105)
    parser.add_argument("--resume",action="store_true",help="resume identical input protocol from saved results")
    parser.add_argument("--output", type=Path, default=ROOT / "bench/results" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    args = parser.parse_args()
    for key in ("samples", "rounds", "startup_runs", "core_samples", "memory_cycles"):
        if getattr(args, key) < 1:
            parser.error(f"--{key.replace('_', '-')} must be positive")
    if args.warmup < 0:
        parser.error("--warmup must be nonnegative")
    args.output.mkdir(parents=True, exist_ok=True)
    result = {"schema": 1, "metadata": {"utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "system": platform.platform(), "machine": platform.machine(), "neovim": command([args.nvim, "--version"]).splitlines()[0],
        "cpu_count":os.cpu_count(),"load_average_start":os.getloadavg(),
        "harness_sha256":{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'bench').iterdir() if p.suffix in ('.py','.lua')},
        "plugin": revision(ROOT), "luasnip": revision(args.luasnip), "config": revision(args.config_root),
        "arguments": {key: str(value) if isinstance(value, Path) else value for key, value in vars(args).items()},
        "timing": "state_ms: F10 handler to validated state after F12 barrier; ui_ms: PTY write to UI flush socket receipt",
        "limits": ["warm filesystem caches; fresh-process module load is not an OS-cold boot",
                   "UI includes PTY/controller/transport overhead and forced redraw; not physical display latency",
                   "configured track keeps both engines loaded and includes compatibility/decorations differences",
                   "RSS includes Neovim/C allocations; Lua heap is full-GC retained memory",
                   "core match uses pinned LuaSnip internal collection API and excludes UI/context extraction"]},
        "startup": [], "core": [], "input": [], "memory": []}
    target = args.output / "results.json"
    if args.resume:
        previous=json.loads(target.read_text())
        oldargs=previous['metadata']['arguments']
        for key in ('mode','samples','warmup','rounds','startup_runs','core_samples','memory_cycles','seed'):
            if oldargs[key]!=getattr(args,key):parser.error(f"Cannot resume with changed {key}")
        for name in ('input.lua','fixtures.lua','init.lua','configured.lua','rpc.py'):
            if previous['metadata']['harness_sha256'][name]!=result['metadata']['harness_sha256'][name]:
                parser.error(f"Cannot reuse input samples after changing {name}")
        for key in ('plugin','luasnip','config'):
            if previous['metadata'][key].get('head')!=result['metadata'][key].get('head'):
                parser.error(f"Cannot resume with changed {key} revision")
        resumed={'utc':result['metadata']['utc'],'harness_sha256':result['metadata']['harness_sha256']}
        if previous['metadata']['harness_sha256']['isolated.lua']!=result['metadata']['harness_sha256']['isolated.lua']:
            resumed['core_recalibrated']=True
            previous.setdefault('discarded_core',[]).extend(previous['core'])
            previous['core']=[]
        previous['metadata'].setdefault('resumes',[]).append(resumed)
        previous['metadata']['harness_sha256']=result['metadata']['harness_sha256']
        result=previous
    def save():
        aggregate(result)
        target.write_text(json.dumps(result, indent=2, ensure_ascii=False))
    rng = random.Random(args.seed)
    try:
        if args.mode != "configured":
            for i in range(args.startup_runs):
                order = list(ENGINES); rng.shuffle(order)
                for engine in order:
                    if sum(r['engine']==engine for r in result['startup'])<=i:
                        result["startup"].append(core(args, engine, True))
                print(f"startup pair {i + 1}/{args.startup_runs}", flush=True)
            save()
        for round_id in range(args.rounds):
            order = list(ENGINES)
            if round_id % 2: order.reverse()
            for engine in order:
                if args.mode != "configured":
                    print(f"core {engine}, round {round_id + 1}", flush=True)
                    if not any(r['engine']==engine and r.get('round')==round_id for r in result['core']):
                        run=core(args,engine,False);run['round']=round_id;result['core'].append(run)
                    if not any(r['engine']==engine and r['track']=='isolated' and r['round']==round_id for r in result['input']):
                        result["input"].append(input_run(args, engine, "isolated", round_id))
                if args.mode != "isolated":
                    if not any(r['engine']==engine and r['track']=='configured' and r['round']==round_id for r in result['input']):
                        result["input"].append(input_run(args, engine, "configured", round_id))
                save()
        if args.mode != "configured":
            for engine in ENGINES:
                print(f"memory {engine}, {args.memory_cycles} cycles", flush=True)
                if not any(r['engine']==engine for r in result['memory']):
                    result["memory"].append(memory_run(args, engine)); save()
    finally:
        result["metadata"]["load_average_end"]=os.getloadavg()
        save()
    failures = sum(s["failures"] for s in result["summary"])
    print(f"Saved {target}; validation failures={failures}", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
