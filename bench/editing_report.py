#!/usr/bin/env python3
"""Render an editing optimization comparison from saved, validated raw runs."""
import argparse
import hashlib
import json
from pathlib import Path

SERIES = (('before','snippet-tools'),('after','snippet-tools'),('after','luasnip'))


def validate(before, after):
    for key in ('seed','rounds','isolated_samples','configured_samples','warmup','startup_runs','memory_cycles'):
        assert before['metadata']['arguments'][key]==after['metadata']['arguments'][key], key
    for key in ('neovim','system','machine'):
        assert before['metadata'][key]==after['metadata'][key], key
    for key in ('config','luasnip'):
        assert before['metadata'][key]['head']==after['metadata'][key]['head'], key+' revision'
        assert before['metadata'][key]['status']==after['metadata'][key]['status'], key+' working tree'
    for name in ('editing.py','input.lua','fixtures.lua','init.lua','configured.lua','rpc.py'):
        assert before['metadata']['harness_sha256'][name]==after['metadata']['harness_sha256'][name], name
    for data in (before,after):
        for run in data['input']:
            expected=data['metadata']['arguments'][run['track']+'_samples']
            for case in run['cases']:
                assert len(case['samples'])==expected and not case['failures'], (run['engine'],case['name'])
        for row in data['summary']:
            assert row['failures']==0
    rounds=before['metadata']['arguments']['rounds']
    assert len(before['input'])==rounds*2 and len(after['input'])==rounds*4, 'Incomplete input data'
    assert len(before['memory'])==1 and len(after['memory'])==2, 'Incomplete lifecycle data'


def rows_for(before,after):
    index={phase:{(r['track'],r['engine'],r['name']):r for r in data['summary']}
           for phase,data in (('before',before),('after',after))}
    rows=[]
    for track in ('isolated','configured','startup'):
        names=sorted({key[2] for key in index['after'] if key[0]==track
                      and (key[2].endswith('/ui_ms') or key[2] in ('require_ms','setup_ms'))})
        for name in names:
            rows.append({'track':track,'name':name,'series':[
                index[phase][track,engine,name] for phase,engine in SERIES]})
    return rows


