local api = vim.api
local M = {}
local ns = api.nvim_create_namespace("snippet-tools")
local eol_ns = api.nvim_create_namespace("snippet-tools.eol")
local display = require("snippet_tools.display")
local stacks, attached, tickets, marks = {}, {}, {}, {}
local serial, mutating = 0, false
local fold_locks = {}
local sync
local function protect_selection(session)
  local win = api.nvim_get_current_win()
  local lock = fold_locks[win]
  if not lock then
    lock = { before = vim.wo[win].foldenable, owners = {} }
    fold_locks[win] = lock
  end
  lock.owners[session], session.fold_win = true, win
  vim.wo[win].foldenable = false
end
local function release_selection(session)
  local win = session.fold_win
  local lock = win and fold_locks[win]
  session.fold_win = nil
  if not lock then
    return
  end
  lock.owners[session] = nil
  if not next(lock.owners) then
    if api.nvim_win_is_valid(win) and not vim.wo[win].foldenable then
      vim.wo[win].foldenable = lock.before
    end
    fold_locks[win] = nil
  end
end

local function point(row, col)
  return { row, col }
end
local function le(a, b)
  return a[1] < b[1] or (a[1] == b[1] and a[2] <= b[2])
end
local function equal(a, b)
  return a[1] == b[1] and a[2] == b[2]
end
local function cursor()
  local p = api.nvim_win_get_cursor(0)
  return point(p[1] - 1, p[2])
