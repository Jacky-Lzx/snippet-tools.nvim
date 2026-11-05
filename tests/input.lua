-- A separate Neovim with an attached UI runs the real input/event loop.
local child = vim.fn.jobstart(
  { vim.v.progpath, "--embed", "-u", "tests/minimal_init.lua", "-i", "NONE", "-n" },
  { rpc = true }
)
assert(child > 0)
local function rpc(method, ...)
  return vim.rpcrequest(child, method, ...)
end
local function lua(code, ...)
  return rpc("nvim_exec_lua", code, { ... })
end
local function input(keys)
  vim.rpcnotify(child, "nvim_input", keys)
end
local function wait(code, label)
  assert(
    vim.wait(2000, function()
      return lua(code) == true
    end, 5),
    (label or code)
      .. "\n"
      .. vim.inspect(
        lua(
          [[return {lines=vim.api.nvim_buf_get_lines(0,0,-1,false),mode=vim.api.nvim_get_mode().mode,
      cursor=vim.api.nvim_win_get_cursor(0),state=require('snippet_tools').inspect(),err=vim.v.errmsg,notifications=notifications}]]
        )
      )
  )
end
local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
end
local count = 0
local function test(name, run)
  input("<Esc><Esc>")
  wait("return vim.api.nvim_get_mode().mode=='n'")
  lua([[
    if package.loaded.completion_tools then require('completion_tools').dispose() end
    local s=require('snippet_tools')
    s.dispose(); require('snippet_tools.registry').clear()
    vim.cmd('enew!'); vim.bo.filetype='lua'; vim.bo.expandtab=true; vim.bo.shiftwidth=2
    vim.o.selection='inclusive'; notifications={}; vim.v.errmsg=''
    vim.notify=function(msg,level) notifications[#notifications+1]={msg=msg,level=level} end
    s.setup({keymap={['<Tab>']='expand_or_jump',['<S-Tab>']='jump_backward',['<F6>']='choice_next',['<F7>']='choice_prev'}})
    vim.keymap.set({'i','s'},'<F5>',function() s.expand(fixture) end)
  ]])
  local ok, err = xpcall(run, debug.traceback)
  assert(ok, name .. ": " .. tostring(err))
  eq({}, lua("return notifications"))
  count = count + 1
  print("input: " .. name)
end
local ok, err = xpcall(function()
  rpc("nvim_ui_attach", 100, 30, { rgb = true })
  test("placeholder replacement, live mirror, final stop and burst input", function()
    lua([[fixture='hello ${1:world} / $1!$0']])
    input("i<F5>name<Tab>!")
    wait(
      "return vim.api.nvim_get_current_line()=='hello name / name!!' and vim.api.nvim_get_mode().mode=='i'"
    )
    eq(false, lua("return require('snippet_tools').active()"))
  end)
  test("empty adjacent placeholders keep independent boundaries", function()
    lua([[fixture='$1$2$0']])
    input("i<F5>A<Tab>B<Tab>C")
    wait("return vim.api.nvim_get_current_line()=='ABC'")
  end)
  test("jump backwards reselects the original field", function()
    lua([[fixture='${1:one}-${2:two}$0']])
    input("i<F5>A<Tab>B<S-Tab>C<Tab><Tab>!")
    wait("return vim.api.nvim_get_current_line()=='C-B!'")
  end)
  test("multiline UTF-8 placeholders and mirrors", function()
    lua([[fixture='${1:你好\n世界} / $1$0']])
    input("i<F5>中文<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='中文 / 中文!'")
  end)
  test("selection=exclusive replaces exactly the placeholder", function()
    lua([[vim.o.selection='exclusive'; fixture='[${1:abc}]$0']])
    input("i<F5>X<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='[X]!'")
  end)
  test("manual trigger replacement respects word boundaries and suffix", function()
    lua([[require('snippet_tools').add('lua',{{trigger='fn',body='function ${1:name}()$0'}});
      vim.api.nvim_buf_set_lines(0,0,-1,false,{'fnTAIL'}); vim.api.nvim_win_set_cursor(0,{1,2})]])
    input("i<Tab>run<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='function run()!TAIL'")
  end)
  test("Lua function nodes update only when dependencies change", function()
    lua([[
      local s=require('snippet_tools'); calls=0
      fixture={s.i(1,'49'),s.t('/'),s.f(function(a) calls=calls+1;return tostring(98-tonumber(a[1])) end,{1}),s.t(':'),s.i(2,'body'),s.i(0)}
    ]])
    input("i<F5>60<Tab>")
    wait("return vim.api.nvim_get_current_line()=='60/38:body' and vim.api.nvim_get_mode().mode=='s'")
    local calls = lua("return calls")
    input("text")
    wait("return vim.api.nvim_get_current_line()=='60/38:text'")
    eq(calls, lua("return calls"))
  end)
  test("plain choice alternatives preserve edited text", function()
    lua([[fixture='${1|red,blue|}-$1$0']])
    input("i<F5>green<F6>")
    wait("return vim.api.nvim_get_current_line()=='blue-blue'")
    input("<F7>")
    wait("return vim.api.nvim_get_current_line()=='green-green'")
    input("<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='green-green!'")
  end)
  test("nested choice branches restore their editable fields", function()
    lua([[
      local s=require('snippet_tools')
      fixture={s.c(1,{{s.t('['),s.i(1,'first'),s.t(']')},{s.t('{'),s.i(1,'second'),s.t('}')}}),s.i(0)}
    ]])
    input("i<F5><Tab>edited<S-Tab><F6>")
    wait("return vim.api.nvim_get_current_line()=='{second}'")
    input("<Tab>other<S-Tab><F7>")
    wait("return vim.api.nvim_get_current_line()=='[edited]'")
    input("<Tab>again<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='[again]!'")
  end)
  test("choice changes propagate to computed nodes and preserve dynamic edits", function()
    lua([[
      local s=require('snippet_tools')
      fixture={s.c(1,{'a','b'}),s.t('/'),s.f(function(a)return a[1]:upper()end,{1}),s.t('/'),
        s.d(2,function(a)
          local body={s.i(1,'body')};if a[1]=='a' then body[#body+1]=s.t(':label') end
          return body
        end,{1}),s.i(0)}
    ]])
    input("i<F5><Tab>edited<S-Tab><F6>")
    wait("return vim.api.nvim_get_current_line()=='b/B/edited'")
    input("<F7>")
    wait("return vim.api.nvim_get_current_line()=='a/A/edited:label'")
  end)
  test("dynamic regeneration propagates through computed dependencies", function()
    lua([[
      local s=require('snippet_tools')
      fixture={s.i(1,'one'),s.t(':'),s.d(2,function(a)return s.t(a[1]..'!')end,{1}),
        s.t(':'),s.f(function(a)return a[1]..'?'end,{2}),s.i(0)}
    ]])
    input("i<F5>two<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='two:two!:two!?!'")
  end)
  test("localized mirror writes preserve adjacent empty fields and Unicode", function()
    lua(
      [[local s=require('snippet_tools');fixture={s.rep(1),s.t('|'),s.i(1,'old'),s.rep(1),s.i(2),s.t('|'),s.rep(1),s.i(0)}]]
    )
    input("i<F5>中文<Tab>Q<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='中文|中文中文Q|中文!'")
  end)
  test("coincident empty mirrors expand again without swallowing siblings", function()
    lua([[fixture='${1:old}$1$1${2:tail}$1$0']])
    input("i<F5>x<BS>")
    wait("return vim.api.nvim_get_current_line()=='tail' and vim.api.nvim_get_mode().mode=='i'")
    input("<Tab>Q<S-Tab>X<Tab><Tab>!")
    wait("return vim.api.nvim_get_current_line()=='XXXQX!'")
  end)
  test("localized writes preserve nested multiline parent mirrors", function()
    lua([[fixture='[${1:outer}]/$1/${2:tail}$0']])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    lua([[fixture='{${1:中\n文}}$0']])
    input("<F5>短<CR>行<Tab><Tab>end<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='行}/end!'")
    eq({ "[{短", "行}]/{短", "行}/end!" }, lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)"))
  end)
  test("identical text choices invalidate cached field order", function()
    lua(
      [[local s=require('snippet_tools');fixture={s.c(1,{{s.i(1,'A'),s.i(2,'B')},{s.i(1,'AB')}}),s.i(2,'tail'),s.i(0)}]]
    )
    input("i<F5><F6><Tab>X<Tab>Y<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='XY!'")
  end)
  test("API source edits invalidate sync snapshots before navigation", function()
    lua([[fixture='${1:a}/$1/${2:tail}$0']])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    lua([[vim.api.nvim_buf_set_text(0,0,0,0,1,{'api'});require('snippet_tools').update()]])
    wait("return vim.api.nvim_get_current_line()=='api/api/tail'")
    input("<Tab>Z<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='api/api/Z!'")
  end)
  test("external linked edits preserve mirror ranges before snippet sync", function()
    lua([[fixture='\\begin{${1:old}}\n  $0\n\\end{$1}']])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    lua([[
      -- A linked-editing client can replace both names before the scheduled sync.
      local previous = 'old'
      for _, name in ipairs({'table', 'table*', 'tabular', '环境', 'table'}) do
        vim.api.nvim_buf_set_text(0,0,7,0,7+#previous,{name})
        vim.api.nvim_buf_set_text(0,2,5,2,5+#previous,{name})
        require('snippet_tools').update()
        assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0,0,-1,false), {
          '\\begin{'..name..'}', '  ', '\\end{'..name..'}',
        }))
        previous = name
      end
    ]])
    eq({ "\\begin{table}", "  ", "\\end{table}" }, lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)"))
    input("<Esc>gg0f{lct}figure<Tab>body")
    wait("return vim.api.nvim_get_current_line()=='  body'")
    eq(
      { "\\begin{figure}", "  body", "\\end{figure}" },
      lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)")
    )
  end)
  test("external linked insertion fills an empty mirror exactly once", function()
    lua([[fixture='\\begin{$1}\n  $0\n\\end{$1}']])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='i'")
    lua([[
      vim.api.nvim_buf_set_text(0,0,7,0,7,{'table'})
      vim.api.nvim_buf_set_text(0,2,5,2,5,{'table'})
      require('snippet_tools').update()
    ]])
    eq({ "\\begin{table}", "  ", "\\end{table}" }, lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)"))
    input("<Tab>body")
    wait("return vim.api.nvim_get_current_line()=='  body' and not require('snippet_tools').active()")
  end)
  test("external replacements also preserve mirrors preceding their source", function()
    lua([[fixture='$1 / ${1:old}:$0']])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    lua([[
      vim.api.nvim_buf_set_text(0,0,6,0,9,{'table'})
      vim.api.nvim_buf_set_text(0,0,0,0,3,{'table'})
      require('snippet_tools').update()
    ]])
    eq("table / table:", lua("return vim.api.nvim_get_current_line()"))
    input("<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='table / table:!'")
  end)
  test("unchanged-text sync still rejects removed root marks", function()
    lua([[fixture='[${1:a}]$0']])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    lua(
      [[local s=require('snippet_tools');s.update();vim.api.nvim_buf_clear_namespace(0,vim.api.nvim_get_namespaces()['snippet-tools'],0,-1);s.update();assert(not s.active())]]
    )
  end)
  test("large literal layouts keep every field independently editable", function()
    lua([[
      local s=require('snippet_tools');fixture={}
      for i=1,100 do
        fixture[#fixture+1]=s.t('[');fixture[#fixture+1]=s.i(i,'old');fixture[#fixture+1]=s.t(']')
      end
      fixture[#fixture+1]=s.i(0)
    ]])
    local keys, expected = { "i<F5>" }, {}
    for i = 1, 100 do
      keys[#keys + 1] = i .. "<Tab>"
      expected[#expected + 1] = "[" .. i .. "]"
    end
    keys[#keys + 1] = "!"
    input(table.concat(keys))
    wait("return vim.api.nvim_get_current_line()==" .. vim.inspect(table.concat(expected) .. "!"))
  end)
  test("indexed multiline positions preserve UTF-8 fields and indentation", function()
    lua([[
      local s=require('snippet_tools');fixture={s.t('中文\n')}
      for i=1,30 do
        fixture[#fixture+1]=s.t('[');fixture[#fixture+1]=s.i(i,'旧');fixture[#fixture+1]=s.t(']\n')
      end
      fixture[#fixture+1]=s.i(0)
      vim.api.nvim_buf_set_lines(0,0,-1,false,{'  '})
    ]])
    local keys, expected = { "A<F5>" }, { "  中文" }
    for i = 1, 30 do
      keys[#keys + 1] = i .. "<Tab>"
      expected[#expected + 1] = "  [" .. i .. "]"
    end
    keys[#keys + 1] = "!"
    expected[#expected + 1] = "  !"
    input(table.concat(keys))
    wait("return vim.api.nvim_get_current_line()=='  !'")
    eq(expected, lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)"))
  end)
  test("dynamic nodes generate editable local placeholders", function()
    lua([[
      local s=require('snippet_tools')
      fixture={s.i(1,'2'),s.t(':'),s.d(2,function(a)
        local result={}; for j=1,math.min(5,tonumber(a[1]) or 0) do
          result[#result+1]=s.i(j,'cell'); result[#result+1]=s.t('|')
        end; return result
      end,{1}),s.i(0)}
    ]])
    input("i<F5>3<Tab>A<Tab>B<Tab>C<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='3:A|B|C|!'")
  end)
  test("nested expansion updates outer mirrors and resumes outer navigation", function()
    lua([[fixture='[${1:outer}]=$1:${2:next}$0']])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    lua([[fixture='(${1:inner})$0']])
    input("<F5>X<Tab>")
    wait("return vim.api.nvim_get_current_line()=='[(X)]=(X):next'")
    input("<Tab>Y<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='[(X)]=(X):Y!'")
  end)
  test("automatic expansion sees each character in a single input burst", function()
    lua([[require('snippet_tools').add('lua',{{trigger='mk',body='[$1]$0',auto=true}})]])
    input("imkX<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='[X]!'")
  end)
  test("pattern autosnippets expose captures to dynamic nodes", function()
    lua([[
      local s=require('snippet_tools'); s.add('lua',{{trigger='table(%d+) ',pattern=true,auto=true,
        body={s.d(1,function(_,ctx) return s.t(string.rep('|',tonumber(ctx.match.captures[1]))) end),s.i(0)}}})
    ]])
    input("itable3 X")
    wait("return vim.api.nvim_get_current_line()=='|||X'")
  end)
  test("a single undo restores an automatic expansion trigger", function()
    lua([[require('snippet_tools').add('lua',{{trigger='mk',body='[$1]$0',auto=true}})]])
    input("imk")
    wait("return vim.api.nvim_get_current_line()=='[]'")
    input("<Esc>u")
    wait("return vim.api.nvim_get_current_line()=='mk'")
    eq(false, lua("return require('snippet_tools').active()"))
    input("<C-r>")
    wait("return vim.api.nvim_get_current_line()=='[]'")
  end)
  test("manual expansion is one undo operation", function()
    lua([[require('snippet_tools').add('lua',{{trigger='fn',body='[${1:name}]-$1$0'}})]])
    input("ifn<Tab>")
    wait("return vim.api.nvim_get_mode().mode=='s' and vim.api.nvim_get_current_line()=='[name]-name'")
    input("<Esc>u")
    wait("return vim.api.nvim_get_current_line()=='fn'")
    eq(false, lua("return require('snippet_tools').active()"))
  end)
  test("indentation and tabs follow buffer settings", function()
    lua([[fixture='function ${1:name}()\n\t$0\nend';vim.api.nvim_buf_set_lines(0,0,-1,false,{'    '})]])
    input("A<F5>run<Tab>body")
    wait("return vim.api.nvim_get_current_line()=='      body'")
    eq(
      { "    function run()", "      body", "    end" },
      lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)")
    )
  end)
  test("leaving the region cancels the session", function()
    lua([[fixture='${1:field}$0';vim.api.nvim_buf_set_lines(0,0,-1,false,{'','outside'})]])
    input("i<F5><Esc>j")
    wait("return vim.api.nvim_win_get_cursor(0)[1]==2 and not require('snippet_tools').active()")
  end)
  test("buffer changes dispose the old session", function()
    lua([[fixture='${1:field}$0']])
    input("i<F5><Esc>")
    wait("return vim.api.nvim_get_mode().mode=='n'")
    lua([[vim.cmd('enew!')]])
    eq(false, lua("return require('snippet_tools').active()"))
  end)
  test("replacing an enclosing placeholder discards its old nested fields", function()
    lua([[fixture='${1:outer ${2:inner}}-${3:next}$0']])
    input("i<F5>X<Tab>Y<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='X-Y!'")
  end)
  test("unknown variables become editable placeholders", function()
    lua([[fixture='$UNKNOWN-$0']])
    input("i<F5>value<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='value-!'")
  end)
  test("mirrors follow edits before the source field", function()
    lua([[fixture='$1=${1:name}:$0']])
    input("i<F5>longer<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='longer=longer:!'")
  end)
  test("readonly text adjacent to an empty field keeps its boundary", function()
    lua([[fixture='$1$1${2:tail}$0']])
    input("i<F5>X<Tab>Y<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='XXY!'")
  end)
  test("choice whole-branch replacement survives switching", function()
    lua([[
      local s=require('snippet_tools');fixture={s.c(1,{{s.t('['),s.i(1,'field'),s.t(']')},'other'}),s.i(0)}
    ]])
    input("i<F5>replaced<F6><F7><Tab>!")
    wait("return vim.api.nvim_get_current_line()=='replaced!'")
  end)
  test("sequential API jumps discard stale selection requests", function()
    lua(
      [[vim.keymap.set('i','<F8>',function() local s=require('snippet_tools');s.expand('${1:one}-${2:two}$0');s.jump(1) end)]]
    )
    input("i<F8>X<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='one-X!'")
  end)
  test("dynamic regeneration restores user-edited fields by local index", function()
    lua([[
      local s=require('snippet_tools')
      fixture={s.i(1,'2'),s.t(':'),s.d(2,function(a)
        local result={};for j=1,math.min(4,tonumber(a[1]) or 0) do
          result[#result+1]=s.i(j,'cell');result[#result+1]=s.t('|')
        end;return result
      end,{1}),s.i(0)}
    ]])
    input("i<F5><Tab>A<Tab>B<S-Tab><S-Tab>3<Tab>")
    wait("return vim.api.nvim_get_current_line()=='3:A|B|cell|' and vim.api.nvim_get_mode().mode=='s'")
    input("<Tab><Tab>C<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='3:A|B|C|!'")
  end)
  test("regenerated empty dynamic fields stay before their following sibling", function()
    lua([[
      local s=require('snippet_tools');fixture={s.i(1,'a'),s.d(2,function()return s.i(1)end,{1}),s.i(3),s.i(0)}
    ]])
    input("i<F5>b<Tab>X<Tab>Y<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='bXY!'")
  end)
  test("choice switching does not retain dead runtime records", function()
    lua([[fixture='${1|red,blue|}$0']])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    local nodes = lua("return require('snippet_tools').inspect().nodes")
    for _ = 1, 30 do
      input("<F6>")
    end
    wait("return vim.api.nvim_get_current_line()=='red' and vim.api.nvim_get_mode().mode=='s'")
    eq(nodes, lua("return require('snippet_tools').inspect().nodes"))
    input("<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='red!'")
  end)
  test("lazy loading follows extensions and reload replaces definitions", function()
    lua([[
      loader_dir=vim.fn.tempname();vim.fn.mkdir(loader_dir,'p')
      vim.fn.writefile({"return {{trigger='loaded',body='[${1:value}]$0'}}"},loader_dir..'/tex.lua')
      vim.fn.writefile({"error('unrelated filetype loaded')"},loader_dir..'/rust.lua')
      local s=require('snippet_tools');s.filetype_extend('lua',{'tex'})
      s.setup({paths={loader_dir},keymap={['<Tab>']='expand_or_jump'}})
    ]])
    input("iloaded<Tab>X<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='[X]!'")
    lua([[
      vim.fn.writefile({"return {{trigger='new',body='new'}}"},loader_dir..'/tex.lua')
      require('snippet_tools').reload()
      local entries=require('snippet_tools').available();assert(#entries==1 and entries[1].trigger=='new')
      vim.fn.delete(loader_dir..'/tex.lua');require('snippet_tools').reload()
      assert(#require('snippet_tools').available()==0)
      vim.fn.delete(loader_dir,'rf')
    ]])
  end)
  test("setup restores existing mappings and leaves newer mappings alone", function()
    lua([[
      local s=require('snippet_tools');s.dispose()
      vim.keymap.set('i','<Tab>',function()return 'ORIGINAL'end,{expr=true})
      s.setup({keymap={['<Tab>']='expand_or_jump'}})
    ]])
    input("i<Tab>")
    wait("return vim.api.nvim_get_current_line()=='ORIGINAL'")
    lua([[
      local s=require('snippet_tools');s.dispose()
      assert(vim.fn.maparg('<Tab>','i',false,true).expr==1)
      s.setup({keymap={['<Tab>']='expand_or_jump'}})
      replacement=function()return 'NEW'end
      vim.keymap.set('i','<Tab>',replacement,{expr=true});s.dispose()
      assert(vim.fn.maparg('<Tab>','i',false,true).callback==replacement)
      vim.keymap.del('i','<Tab>')
    ]])
  end)
  test("actual Beamer example links widths and edits both column bodies", function()
    lua([[
      local s=require('snippet_tools');vim.bo.filetype='tex'
      s.setup({paths={vim.fn.getcwd()..'/examples'},keymap={['<Tab>']='expand_or_jump'}})
    ]])
    input("icolumns<Tab>60<Tab>Left<Tab>Right<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='\\\\end{columns}!'")
    local lines = lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)")
    eq("  \\begin{column}{0.60\\linewidth}", lines[2])
    eq("    Left", lines[3])
    eq("  \\begin{column}{0.38\\linewidth}", lines[5])
    eq("    Right", lines[6])
  end)
  test("actual Markdown example expands pattern captures into editable cells", function()
    lua([[
      local s=require('snippet_tools');vim.bo.filetype='markdown'
      s.setup({paths={vim.fn.getcwd()..'/examples'},keymap={['<Tab>']='expand_or_jump'}})
    ]])
    input("itable2x2 A<Tab>B<Tab>C<Tab>D<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='!'")
    eq(
      { "| A | B | ", "| --- | --- |", "| C | D | ", "!" },
      lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)")
    )
  end)
  test("undoing a field edit keeps source and mirror coherent", function()
    lua([[fixture='${1:name}=$1$0']])
    input("i<F5>X")
    wait("return vim.api.nvim_get_current_line()=='X=X'")
    input("<Esc>u")
    wait("return vim.api.nvim_get_current_line()=='name=name' and not require('snippet_tools').active()")
    input("<C-r>")
    wait("return vim.api.nvim_get_current_line()=='X=X'")
  end)
  test("deleting the complete snippet ends its session", function()
    lua([[fixture='${1:field}-$1$0']])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    input("<Esc>dd")
    wait("return vim.api.nvim_get_current_line()=='' and not require('snippet_tools').active()")
  end)
  test("callback failure leaves the previous text intact", function()
    lua([[
      local s=require('snippet_tools')
      local ok=pcall(s.expand,{s.d(1,function()error('fixture callback failure')end)})
      assert(not ok and vim.api.nvim_get_current_line()=='')
      assert(not s.active())
    ]])
  end)
  test("visual selection is captured and consumed without changing registers", function()
    lua([[
      vim.api.nvim_buf_set_lines(0,0,-1,false,{'中文 text'})
      vim.fn.setreg('a','preserved')
      vim.keymap.set('x','`',function() require('snippet_tools').cut_selection() end)
      fixture='**${TM_SELECTED_TEXT}**$0'
    ]])
    input("v$`<F5>!")
    wait("return vim.api.nvim_get_current_line()=='**中文 text**!'")
    eq("preserved", lua("return vim.fn.getreg('a')"))
    eq("", lua("return require('snippet_tools').get_selection()"))
  end)
  test("disabled automatic expansion leaves the trigger for another engine", function()
    lua([[
      local s=require('snippet_tools');s.setup({enabled=function() return false end})
      s.add('lua',{{trigger='mk',body='[$1]$0',auto=true}})
    ]])
    input("imkX")
    wait("return vim.api.nvim_get_current_line()=='mkX'")
    eq(false, lua("return require('snippet_tools').active()"))
  end)
  test("choice selection survives a temporary UI buffer and rejects stale callbacks", function()
    lua([[
      fixture='${1|red,blue|}$0'
      original_select=vim.ui.select
      vim.ui.select=function(_,_,cb)
        choice_callback=cb; choice_win=vim.api.nvim_get_current_win()
        choice_buf=vim.api.nvim_create_buf(false,true)
        vim.api.nvim_win_set_buf(choice_win,choice_buf)
      end
      vim.keymap.set({'i','s'},'<F8>',function()require('snippet_tools').select_choice()end)
    ]])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    lua("origin_buf=vim.api.nvim_get_current_buf()")
    input("<F8>")
    wait("return vim.api.nvim_get_current_buf()==choice_buf")
    lua(
      [[vim.api.nvim_win_set_buf(choice_win,origin_buf);choice_callback('blue',2);vim.ui.select=original_select]]
    )
    wait("return vim.api.nvim_get_current_line()=='blue' and vim.api.nvim_get_mode().mode=='s'")
    lua([[require('snippet_tools').stop();choice_callback('red',1)]])
    eq("blue", lua("return vim.api.nvim_get_current_line()"))
  end)
  test("placeholder selection opens closed folds without replacing their contents", function()
    lua([[fixture='pre\n${1:field}\n${2:second}$0']])
    input("i<F5><Tab><Esc>")
    wait("return vim.api.nvim_get_mode().mode=='n'")
    lua([[vim.wo.foldmethod='manual';vim.cmd('1,3fold');require('snippet_tools').jump(-1)]])
    wait("return vim.api.nvim_get_mode().mode=='s'")
    input("X<Tab>Y<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='Y!'")
    eq({ "pre", "X", "Y!" }, lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)"))
  end)
  test("a fold created after selection cannot widen the replacement range", function()
    lua([[fixture='pre\n${1:field}\n${2:second}$0';vim.wo.foldenable=true]])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    lua([[vim.wo.foldmethod='manual';vim.cmd('1,3fold');assert(not vim.wo.foldenable)]])
    input("X<Tab>Y<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='Y!'")
    eq({ "pre", "X", "Y!" }, lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)"))
    eq(true, lua("return vim.wo.foldenable"))
  end)
  local function configure_display()
    lua([[
      require('snippet_tools').setup({
        keymap={['<Tab>']='jump_forward',['<S-Tab>']='jump_backward',['<F6>']='choice_next'},
        ext_opts={
          insert={
            passive={virt_text={{'i','Comment'}},sign_text='i',sign_hl_group='Comment'},
            active={virt_text={{'I','Identifier'}},sign_text='I',sign_hl_group='Identifier'},
          },
          exit={
            passive={virt_text={{'e','Comment'}},sign_text='e'},
            active={virt_text={{'E','Identifier'}},sign_text='E'},
          },
          choice={
            passive={virt_text={{'c','Comment'}},sign_text='c',sign_hl_group='Comment'},
            active={virt_text={{'C','Type'}},sign_text='C',sign_hl_group='Type'},
          },
        },
      })
      function decorations()
        local result={}
        local ns=vim.api.nvim_get_namespaces()['snippet-tools']
        local eol_ns=vim.api.nvim_get_namespaces()['snippet-tools.eol']
        for _,mark in ipairs(vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{details=true})) do
          local d=mark[4]
          local eol=vim.api.nvim_buf_get_extmark_by_id(0,eol_ns,mark[1],{details=true})
          local text=d.virt_text or (#eol>0 and eol[3].virt_text)
          if text then
            result[#result+1]={mark[2],mark[3],text[1][1],d.sign_text:match('%S+'),d.priority,d.hl_group}
          end
        end
        return result
      end
      function eol_summary(row)
        local ns=vim.api.nvim_get_namespaces()['snippet-tools.eol']
        local entries={}
        for _,mark in ipairs(vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{details=true})) do
          if mark[2]==row then entries[#entries+1]=mark[4] end
        end
        table.sort(entries,function(a,b)return a.priority<b.priority end)
        local text,last={}
        for _,entry in ipairs(entries)do
          last=entry.virt_text[1];text[#text+1]=last[1]
        end
        return {table.concat(text),last and last[2],#entries}
      end
    ]])
  end
  test("node decorations follow field and choice transitions and clear on exit", function()
    configure_display()
    lua([[fixture='$1\n${2|red,blue|}\n$0']])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='i' and require('snippet_tools').active()")
    eq({
      { 0, 0, "I", "I", 130, "SnippetToolsActive" },
      { 1, 0, "c", "c", 120, "SnippetToolsPlaceholder" },
      { 2, 0, "e", "e", 120, "SnippetToolsPlaceholder" },
    }, lua("return decorations()"))
    input("X<Tab><F6>")
    wait("return vim.api.nvim_get_current_line()=='blue' and vim.api.nvim_get_mode().mode=='s'")
    eq({
      { 0, 0, "i", "i", 120, "SnippetToolsPlaceholder" },
      { 1, 0, "C", "C", 130, "SnippetToolsActive" },
      { 2, 0, "e", "e", 120, "SnippetToolsPlaceholder" },
    }, lua("return decorations()"))
    input("<Tab>body")
    wait("return vim.api.nvim_get_current_line()=='body' and not require('snippet_tools').active()")
    eq({}, lua("return decorations()"))
    eq(
      {},
      lua(
        "return vim.api.nvim_buf_get_extmarks(0,vim.api.nvim_get_namespaces()['snippet-tools.eol'],0,-1,{})"
      )
    )
  end)
  test("nested sessions suspend and restore their parent decorations", function()
    configure_display()
    lua([[fixture='${1:outer}-$0']])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    lua([[fixture='(${1:inner})$0']])
    input("<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s' and require('snippet_tools').inspect().depth==2")
    eq(
      { "i", "I", "e", "e" },
      lua([[local out={};for _,d in ipairs(decorations())do out[#out+1]=d[3] end;return out]])
    )
    input("X<Tab>")
    wait("return require('snippet_tools').inspect().depth==1 and vim.api.nvim_get_current_line()=='(X)-'")
    eq({ "I", "e" }, lua([[local out={};for _,d in ipairs(decorations())do out[#out+1]=d[3] end;return out]]))
    lua([[require('snippet_tools').stop()]])
    eq({}, lua("return decorations()"))
  end)
  for _, suffix in ipairs({ "", "$0", "$0-$0" }) do
    test("exit display distinguishes final stops with suffix " .. vim.inspect(suffix), function()
      configure_display()
      lua("fixture=...", "${1:field}" .. suffix)
      input("i<F5>")
      wait("return vim.api.nvim_get_mode().mode=='s'")
      eq({ "Ie", "Comment", 2 }, lua("return eol_summary(0)"))
      input("X<Tab>!")
      wait("return not require('snippet_tools').active() and vim.api.nvim_get_mode().mode=='i'")
      eq(suffix == "$0-$0" and "X!-" or "X!", lua("return vim.api.nvim_get_current_line()"))
      eq({}, lua("return decorations()"))
    end)
  end
  test("local zero fields use the active exit style without finishing the session", function()
    configure_display()
    lua([[
      local s=require('snippet_tools')
      fixture={s.c(1,{{s.i(1),s.t('|'),s.i(0)}}),s.t(':'),s.i(0)}
    ]])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    eq({ "Ciee", "Comment", 4 }, lua("return eol_summary(0)"))
    input("<Tab><Tab>")
    wait(
      "return require('snippet_tools').inspect().current=='root/1@1/0' and vim.api.nvim_get_mode().mode=='i'"
    )
    eq({ "ciEe", "Comment", 4 }, lua("return eol_summary(0)"))
    eq("E", lua([[for _,d in ipairs(decorations())do if d[5]==130 then return d[4] end end]]))
    input("<Tab>!")
    wait("return vim.api.nvim_get_current_line()=='|:!' and not require('snippet_tools').active()")
    eq({}, lua("return decorations()"))
  end)
  test("EOL overflow is per line and follows hidden activity and line splits", function()
    configure_display()
    lua([[fixture='$1|$2|$3|$4|$5\n$6|$7|$8|$9|$10|$11|$12$0']])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='i' and require('snippet_tools').active()")
    eq({ "Iiiii", "Comment", 5 }, lua("return eol_summary(0)"))
    eq({ "iiiii...", "Comment", 6 }, lua("return eol_summary(1)"))
    input(string.rep("<Tab>", 9))
    wait("return require('snippet_tools').inspect().current=='root/10'")
    eq({ "iiiiI...", "Comment", 6 }, lua("return eol_summary(1)"))
    input("<Tab>")
    wait("return require('snippet_tools').inspect().current=='root/11'")
    eq({ "iiiii...", "Identifier", 6 }, lua("return eol_summary(1)"))
    input("<Tab>")
    wait("return require('snippet_tools').inspect().current=='root/12'")
    eq({ "iiiii...", "Identifier", 6 }, lua("return eol_summary(1)"))
    input("<S-Tab><S-Tab>")
    wait("return require('snippet_tools').inspect().current=='root/10'")
    eq({ "iiiiI...", "Comment", 6 }, lua("return eol_summary(1)"))
    input("<CR>")
    wait("return vim.api.nvim_buf_line_count(0)==3")
    eq({ "iiiiI", "Identifier", 5 }, lua("return eol_summary(1)"))
    eq({ "iie", "Comment", 3 }, lua("return eol_summary(2)"))
    lua([[require('snippet_tools').stop()]])
    eq(
      {},
      lua(
        "return vim.api.nvim_buf_get_extmarks(0,vim.api.nvim_get_namespaces()['snippet-tools.eol'],0,-1,{})"
      )
    )
  end)
  test("rebuilding a choice restores markers previously hidden by overflow", function()
    configure_display()
    lua([[
      local s=require('snippet_tools')
      fixture={s.c(1,{
        {s.i(1),s.t('|'),s.i(2),s.t('|'),s.i(3),s.t('|'),s.i(4),s.t('|'),s.i(5),s.t('|'),s.i(6)},
        {s.i(1),s.t('|'),s.i(2)},
      }),s.i(0)}
    ]])
    input("i<F5>")
    wait("return require('snippet_tools').active() and vim.api.nvim_get_mode().mode=='s'")
    eq({ "Ciiii...", "Comment", 6 }, lua("return eol_summary(0)"))
    input("<F6>")
    wait("return vim.api.nvim_get_current_line()=='|' and vim.api.nvim_get_mode().mode=='s'")
    eq({ "Ciie", "Comment", 4 }, lua("return eol_summary(0)"))
    input("<F6>")
    wait("return vim.api.nvim_get_current_line()=='|||||' and vim.api.nvim_get_mode().mode=='s'")
    eq({ "Ciiii...", "Comment", 6 }, lua("return eol_summary(0)"))
  end)
  test("display options inherit, clear and reject edits to tracking options", function()
    lua([[
      local s=require('snippet_tools')
      s.setup({ext_opts={insert={
        passive={virt_text={{'passive','Comment'}},sign_text='p',hl_group='Comment'},
        active={virt_text={},sign_text=false,hl_group=false},
      }}})
      fixture='${1:field}$0'
    ]])
    input("i<F5>")
    wait("return vim.api.nvim_get_mode().mode=='s'")
    lua([[
      local s=require('snippet_tools')
      local ns=vim.api.nvim_get_namespaces()['snippet-tools']
      local eol_ns=vim.api.nvim_get_namespaces()['snippet-tools.eol']
      local plain, passive = 0
      for _,mark in ipairs(vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{details=true})) do
        local d=mark[4]
        if mark[3]==0 and d.end_col==5 then
          assert(not d.hl_group and not d.sign_text and #(d.virt_text or {})==0, vim.inspect(d))
          plain=plain+1
        elseif d.sign_text then
          passive=vim.api.nvim_buf_get_extmark_by_id(0,eol_ns,mark[1],{details=true})[3]
        end
      end
      assert(plain==2 and passive and passive.virt_text[1][1]=='passive')
      for _,opts in ipairs({
        {insert={active={right_gravity=true}}},
        {insert={active={end_row=1}}},
        {unknown={active={}}},
        {insert={visited={}}},
        {insert={active={virt_text='wrong'}}},
      }) do
        assert(not pcall(s.setup,{ext_opts=opts}))
        assert(s.active(), 'invalid display config must not stop the current session')
      end
    ]])
  end)
  local completion = vim.env.COMPLETION_TOOLS_PATH
  if completion then
    lua("vim.opt.runtimepath:append(...)", completion)
    test("completion-tools accepts Lua definitions and preserves one undo transaction", function()
      lua([[
        local s=require('snippet_tools');s.setup({keymap=false})
        s.add('lua',{{trigger='hello',body='hello ${1:world} / $1$0',description='Greeting'}})
        local opts=require('snippet_tools.integrations.completion_tools').options()
        opts.sources={'snippets'}
        require('completion_tools').setup(opts)
      ]])
      input("ihe")
      wait("return require('completion_tools')._can('accept')")
      input("<Tab>user<Tab>!")
      wait("return vim.api.nvim_get_current_line()=='hello user / user!'")
    end)
    for _, mode in ipairs({ 1, 2 }) do
      test("completion-tools LSP snippets respect insertTextMode=" .. mode, function()
        lua(
          [[
          local mode=...
          local s=require('snippet_tools');s.setup({keymap=false})
          local opts=require('snippet_tools.integrations.completion_tools').options()
          opts.sources={'fixture'}; opts.providers.fixture={complete=function(_,cb)
            cb({items={{label='block',insertText='block\n\t${1:value}\n$0',insertTextFormat=2,insertTextMode=mode}}})
          end}
          require('completion_tools').setup(opts)
          vim.api.nvim_buf_set_lines(0,0,-1,false,{'    blTAIL'});vim.api.nvim_win_set_cursor(0,{1,6})
        ]],
          mode
        )
        input("i<C-Space>")
        wait("return require('completion_tools')._can('accept')")
        input("<Tab>changed<Tab>!")
        wait("return vim.api.nvim_get_current_line():find('!',1,true)~=nil")
        eq(
          mode == 1 and { "    block", "\tchanged", "!TAIL" } or { "    block", "      changed", "    !TAIL" },
          lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)")
        )
      end)
    end
  end
end, debug.traceback)
pcall(rpc, "nvim_command", "qa!")
vim.fn.jobstop(child)
assert(ok, err)
print("input: " .. count .. " scenarios passed")