def markdown(before,after,rows,before_path,after_path):
    args=after['metadata']['arguments']; rounds=args['rounds']
    total=sum(len(c['samples']) for data in (before,after) for run in data['input'] for c in run['cases'])
    lines=['# Editing optimization comparison','','Same current configuration and PTY protocol before/after optimization. No engine settings, fixtures, decorations or update events were relaxed to improve timings.','',
           f"{rounds} alternating optimized-engine/LuaSnip rounds; {rounds*args['isolated_samples']} isolated and {rounds*args['configured_samples']} configured samples per case/engine, {args['warmup']} warmup samples each round, {args['startup_runs']} fresh module loads and {args['memory_cycles']} lifecycle cycles. Before-only measurements precede optimization and cannot eliminate time-of-day effects. P95 is the primary tail statistic; P99 is descriptive, especially for the smaller configured sample set.",'',
           f'The comparison contains {total:,} successful measured input operations across three series, with zero validation failures. Exact text, selection, mode and the delivered UI frame are checked. These are PTY-to-validated-flush endpoints, not physical display latency.','',
           f"Measurements (UTC): before {before['metadata']['utc']}; after {after['metadata']['utc']}.",'', '## Changes','','- Index line starts once per rendered model instead of rescanning prefixes for every node coordinate.',
           '- Copy numeric navigation paths directly instead of using general recursive table copies.',
           '- Track editable/computed records; literal text uses its enclosing field/root instead of its own extmark.',
           '- Reuse synchronous-pass buffer bounds/line reads and avoid rewriting unchanged extmark gravity/highlights.',
           '- Read initial field values from the just-inserted model instead of querying them back through the buffer.','']
    for track,title in (('isolated','Equivalent isolated definitions'),('configured','Current Markdown configuration'),('startup','Fresh module loading')):
        lines += ['## '+title,'','Milliseconds; smaller is better.','',
                  '| Operation | Before P50 | Optimized P50 | LuaSnip P50 | Before P95 | Optimized P95 | LuaSnip P95 | Before / optimized | N per series |',
                  '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
        for row in rows:
            if row['track']!=track:continue
            a,b,c=[r['stats'] for r in row['series']]
            vals=[s['median'] for s in (a,b,c)]+[s['p95'] for s in (a,b,c)]
            lines.append('| '+row['name'].removesuffix('/ui_ms')+' | '+' | '.join(f'{v:.3f}' for v in vals)+f" | {a['median']/b['median']:.2f}× | {a['n']} / {b['n']} / {c['n']} |")
        lines += ['']
    lines += ['## Between-round variability','','Ranges of the four per-round UI medians in milliseconds.','',
              '| Track / operation | Before | Optimized | LuaSnip |','| --- | ---: | ---: | ---: |']
    for row in rows:
        if row['track']=='startup':continue
        ranges=[]
        for series in row['series']:
            vals=[r['summary']['median'] for r in series['rounds']]
            ranges.append(f'{min(vals):.3f}–{max(vals):.3f}')
        lines.append('| '+row['track']+'/'+row['name'].split('/')[0]+' | '+' | '.join(ranges)+' |')
    lines += ['', '## Configured-workload scope','','This focused experiment uses a shorter repeated editing sequence than the earlier 250-sample/round report. Table numbers include warmup and preceding-case state, and should not be equated with a fresh-session first expansion or directly compared to the older longer-sequence medians.','',
              'Configured checkbox focus differs by route; undo measures a normalized field-edit boundary. Both engines remain loaded in the configured track. Plain input is a control, not a value to subtract from other medians.','',
              '## Lifecycle memory','','Full-GC Lua heap; RSS includes editor/C/allocator state. The same buffer is reused, with undo/backend bookkeeping retained. Growth alone is not a general leak diagnosis.','',
              '| Series | Cycles | Lua KiB | RSS KiB | Extmarks | Buffers |','| --- | ---: | ---: | ---: | ---: | ---: |']
    for phase,data in (('before',before),('after',after)):
        for run in data['memory']:
            for item in run['phases']:
                lines.append(f"| {phase}/{run['engine']} | {item['cycles']} | {item['lua_heap_kib']:.1f} | {item['rss_kib']} | {item['extmarks']} | {item['buffers']} |")
    lines += ['', '## Revisions and raw evidence','','| Source | Before | After |','| --- | --- | --- |']
    for key in ('plugin','config','luasnip'):
        lines.append(f"| {key} | {before['metadata'][key]['head']} | {after['metadata'][key]['head']} |")
    for label,path in (('before',before_path),('after',after_path)):
        lines += ['',f'Local raw {label}: `{path}`',f'SHA-256: `{hashlib.sha256(path.read_bytes()).hexdigest()}`']
    lines += ['', 'Runtime/harness hashes, startup samples, every input sample and round summaries are in those ignored local files. The interactive comparison is generated alongside this report.','',
              '## Limits','','- The Markdown configuration has changed since the first comparison: TeX snippets have migrated. This run collects a fresh pre-optimization baseline under that same new configuration.',
              '- LuaSnip and optimized-engine rounds alternate, but the baseline-only phase ran earlier; sub-millisecond changes and host-load differences deserve caution.',
              '- This run targets editing. Trigger lookup/collection scaling was not changed or remeasured.',
              '- Mirror edits still perform one buffer replacement per replica and scan geometry across records. Extmark writes are reduced, but extremely large mirror sets can still expose quadratic geometry work.',
              '- Profile call counts are instrumented diagnostics, separate from uninstrumented formal timings.','']
    return '\n'.join(lines)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--profile-before',type=Path);p.add_argument('--profile-after',type=Path)
    p.add_argument('before',type=Path);p.add_argument('after',type=Path);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();before=json.loads(args.before.read_text());after=json.loads(args.after.read_text())
    validate(before,after);rows=rows_for(before,after);args.output.mkdir(parents=True,exist_ok=True)
    report=markdown(before,after,rows,args.before,args.after)
    report += "\n## Protocol provenance\n\nThe six input/fixture/harness hashes checked by this report match across before/after.\n"
    for note in after['metadata'].get('measurement_notes',[]):
        if note.get('kind')=='cleanup_interruption':
            report += f"\nA prior final-attempt run stopped after an ENOTEMPTY bytecode-cache cleanup race outside timed operations. It is retained under `{note['path']}`. Commit `{note['fix_commit']}` makes the editor quit before cache cleanup, with a bounded cleanup retry. The final comparison was restarted; none of that interrupted attempt's samples are pooled.\n"
    if args.profile_before or args.profile_after:
        assert args.profile_before and args.profile_after, 'Supply both profile files'
        profiles=[json.loads(path.read_text()) for path in (args.profile_before,args.profile_after)]
        report += "\n## Instrumented API diagnostics\n\nMedian call counts over ten isolated operations after warmup. Diagnostic latency is excluded from the formal comparison.\n\n| Operation / API | Before calls | Optimized calls |\n| --- | ---: | ---: |\n"
        for name in ('table_10x10','mirrors_100'):
            cases=[next(c for c in data['cases'] if c['name']==name) for data in profiles]
            for api in ('nvim_buf_set_extmark','nvim_buf_get_extmark_by_id','nvim_buf_get_lines','nvim_buf_get_text','nvim_buf_set_text'):
                counts=[sorted(s['counters']['counts'].get(api,0) for s in c['samples']) for c in cases]
                medians=[(v[(len(v)-1)//2]+v[len(v)//2])/2 for v in counts]
                report += f"| {name}/{api} | {medians[0]:.0f} | {medians[1]:.0f} |\n"
        for label,path in (('before',args.profile_before),('optimized',args.profile_after)):
            report += f"\nInstrumented {label}: `{path}`; SHA-256 `{hashlib.sha256(path.read_bytes()).hexdigest()}`.\n"
    (args.output/'report.md').write_text(report)
    template=Path(__file__).with_name('editing_chart.html').read_text()
    (args.output/'comparison.html').write_text(template.replace('__BENCH_DATA__',json.dumps(rows,ensure_ascii=False).replace('</','<\\/')))
    print(args.output/'report.md')


if __name__=='__main__':main()