end
local function top(buf)
  local stack = stacks[buf or api.nvim_get_current_buf()] or {}
  return stack[#stack]
end
local function range(session, record, bounds, mark)
  if
    record.dead
    or not record.mark
    or (bounds and not bounds.valid)
    or (not bounds and not api.nvim_buf_is_valid(session.buf))
  then
    return
  end
  mark = mark or api.nvim_buf_get_extmark_by_id(session.buf, ns, record.mark, { details = true })
  if #mark == 0 then
    return
  end
  local count = bounds and bounds.count or api.nvim_buf_line_count(session.buf)
  if mark[1] >= count or mark[3].end_row >= count then
    return
  end
  local function line(row)
    if bounds and bounds.lines[row] then
      return bounds.lines[row]
    end
    local text = api.nvim_buf_get_lines(session.buf, row, row + 1, false)[1]
    if bounds then
      bounds.lines[row] = text
    end
    return text
  end
  local first = line(mark[1])
  local last = mark[1] == mark[3].end_row and first or line(mark[3].end_row)
  if mark[2] > #first or mark[3].end_col > #last then
    return
  end
  return point(mark[1], mark[2]), point(mark[3].end_row, mark[3].end_col)
end
local function contents(session, record)
  local a, b = range(session, record)
  return a and table.concat(api.nvim_buf_get_text(session.buf, a[1], a[2], b[1], b[2], {}), "\n")
end
local function descendant(record, parent)
  while record do
    if record == parent then
      return true
    end
    record = record.parent
  end
  return false
end
local function setmark(session, record, a, b, left, right)
  record.left_gravity, record.right_gravity = left, right
  record.highlight_active = session == top(session.buf) and record == session.current
  local kind = record.kind ~= "mirror" and record.node and record.node.index == 0 and "exit" or record.kind
  local opts = vim.tbl_extend("force", {}, display.options(kind, record.highlight_active))
  local eol
  if
    opts.virt_text
    and #opts.virt_text > 0
    and (not opts.virt_text_pos or opts.virt_text_pos == "eol")
    and not opts.virt_text_win_col
  then
    -- EOL text is sorted by priority before position. refresh_eol assigns stable
    -- priorities by field order; range highlights and signs remain independent.
    eol = {
      virt_text = opts.virt_text,
      virt_text_pos = "eol",
      virt_text_hide = opts.virt_text_hide,
      hl_mode = opts.hl_mode,
      priority = 120,
      right_gravity = left,
      undo_restore = false,
    }
    opts.virt_text = nil
  end
  record.mark = api.nvim_buf_set_extmark(
    session.buf,
    ns,
    a[1],
    a[2],
    vim.tbl_extend("force", opts, {
      id = record.mark,
      end_row = b[1],
      end_col = b[2],
      right_gravity = left,
      end_right_gravity = right,
      undo_restore = false,
    })
  )
  record.eol_opts = eol
  session.has_eol = session.has_eol or eol ~= nil
  if not eol and record.eol_mark then
    api.nvim_buf_del_extmark(session.buf, eol_ns, record.eol_mark)
    record.eol_mark = nil
  end
  marks[session.buf] = marks[session.buf] or {}
  marks[session.buf][record.mark], record.owner = record, session
end
local function delmark(session, record)
  if record.eol_mark then
    api.nvim_buf_del_extmark(session.buf, eol_ns, record.eol_mark)
    record.eol_mark = nil
  end
  if record.mark then
    api.nvim_buf_del_extmark(session.buf, ns, record.mark)
    if marks[session.buf] then
      marks[session.buf][record.mark] = nil
    end
  end
end
local function each_record(buf, fn)
  for _, session in ipairs(stacks[buf] or {}) do
    fn(session, session.root)
    for _, record in ipairs(session.records) do
      if not record.dead then
        fn(session, record)
      end
    end
  end
end
local function refresh_eol(buf)
  local needed, prefixes, prefix = false, {}, {}
  for _, session in ipairs(stacks[buf] or {}) do
    needed = needed or session.has_eol
    prefixes[session] = prefix
    prefix = vim.list_extend(vim.list_extend({}, prefix), session.current and session.current.path or {})
  end
  if not needed then
    return
  end
  local rows, index = {}, marks[buf] or {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})) do
    local record = index[mark[1]]
    if record and not record.dead and record.eol_opts then
      rows[mark[2]] = rows[mark[2]] or {}
      rows[mark[2]][#rows[mark[2]] + 1] = {
        record = record,
        col = mark[3],
        order = vim.list_extend(vim.list_extend({}, prefixes[record.owner]), record.path),
      }
    end
  end
  for row, entries in pairs(rows) do
    table.sort(entries, function(a, b)
      if a.col ~= b.col then
        return a.col < b.col
      end
      for i = 1, math.max(#a.order, #b.order) do
        if a.order[i] ~= b.order[i] then
          if a.order[i] == nil then
            return true
          elseif b.order[i] == nil then
            return false
          end
          return a.order[i] < b.order[i]
        end
      end
      return a.record.mark < b.record.mark
    end)
    local overflow = entries[6] and entries[6].record
    local style = overflow and overflow.eol_opts
    for i = 6, #entries do
      if entries[i].record.highlight_active then
        style = entries[i].record.eol_opts
        break
      end
    end
    for i, entry in ipairs(entries) do
      local record, opts = entry.record
      if i <= 5 then
        opts = record.eol_opts
      elseif i == 6 then
        opts = vim.tbl_extend("force", {}, record.eol_opts, {
          virt_text = { { "...", style.virt_text[1][2] } },
        })
      end
      if opts then
        record.eol_mark = api.nvim_buf_set_extmark(
          buf,
          eol_ns,
          row,
          entry.col,
          vim.tbl_extend("force", {}, opts, { id = record.mark, priority = 119 + i })
        )
      elseif record.eol_mark then
        api.nvim_buf_del_extmark(buf, eol_ns, record.eol_mark)
        record.eol_mark = nil
      end
    end
  end
end
local function assign_gravity(session, target, start, finish, owner, record, a, b)
  local left, right = false, true
  if owner == session and descendant(target, record) then
    left, right = false, true
  elseif equal(b, start) and record.rank <= target.rank then
    left, right = false, false
  elseif equal(finish, a) then
    left, right = true, true
  end
  -- Only shared boundaries need to exclude the active edit. Distant records
  -- must retain both endpoints when another editor (e.g. LSP linked editing)
  -- replaces their text before the scheduled dependency sync runs.
  if
    record.left_gravity ~= left
    or record.right_gravity ~= right
    or record.highlight_active ~= (owner == top(owner.buf) and record == owner.current)
  then
    setmark(owner, record, a, b, left, right)
  end
end
local function gravity(session, target, start, finish, edit)
  -- Bounds are shared only during this synchronous pass, never across edits.
  local bounds = { valid = api.nvim_buf_is_valid(session.buf), lines = {} }
  if bounds.valid then
    bounds.count = api.nvim_buf_line_count(session.buf)
  end
  if not start then
    start, finish = range(session, target, bounds)
  end
  if not start then
    return
  end
  if edit then
    -- A replacement only moves endpoints inside or touching its range. Marks
    -- elsewhere need no gravity adjustment until the active field is restored.
    -- overlap=true includes ancestors and ranges ending at the start boundary.
    local index = marks[session.buf] or {}
    for _, mark in
      ipairs(api.nvim_buf_get_extmarks(session.buf, ns, start, finish, { details = true, overlap = true }))
    do
      local record = index[mark[1]]
      if record then
        local owner = record.owner
        local a, b = range(owner, record, bounds, { mark[2], mark[3], mark[4] })
        if a then
          assign_gravity(session, target, start, finish, owner, record, a, b)
        end
      end
    end
  else
    each_record(session.buf, function(owner, record)
      local a, b = range(owner, record, bounds)
      if a then
        assign_gravity(session, target, start, finish, owner, record, a, b)
      end
    end)
  end
  if not edit then
    refresh_eol(session.buf)
  end
end

local function position(text, offset, origin)
  local prefix = text:sub(1, offset)
  local _, newlines = prefix:gsub("\n", "")
  return point(origin[1] + newlines, newlines == 0 and origin[2] + #prefix or #prefix:match("[^\n]*$"))
end
local function format_model(session, model)
  local map, parts, offset = { [0] = 0 }, {}, 0
  for i = 1, #model.text do
    local char = model.text:sub(i, i)
    local piece = char == "\n" and "\n" .. session.indentation
      or (char == "\t" and session.expand_tabs and string.rep(" ", session.tab_width) or char)
    parts[#parts + 1], offset = piece, offset + #piece
    map[i] = offset
  end
  for _, record in ipairs(model.records) do
    record.start, record.finish = map[record.start], map[record.finish]
  end
  model.text = table.concat(parts)
  model.line_starts = { 0 }
  for offset in model.text:gmatch("()\n") do
    model.line_starts[#model.line_starts + 1] = offset
  end
  return model
end
local function model_position(model, offset, origin)
  local starts = model.line_starts
  local low, high = 1, #starts
  while low < high do
    local middle = math.floor((low + high + 1) / 2)
    if starts[middle] <= offset then
      low = middle
    else
      high = middle - 1
    end
  end
  return point(origin[1] + low - 1, offset - starts[low] + (low == 1 and origin[2] or 0))
end
local function saved_text(session, text)
  local lines = vim.split(text, "\n", { plain = true })
  for i = 2, #lines do
    if lines[i]:sub(1, #session.indentation) == session.indentation then
      lines[i] = lines[i]:sub(#session.indentation + 1)
    end
  end
  return table.concat(lines, "\n")
end
local function save_children(session, parent, edited_only)
  for id, child in pairs(session.groups) do
    if child ~= parent and not child.dead and descendant(child, parent) then
      local text = contents(session, child)
      if not edited_only or text ~= child.initial_value then
        session.saved[id] = saved_text(session, text)
      end
    end
  end
end
local function options(session, scope, order)
  return {
    scope = scope,
    order = order,
    variables = session.variables,
    resolve_variable = session.resolve_variable,
    context = session.context,
    values = session.saved,
    choices = session.choices,
  }
end
local function install(session, model, origin, parent)
  session.navigation, session.synced_tick = nil, nil
  for _, record in ipairs(model.records) do
    -- Literal text cannot be edited or recomputed independently. Its enclosing
    -- placeholder/root already tracks it; an extra extmark only adds work.
    if record.kind ~= "text" then
      record.rank = #session.records + 1
      if record.parent == nil then
        record.parent = parent or session.root
      end
      record.path = {}
      for i, value in ipairs(record.parent.path or {}) do
        record.path[i] = value
      end
      record.path[#record.path + 1] = record.ordinal
      session.records[#session.records + 1] = record
      setmark(
        session,
        record,
        model_position(model, record.start, origin),
        model_position(model, record.finish, origin),
        false,
        true
      )
      if record.key and record.kind ~= "mirror" then
        session.groups[record.key] = record
        record.initial_value = model.text:sub(record.start + 1, record.finish)
      end
    end
  end
  local live = {}
  for _, record in ipairs(session.records) do
    if not record.dead then
      live[#live + 1] = record
    end
  end
  table.sort(live, function(a, b)
    for i = 1, math.max(#a.path, #b.path) do
      if a.path[i] ~= b.path[i] then
        if a.path[i] == nil then
          return true
        end
        if b.path[i] == nil then
          return false
        end
        return a.path[i] < b.path[i]
      end
    end
    return a.rank < b.rank
  end)
  session.records = live
  for i, record in ipairs(live) do
    record.rank = i
  end
end
local function group_text(session, key, values)
  local value = values and values[key]
  if value == nil then
    local record = session.groups[key]
    value = record and contents(session, record) or ""
    if values then
      values[key] = value
    end
  end
  return value
end
local function arguments(session, record, values)
  local args = {}
  for i, dep in ipairs(record.node.deps or {}) do
    args[i] = group_text(session, record.scope .. "/" .. dep, values)
  end
  return args
end
local function remember_arguments(session, initial)
  for _, record in ipairs(session.records) do
    -- Existing records must retain their old arguments so the next sync sees
    -- changes caused by a rebuilt choice/dynamic subtree.
    if record.node.deps and record.args == nil and not record.dead then
      record.args = arguments(session, record)
    end
    if record.key and record.kind ~= "mirror" and not record.dead then
      record.last_value = initial and record.initial_value or contents(session, record)
    end
  end
end
local function remove_children(session, parent)
  for _, record in ipairs(session.records) do
    if record ~= parent and not record.dead and descendant(record, parent) then
      record.dead = true
      session.navigation, session.synced_tick = nil, nil
      delmark(session, record)
      if session.groups[record.key] == record then
        session.groups[record.key] = nil
      end
    end
  end
end
local function replace(session, record, text)
  local a, b = range(session, record)
  assert(a, "snippet-tools: target no longer exists")
  gravity(session, record, a, b, true)
  pcall(vim.cmd, "undojoin")
  mutating = true
  local ok, err =
    pcall(api.nvim_buf_set_text, session.buf, a[1], a[2], b[1], b[2], vim.split(text, "\n", { plain = true }))
  mutating = false
  if not ok then
    error(err)
  end
  setmark(session, record, a, position(text, #text, a), false, true)
  return a
end

local function navigation(session)
  if session.navigation then
    return session.navigation
  end
  local result = {}
  for _, record in pairs(session.groups) do
    if not record.dead and record.kind ~= "dynamic" then
      result[#result + 1] = record
    end
  end
  table.sort(result, function(a, b)
    for i = 1, math.max(#a.order, #b.order) do
      if a.order[i] ~= b.order[i] then
        if a.order[i] == nil then
          return true
        end
        if b.order[i] == nil then
          return false
        end
        return a.order[i] < b.order[i]
      end
    end
    return a.rank < b.rank
  end)
  session.navigation = result
  return result
end

local function dispose(session)
  release_selection(session)
  if session.ticket then
    tickets[session.ticket] = nil
  end
  if api.nvim_buf_is_valid(session.buf) then
    delmark(session, session.root)
    for _, record in ipairs(session.records) do
      delmark(session, record)
    end
  end
end

function M.stop(buf, all)
  buf = buf or api.nvim_get_current_buf()
  local stack = stacks[buf] or {}
  repeat
    local session = table.remove(stack)
    if session then
      dispose(session)
    end
  until not all or #stack == 0
  stacks[buf] = #stack > 0 and stack or nil
  if #stack == 0 then
    marks[buf] = nil
  end
  local parent = top(buf)
  if parent and parent.current then
    parent.synced_tick = nil
    gravity(parent, parent.current)
  end
end

local function feed(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "in", false)
end
function M._selected(ticket)
  local session = tickets[ticket]
  if session then
    session.pending = false
    tickets[ticket] = nil
    if session.finishing and top(session.buf) == session then
      M.stop(session.buf)
      if session.buf == api.nvim_get_current_buf() then
        M.update()
      end
    else
      api.nvim_exec_autocmds("User", {
        pattern = "SnippetToolsEnter",
        modeline = false,
        data = { bufnr = session.buf, field = session.current.key },
      })
    end
  end
end
function M._select(ticket)
  local session = tickets[ticket]
  if session and top() == session then
    feed(("<Esc><Cmd>lua require('snippet_tools.session')._place(%d)<CR>"):format(ticket))
  end
end
function M._place(ticket)
  local session = tickets[ticket]
  if not session or top() ~= session then
    tickets[ticket] = nil
    return
  end
  local record = session.current
  local a, b = range(session, record)
  if not a then
    return
  end
  if not equal(a, b) and record.node.index ~= 0 then
    -- Async fold expressions can create a new closed fold after the endpoints
    -- were opened. Suspend folding only while the field is selected; restoring
    -- it after replacement prevents Select mode from deleting that entire fold.
    protect_selection(session)
  else
    release_selection(session)
  end
  -- A Visual selection starting on a closed fold includes the folded region.
  -- Open both endpoints in Normal mode before selecting a placeholder.
  for _, pos in ipairs({ b, a }) do
    api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
    vim.cmd("normal! zv")
  end
  if equal(a, b) or record.node.index == 0 then
    api.nvim_win_set_cursor(0, { a[1] + 1, a[2] })
    vim.cmd.startinsert({ bang = a[2] >= #api.nvim_get_current_line() })
    M._selected(ticket)
  else
    local last = b
    if b[2] == 0 and b[1] > a[1] then
      local line = api.nvim_buf_get_lines(session.buf, b[1] - 1, b[1], false)[1]
      last = point(b[1] - 1, #line + 1)
    end
    local extra = vim.o.selection == "exclusive" and "l" or ""
    feed(
      ("<Cmd>call cursor(%d,%d)<CR>v<Cmd>call cursor(%d,%d)<CR>%so<C-g><C-r>_<Cmd>lua require('snippet_tools.session')._selected(%d)<CR>"):format(
        a[1] + 1,
        a[2] + 1,
        last[1] + 1,
        last[2],
        extra,
        ticket
      )
    )
  end
end
local function select(session, record)
  if session.ticket then
    tickets[session.ticket] = nil
  end
  session.current = record
  gravity(session, record)
  serial = serial + 1
  session.ticket, session.pending, tickets[serial] = serial, true, session
  feed(("<Cmd>lua require('snippet_tools.session')._select(%d)<CR>"):format(serial))
end

sync = function(buf)
  local session = top(buf)
  if not session or mutating or session.syncing or not api.nvim_buf_is_loaded(buf) then
    return
  end
  local tick = api.nvim_buf_get_changedtick(buf)
  local first, last = range(session, session.root)
  if not first or (equal(first, last) and session.nonempty) then
    M.stop(buf, true)
    return
  end
  if session.synced_tick == tick and session.synced_current == session.current then
    return
  end
  session.syncing = true
  local ok, err = xpcall(function()
    local tree = vim.fn.undotree()
    if tree.seq_cur < session.seq then
      M.stop(buf, true)
      return
    end
    -- Propagate from the innermost session to its enclosing placeholders.
    for si = #(stacks[buf] or {}), 1, -1 do
      local owner = stacks[buf][si]
      local current = owner.current
      if
        owner == session
        and current
        and not owner.pending
        and current.last_value ~= contents(owner, current)
      then
        remove_children(owner, current)
        current.overridden = true
      end
      for pass = 1, 16 do
        local dirty = false
        local updates, values = {}, {}
        for _, record in ipairs(owner.records) do
          if not record.dead then
            if record.kind == "mirror" then
              local value = group_text(owner, record.key, values)
              if contents(owner, record) ~= value then
                updates[#updates + 1] = { record, value }
              end
            elseif record.kind == "function" or record.kind == "dynamic" then
              local args = arguments(owner, record, values)
              if not vim.deep_equal(args, record.args) then
                local value = record.node.fn(args, owner.context)
                record.args = args
                updates[#updates + 1] = { record, value, record.kind == "dynamic" }
              end
            end
          end
        end
        for _, update in ipairs(updates) do
          local record = update[1]
          if not record.dead then
            if update[3] then
              save_children(owner, record, true)
              local model = format_model(
                owner,
                require("snippet_tools.render").render(
                  require("snippet_tools.nodes").normalize(update[2] or {}),
                  options(owner, record.key .. "@dynamic", record.order)
                )
              )
              remove_children(owner, record)
              local origin = replace(owner, record, model.text)
              install(owner, model, origin, record)
              remember_arguments(owner)
            else
              replace(owner, record, tostring(update[2] or ""))
            end
            dirty = true
          end
        end
        if not dirty then
          break
        end
        assert(pass < 16, "snippet-tools: dependency updates did not converge")
      end
      owner.seq = tree.seq_cur
      for _, record in ipairs(owner.records) do
        if record.key and record.kind ~= "mirror" and not record.dead then
          record.last_value = contents(owner, record)
        end
      end
    end
    if top(buf) == session and session.current then
      gravity(session, session.current)
      session.synced_tick = api.nvim_buf_get_changedtick(buf)
      session.synced_current = session.current
    end
  end, debug.traceback)
  session.syncing = false
  if not ok then
    M.stop(buf, true)
    vim.notify(err, vim.log.levels.ERROR)
  end
end
M.update = function()
  sync(api.nvim_get_current_buf())
end

local function attach(buf)
  if attached[buf] then
    return
  end
  attached[buf] = true
  local pending = false
  api.nvim_buf_attach(buf, false, {
    on_bytes = function()
      if not stacks[buf] then
        attached[buf] = nil
        return true
      end
      if not mutating and not pending then
        pending = true
        vim.schedule(function()
          pending = false
          if buf == api.nvim_get_current_buf() then
            sync(buf)
          end
        end)
      end
    end,
    on_reload = function()
      M.stop(buf, true)
    end,
    on_detach = function()
      M.stop(buf, true)
      attached[buf] = nil
    end,
  })
end

function M.expand(body, opts)
  opts = opts or {}
  local buf = api.nvim_get_current_buf()
  assert(vim.bo[buf].modifiable, "snippet-tools: buffer is not modifiable")
  sync(buf)
  local parent = top(buf)
  local a, b = cursor(), cursor()
  if opts.range then
    a, b = opts.range[1], opts.range[2]
  elseif api.nvim_get_mode().mode == "s" and parent and parent.current then
    a, b = range(parent, parent.current)
  end
  if parent then
    local start, finish
    if parent.current then
      start, finish = range(parent, parent.current)
    end
    if not start or not le(start, a) or not le(b, finish) then
      M.stop(buf, true)
      parent = nil
    end
  end
  local session = {
    buf = buf,
    records = {},
    groups = {},
    saved = {},
    choices = {},
    variables = opts.variables,
    resolve_variable = opts.resolve_variable,
    context = opts.context,
    root = { rank = 0 },
    indentation = opts.indent ~= false and api.nvim_get_current_line():match("^[ \t]*") or "",
    expand_tabs = opts.expand_tabs ~= false and vim.bo[buf].expandtab,
    tab_width = vim.fn.shiftwidth(),
  }
  local model = format_model(session, require("snippet_tools.render").render(body, options(session)))
  if not opts.join_undo then
    vim.o.undolevels = vim.o.undolevels
  else
    pcall(vim.cmd, "undojoin")
  end
  mutating = true
  local ok, err =
    pcall(api.nvim_buf_set_text, buf, a[1], a[2], b[1], b[2], vim.split(model.text, "\n", { plain = true }))
  mutating = false
  if not ok then
    error(err)
  end
  stacks[buf] = stacks[buf] or {}
  table.insert(stacks[buf], session)
  setmark(session, session.root, a, model_position(model, #model.text, a), false, true)
  install(session, model, a)
  if not session.groups["root/0"] then
    local final = {
      kind = "insert",
      key = "root/0",
      node = { index = 0 },
      order = { math.huge },
      parent = session.root,
      rank = #session.records + 1,
      path = { math.huge },
    }
    session.groups[final.key] = final
    session.records[#session.records + 1] = final
    local finish = model_position(model, #model.text, a)
    setmark(session, final, finish, finish, true, true)
  end
  session.nonempty, session.seq = model.text ~= "", vim.fn.undotree().seq_cur
  -- The freshly inserted model is authoritative; do not read every field back
  -- through extmarks before any external edit can occur.
  remember_arguments(session, true)
  attach(buf)
  local first = navigation(session)[1]
  select(session, first)
  if first.key == "root/0" then
    -- Keep selection alive until its queued cursor placement has completed.
    session.finishing = true
  end
  if not parent then
    -- A fresh root's model, values and argument snapshots are already in sync.
    -- Nested expansions must still propagate their changed text to ancestors.
    session.synced_tick = api.nvim_buf_get_changedtick(buf)
    session.synced_current = first
  end
  return true
end

function M.active(direction)
  local session = top()
  if not session or session.finishing then
    return false
  end
  if not direction then
    return true
  end
  local list = navigation(session)
  for i, record in ipairs(list) do
    if record == session.current then
      return list[i + direction] ~= nil
    end
  end
  return false
end

function M.jump(direction)
  assert(direction == 1 or direction == -1, "snippet-tools: direction must be 1 or -1")
  M.update()
  local session = top()
  if not session or session.finishing then
    return false
  end
  local list = navigation(session)
  for i, record in ipairs(list) do
    if record == session.current and list[i + direction] then
      local next_record = list[i + direction]
      select(session, next_record)
      if next_record.key == "root/0" then
        session.finishing = true
      end
      return true
    end
  end
  return false
end

function M.choices()
  local session = top()
  local record = session and session.current
  if record and record.kind == "choice" then
    return record.node.branches, record.choice
  end
end

function M.set_choice(index)
  M.update()
  local session = top()
  local record = session and session.current
  if not record or record.kind ~= "choice" then
    return false
  end
  assert(
    type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #record.node.branches,
    "snippet-tools: invalid choice index"
  )
  local old = record.choice
  -- Snapshot both the whole edited alternative and its editable descendants.
  record.snapshots = record.snapshots or {}
  record.snapshots[old] = contents(session, record)
  record.overrides = record.overrides or {}
  if record.overridden then
    record.overrides[old] = record.snapshots[old]
  end
  save_children(session, record, false)
  record.choice = index
  session.choices[record.key] = record.choice
  record.overridden = record.overrides[record.choice] ~= nil
  local model = format_model(
    session,
    require("snippet_tools.render").render(
      record.overridden and { require("snippet_tools.nodes").text(record.overrides[record.choice]) }
        or record.node.branches[record.choice],
      options(session, record.key .. "@" .. record.choice, record.order)
    )
  )
  remove_children(session, record)
  local origin = replace(session, record, model.text)
  install(session, model, origin, record)
  -- Alternatives containing only text are editable too.
  if not next(model.groups) and record.snapshots[record.choice] then
    replace(session, record, record.snapshots[record.choice])
  end
  remember_arguments(session)
  select(session, record)
  M.update()
  return true
end

function M.change_choice(direction)
  assert(direction == 1 or direction == -1, "snippet-tools: direction must be 1 or -1")
  local choices, index = M.choices()
  return choices and M.set_choice((index - 1 + direction) % #choices + 1) or false
end

local function describe(nodes)
  local parts = {}
  for _, node in ipairs(nodes) do
    parts[#parts + 1] = node.kind == "text" and node.text
      or (node.children and describe(node.children))
      or (node.kind == "choice" and describe(node.branches[1]))
      or (node.kind == "mirror" and "$" .. node.index)
      or ("<" .. node.kind .. ">")
  end
  return table.concat(parts):gsub("\n", " ↵ ")
end
function M.select_choice()
  local session = top()
  local record = session and session.current
  if not record or record.kind ~= "choice" then
    return false
  end
  local win, labels = api.nvim_get_current_win(), {}
  for i, branch in ipairs(record.node.branches) do
    labels[i] = describe(branch)
  end
  session.selecting = true
  local ok, err = pcall(vim.ui.select, labels, { prompt = "Snippet choice" }, function(_, index)
    if top(session.buf) ~= session or session.current ~= record then
      return
    end
    session.selecting = false
    if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= session.buf then
      M.stop(session.buf, true)
      return
    end
    api.nvim_set_current_win(win)
    if index then
      M.set_choice(index)
    else
      select(session, record)
    end
  end)
  if not ok then
    session.selecting = false
    error(err)
  end
  return true
end
function M.leave_buffer(buf)
  local session = top(buf)
  if not session or not session.selecting then
    M.stop(buf, true)
  end
end

function M.check_cursor()
  local session = top()
  if not session then
    return
  end
  local mode = api.nvim_get_mode().mode
  if
    not session.pending
    and mode ~= "s"
    and mode ~= "S"
    and mode ~= "\19"
    and mode ~= "v"
    and mode ~= "V"
    and mode ~= "\22"
  then
    release_selection(session)
  end
  if session.finishing and not session.pending then
    M.stop(session.buf)
    M.update()
    return
  end
  if session.pending then
    return
  end
  local a, b = range(session, session.root)
  local pos = cursor()
  if not a or not le(a, pos) or not le(pos, b) then
    M.stop(session.buf)
  end
end

function M.inspect()
  local session = top()
  if not session then
    return { active = false, depth = 0 }
  end
  local a, b = range(session, session.root)
  return {
    active = not session.finishing,
    depth = #stacks[session.buf],
    current = session.current and session.current.key,
    range = { a, b },
    pending = session.pending or false,
    choices = session.current and session.current.choice,
    nodes = #session.records,
    fields = vim.tbl_count(session.groups),
  }
end

function M.dispose()
  for buf in pairs(stacks) do
    M.stop(buf, true)
  end
end

return M
