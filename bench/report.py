#!/usr/bin/env python3
"""Render saved benchmark measurements; never executes or changes the engines."""
import argparse
import json
import statistics
from pathlib import Path

ENGINES=("snippet-tools","luasnip")


def number(value):
    return f"{value:.3f}" if abs(value)<100 else f"{value:.1f}"


def markdown(data):
    index={(row['track'],row['engine'],row['name']):row for row in data['summary']}
    def stat(track,engine,name):
        row=index.get((track,engine,name))
        return row and row['stats']
    output=["# snippet-tools / LuaSnip comparison", "", f"Measured: {data['metadata']['utc']}", "",
            f"Environment: {data['metadata']['neovim']}, {data['metadata']['system']}, {data['metadata']['machine']}", "",
            "Smaller times are better. All figures below come from the adjacent raw results.json.", "",
            "## Scope", "",
            "Fresh module loads use warm OS filesystem caches. Isolated runs load one engine with equivalent definitions; configured runs keep both engines and the existing compatibility layer. UI endpoints include PTY, barrier and explicit redraw overhead; they are not physical display latency.", ""]
    for track,title in [('configured','Actual configuration'),('isolated','Isolated equivalent fixtures')]:
        output += [f"## {title}", "", "Milliseconds from PTY write to the validated UI flush.", "",
          "| Case | New P50 | New P95 | New P99 | LuaSnip P50 | LuaSnip P95 | LuaSnip P99 | New / LS P50 | N per engine | Failures |",
          "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |"]
        names=sorted({r['name'].split('/')[0] for r in data['summary'] if r['track']==track})
        for name in names:
            rows=[index.get((track,e,name+'/ui_ms')) for e in ENGINES]
            stats=[r and r['stats'] for r in rows]
            if not all(stats):
                output.append(f"| {name} | incomplete | | | | | | | | {sum(r['failures'] for r in rows if r)} |")
                continue
            n,ls=stats
            values=[number(s[q]) for s in stats for q in ('median','p95','p99')]
            output.append('| '+name+' | '+' | '.join(values)+f" | {n['median']/ls['median']:.2f}× | {n['n']} / {ls['n']} | {sum(r['failures'] for r in rows)} |")
        if track=='configured':
            output += ["", "The configured checkbox has a documented focus/trailing-whitespace difference. Undo uses a normalized field-edit boundary. See bench/README.md for the exact protocol.", ""]
        else:
            output += [""]
    output += ["## Between-round stability", "", "Range of the four per-round UI medians, in milliseconds. Alternating engine order reduces ordering bias; these ranges help distinguish persistent differences from a single noisy round.", "", "| Track / case | New median range | LuaSnip median range |", "| --- | ---: | ---: |"]
    for track in ('configured','isolated'):
        names=sorted({r['name'] for r in data['summary'] if r['track']==track and r['name'].endswith('/ui_ms')})
        for name in names:
            ranges=[]
            for engine in ENGINES:
                row=index.get((track,engine,name))
                values=[r['summary']['median'] for r in (row or {}).get('rounds',[]) if r['summary']]
                ranges.append(f"{number(min(values))}–{number(max(values))}" if values else 'incomplete')
            output.append(f"| {track}/{name.split('/')[0]} | {' | '.join(ranges)} |")
    output += ["", "## Repeated-table drift", "", "Configured 10×10-table UI medians in the first and last measured 50-sample windows of each round, after warmup. The same buffer is reset between samples; backend bookkeeping and undo history are not purged. This is a repeated editing workload, not fresh-session expansion latency.", "", "| Engine | Round | First window ms | Last window ms | Window N |", "| --- | ---: | ---: | ---: | ---: |"]
    for run in data['input']:
        if run['track']!='configured':continue
        for case in run['cases']:
            if case['name']!='table_10x10' or not case['samples']:continue
            values=[sample['ui_ms'] for sample in case['samples']]
            window=min(50,len(values))
            output.append(f"| {run['engine']} | {run['round']+1} | {number(statistics.median(values[:window]))} | {number(statistics.median(values[-window:]))} | {window} |")
    output += ["", "## Source revisions", "", "| Source | HEAD |", "| --- | --- |"]
    for key in ('plugin','luasnip','config'):
        source=data['metadata'][key]
        output.append(f"| {source['path']} | {source.get('head','unknown')} |")
    output += [""]
    output += ["## Editor-state endpoint", "", "Milliseconds from the in-editor F10 timestamp to validated text/selection, excluding controller/transport time but including sentinel and scheduled-event costs.", "",
               "| Track / case | New P50 | LuaSnip P50 | New P95 | LuaSnip P95 |", "| --- | ---: | ---: | ---: | ---: |"]
    for track in ('configured','isolated'):
        for name in sorted({r['name'] for r in data['summary'] if r['track']==track and r['name'].endswith('state_ms')}):
            a,b=[stat(track,e,name) for e in ENGINES]
            if a and b:output.append(f"| {track}/{name.split('/')[0]} | {number(a['median'])} | {number(b['median'])} | {number(a['p95'])} | {number(b['p95'])} |")
    output += ["", "## Fresh-process module load", "", "| Metric | Unit | New P50 | LuaSnip P50 | N per engine |", "| --- | --- | ---: | ---: | --- |"]
    for name,unit in [('require_ms','ms'),('setup_ms','ms'),('module_heap_kib','KiB')]:
        a,b=[stat('startup',e,name) for e in ENGINES]
        if a and b:output.append(f"| {name} | {unit} | {number(a['median'])} | {number(b['median'])} | {a['n']} / {b['n']} |")
    output += ["", "## Collection scaling", "", "Registration includes equivalent Lua node construction; the lazy first index is timed separately. Warm matching excludes context extraction and UI. Timed matching samples use calibrated batches of 1–10 varying-line calls after 30 warmup calls (about 0.1ms target); values are normalized per call. Batch sizes are recorded in raw JSON.", "",
               "| Metric / collection | Unit | New P50 | LuaSnip P50 | New P95 | LuaSnip P95 |", "| --- | --- | ---: | ---: | ---: | ---: |"]
    for name in sorted({r['name'] for r in data['summary'] if r['track']=='core'}):
        a,b=[stat('core',e,name) for e in ENGINES]
        if a and b:output.append(f"| {name} | {index[('core',ENGINES[0],name)]['unit']} | {number(a['median'])} | {number(b['median'])} | {number(a['p95'])} | {number(b['p95'])} |")
    output += ["", "## Lifecycle memory", "", "After warmup, full-GC retained Lua heap and current-buffer extmarks. RSS is the editor process, including C/allocator state. Neither undo history nor backend bookkeeping is purged between cycles.", "",
               "| Engine | Cycles | Lua heap KiB | RSS KiB | Extmarks | Autocommands | Buffers |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for run in data['memory']:
        for phase in run['phases']:
            output.append(f"| {run['engine']} | {phase['cycles']} | {number(phase['lua_heap_kib'])} | {phase['rss_kib']} | {phase['extmarks']} | {phase['autocmds']} | {phase['buffers']} |")
    output += ["", "A retained-count trend under this workload needs attribution before calling it a general leak. Per-round samples and host load are in results.json.", "", "## Reproduction", "", "```sh",
               "PYTHONDONTWRITEBYTECODE=1 python3 bench/compare.py --output bench/results/reproduction",
               "python3 bench/report.py bench/results/reproduction/results.json", "```", "", "## Limits", ""]
    output += ['- '+line for line in data['metadata']['limits']]
    output += ["- Definition sets are preloaded for the configured route, so lazy source availability is not mistaken for speed.",
               "- Normalized-history isolated memory results do not predict the real configuration's history retention.",
               "- A large relative ratio on a sub-millisecond operation can still be a small absolute difference.",
               "- The machine remains a shared interactive environment; tails and small differences can vary between runs.", ""]
    if data['metadata'].get('resumes'):
        output += ["## Run provenance", "", "This run was resumed with unchanged input-protocol hashes and source revisions. Completed input samples were retained.", ""]
        if any(r.get('core_recalibrated') for r in data['metadata']['resumes']):
            output += ["The core harness changed on resume, so both engines' core samples were rerun. Previous completed core samples remain under discarded_core and are excluded from summaries.", ""]
    for note in data['metadata'].get('measurement_notes',[]):
        if note.get('kind')=='core_process_timeout':
            output += [f"The initial fixed-{note['fixed_batch_size']}-call core process exceeded its {note['limit_seconds']}-second whole-process limit on {note['engine']}. It was replaced by calibrated 1–10-call batches. This is a batch-runtime timeout, not a single-operation latency or input correctness failure.", ""]
    return '\n'.join(output)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('results',type=Path);args=p.parse_args()
    data=json.loads(args.results.read_text())
    target=args.results.with_name('report.md');target.write_text(markdown(data))
    rows=[row for row in data['summary'] if (row['track'] in ('configured','isolated') and row['name'].endswith('/ui_ms')) or (row['track']=='startup' and row['name'] in ('require_ms','setup_ms'))]
    template=Path(__file__).with_name('chart.html').read_text()
    args.results.with_name('comparison.html').write_text(template.replace('__BENCH_DATA__',json.dumps(rows,ensure_ascii=False).replace('</','<\\/')))
    print(target)


if __name__=='__main__':main()
