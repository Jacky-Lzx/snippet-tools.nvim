#!/usr/bin/env python3
"""Compare editing latency without repeating unrelated collection-scaling tests."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import shutil

from compare import ROOT, ENGINES, InputProcess, aggregate, command, core, input_run, memory_run, revision


def metadata(args):
    runtime = {}
    for directory in ("lua", "plugin", "after"):
        for path in (ROOT / directory).rglob("*.lua"):
            runtime[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return {
        "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "system": platform.platform(), "machine": platform.machine(),
        "neovim": command([args.nvim, "--version"]).splitlines()[0],
        "plugin": revision(ROOT), "luasnip": revision(args.luasnip), "config": revision(args.config_root),
        "runtime_sha256": runtime,
        "harness_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in (ROOT / 'bench').iterdir() if p.suffix in ('.py', '.lua')},
        "arguments": {k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()},
        "load_average_start": os.getloadavg(),
        "limits": ["warm OS caches; fresh Lua modules are not OS-cold application startup",
                   "UI endpoint includes real PTY, validation barrier and forced redraw, not physical display painting",
                   "configured Markdown uses current dual-engine integration and same-buffer repeated editing",
                   "different sample counts by track; P99 with 200 samples is descriptive only",
                   "collection scaling omitted: this experiment optimizes editing, not trigger lookup"],
    }


def profile(args):
    proc = InputProcess(args, 'snippet-tools', 'isolated')
    output = {'metadata': metadata(args), 'instrumented': True, 'cases': []}
    try:
        for name in ('table_10x10', 'mirrors_100'):
            case = next(c for c in proc.cases if c['name'] == name)
            for _ in range(20):
                assert proc.sample(case)['valid']
            proc.client.lua('''
              Profile={active=false,counts={},ns={}}
              if not ProfileOriginal then
                ProfileOriginal={}
                for _,name in ipairs({'nvim_buf_get_extmark_by_id','nvim_buf_set_extmark',
                    'nvim_buf_get_lines','nvim_buf_get_text','nvim_buf_line_count','nvim_buf_is_valid',
                    'nvim_buf_set_text'})do
                  local original=vim.api[name];ProfileOriginal[name]=original
                  vim.api[name]=function(...)
                    if not Profile.active then return original(...) end
                    Profile.counts[name]=(Profile.counts[name] or 0)+1
                    local started=vim.uv.hrtime();local value=original(...)
                    Profile.ns[name]=(Profile.ns[name] or 0)+vim.uv.hrtime()-started
                    return value
                  end
                end
              end
            ''')
            samples = []
            for _ in range(10):
                proc.prepare(case)
                proc.client.lua('Profile.counts={};Profile.ns={};Profile.active=true')
                proc.serial += 1
                sample = proc.client.sample(proc.serial, case['action'])
                assert sample['valid'], sample
                counters = proc.client.lua('Profile.active=false;return {counts=Profile.counts,ns=Profile.ns}')
                samples.append({'counters': counters, 'state_ms': sample['state_ms'], 'ui_ms': sample['ui_ms']})
            output['cases'].append({'name': name, 'samples': samples})
    finally:
        proc.close()
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'profile.json').write_text(json.dumps(output, indent=2))
    for row in output['cases']:
        print(row['name'], row['samples'][0]['counters']['counts'], flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--nvim', default=shutil.which('nvim'))
    p.add_argument('--luasnip', type=Path, default=Path.home()/'.local/share/nvim/lazy/LuaSnip')
    p.add_argument('--config-root', type=Path, default=Path.home()/'.config/nvim')
    p.add_argument('--engines', nargs='+', choices=ENGINES, default=list(ENGINES))
    p.add_argument('--isolated-samples', type=int, default=100)
    p.add_argument('--configured-samples', type=int, default=50)
    p.add_argument('--warmup', type=int, default=20)
    p.add_argument('--rounds', type=int, default=4)
    p.add_argument('--startup-runs', type=int, default=20)
    p.add_argument('--memory-cycles', type=int, default=1000)
    p.add_argument('--seed', type=int, default=20261105)
    p.add_argument('--profile', action='store_true')
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    for key in ('isolated_samples','configured_samples','warmup','rounds','startup_runs','memory_cycles'):
        if getattr(args,key)<1: p.error(key+' must be positive')
    args.core_samples = 1  # Required by the shared environment; core is load-only here.
    if args.profile:
        profile(args)
        return 0
    args.output.mkdir(parents=True, exist_ok=True)
    result = {'schema': 1, 'metadata': metadata(args), 'startup': [], 'core': [], 'input': [], 'memory': []}
    def save():
        aggregate(result)
        (args.output/'results.json').write_text(json.dumps(result, indent=2, ensure_ascii=False))
    try:
        rng = random.Random(args.seed)
        for _ in range(args.startup_runs):
            order = list(args.engines); rng.shuffle(order)
            for engine in order: result['startup'].append(core(args,engine,True))
        save()
        for round_id in range(args.rounds):
            order = list(args.engines)
            if round_id%2: order.reverse()
            for engine in order:
                for track in ('isolated','configured'):
                    args.samples = args.isolated_samples if track=='isolated' else args.configured_samples
                    print(f'round {round_id+1}/{args.rounds}: {engine}/{track}', flush=True)
                    result['input'].append(input_run(args,engine,track,round_id)); save()
        for engine in args.engines:
            result['memory'].append(memory_run(args,engine)); save()
    finally:
        result['metadata']['load_average_end']=os.getloadavg()
        save()
    failures=sum(row['failures'] for row in result['summary'])
    print('Saved', args.output, 'failures=', failures, flush=True)
    return int(failures>0)


if __name__=='__main__': raise SystemExit(main())
