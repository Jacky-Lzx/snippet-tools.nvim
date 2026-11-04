#!/usr/bin/env python3
"""Instrument range queries separately from formal uninstrumented PTY timings."""
import argparse
import json
from pathlib import Path
import shutil
from compare import InputProcess
from editing import metadata


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--nvim',default=shutil.which('nvim'))
    p.add_argument('--luasnip',type=Path,default=Path.home()/'.local/share/nvim/lazy/LuaSnip')
    p.add_argument('--config-root',type=Path,default=Path.home()/'.config/nvim')
    args=p.parse_args();args.core_samples=1
    proc=InputProcess(args,'snippet-tools','isolated')
    data={'metadata':metadata(args),'instrumented':True,'cases':[]}
    try:
        proc.client.lua('''
          RangeProfile={active=false,counts={},ns={}}
          for _,name in ipairs({'nvim_buf_get_extmark_by_id','nvim_buf_get_extmarks',
              'nvim_buf_set_extmark','nvim_buf_get_lines','nvim_buf_get_text',
              'nvim_buf_line_count','nvim_buf_is_valid','nvim_buf_set_text'})do
            local original=vim.api[name]
            vim.api[name]=function(...)
              if not RangeProfile.active then return original(...) end
              RangeProfile.counts[name]=(RangeProfile.counts[name] or 0)+1
              local started=vim.uv.hrtime();local value=original(...)
              RangeProfile.ns[name]=(RangeProfile.ns[name] or 0)+vim.uv.hrtime()-started
              return value
            end
          end
        ''')
        for name in ('table_10x10','mirrors_100','choice_toggle','jump_final'):
            case=next(c for c in proc.cases if c['name']==name)
            for _ in range(20):assert proc.sample(case)['valid']
            samples=[]
            for _ in range(10):
                proc.prepare(case)
                proc.client.lua('RangeProfile.counts={};RangeProfile.ns={};RangeProfile.active=true')
                proc.serial+=1;sample=proc.client.sample(proc.serial,case['action'])
                assert sample['valid'],sample
                counters=proc.client.lua('RangeProfile.active=false;return {counts=RangeProfile.counts,ns=RangeProfile.ns}')
                samples.append({'counters':counters,'state_ms':sample['state_ms'],'ui_ms':sample['ui_ms']})
            data['cases'].append({'name':name,'samples':samples})
            print(name,samples[0]['counters']['counts'],flush=True)
    finally:proc.close()
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'profile.json').write_text(json.dumps(data,indent=2))


if __name__=='__main__':main()
