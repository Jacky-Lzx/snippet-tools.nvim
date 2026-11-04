local engine = assert(vim.env.SNIPPET_BENCH_ENGINE)
vim.opt.rtp:prepend(assert(vim.env.SNIPPET_BENCH_ROOT))
if engine == "luasnip" then
  vim.opt.rtp:append(assert(vim.env.SNIPPET_BENCH_LUASNIP))
end
vim.loader.enable()
vim.o.swapfile = false
vim.o.shadafile = "NONE"
local clock = vim.uv.hrtime
collectgarbage("collect")
local baseline = collectgarbage("count")
local start = clock()
local s = require(engine == "snippet-tools" and "snippet_tools" or "luasnip")
local require_ms = (clock() - start) / 1e6
start = clock()
if engine == "snippet-tools" then
  s.setup({ keymap = false })
else
  s.setup({
    enable_autosnippets = true,
    keep_roots = false,
    link_roots = false,
    link_children = true,
    exit_roots = true,
    update_events = { "TextChanged", "TextChangedI" },
    delete_check_events = { "TextChanged", "TextChangedI" },
  })
end
local setup_ms = (clock() - start) / 1e6
collectgarbage("collect")
local result = {
  engine = engine,
  require_ms = require_ms,
  setup_ms = setup_ms,
  module_heap_kib = collectgarbage("count") - baseline,
  cases = {},
  neovim = tostring(vim.version()),
}
if vim.env.SNIPPET_BENCH_LOAD_ONLY == "1" then
  vim.fn.writefile({ vim.json.encode(result) }, assert(vim.env.SNIPPET_BENCH_RESULT))
  return
end
local fixtures = dofile(vim.env.SNIPPET_BENCH_ROOT .. "/bench/fixtures.lua")
local rounds = tonumber(vim.env.SNIPPET_BENCH_CORE_SAMPLES) or 200
local function measure(name, fn, validate, batch)
  batch = batch or 1
  for _ = 1, 30 do
    fn()
  end
  validate(fn())
  local estimate_start = clock()
  fn()
  local estimate = math.max(1, clock() - estimate_start)
  batch = math.max(1, math.min(batch, math.floor(100000 / estimate)))
  io.stderr:write(name .. " batch=" .. batch .. "\n")
  io.stderr:flush()
  local samples = {}
  for i = 1, rounds do
    local began = clock()
    local value
    for _ = 1, batch do
      value = fn()
    end
    samples[i] = (clock() - began) / 1000 / batch
    validate(value)
  end
  result.cases[#result.cases + 1] =
    { name = name, unit = "us", samples = samples, batch = batch, failures = 0 }
  vim.fn.writefile({ vim.json.encode(result) }, assert(vim.env.SNIPPET_BENCH_RESULT))
end
local function clear()
  if engine == "snippet-tools" then
    require("snippet_tools.registry").clear()
  else
    s.cleanup()
  end
end
for _, spec in ipairs({ { 100, false }, { 1000, false }, { 5000, false }, { 100, true }, { 1000, true } }) do
  local size, pattern = spec[1], spec[2]
  clear()
  collectgarbage("collect")
  local before = collectgarbage("count")
  start = clock()
  fixtures.collection(engine, size, pattern)
  local registration = (clock() - start) / 1e6
  collectgarbage("collect")
  local suffix = (pattern and "patterns/" or "literals/") .. size
  result.cases[#result.cases + 1] =
    { name = "register/" .. suffix, unit = "ms", samples = { registration }, failures = 0 }
  result.cases[#result.cases + 1] = {
    name = "collection_heap/" .. suffix,
    unit = "KiB",
    samples = { collectgarbage("count") - before },
    failures = 0,
  }
  local ctx = { filetype = "bench", before = "ordinary text z", cache = {} }
  local inputs, counter = {}, 0
  local function lines(suffix)
    for i = 1, 32 do
      inputs[i] = "prefix " .. i .. " " .. suffix
    end
  end
  lines("ordinary text z")
  local function match()
    counter = counter + 1
    ctx.before = inputs[(counter % #inputs) + 1]
    if engine == "snippet-tools" then
      return require("snippet_tools.registry").find(ctx, true)
    end
    return require("luasnip.session.snippet_collection").match_snippet(
      ctx.before,
      { "bench" },
      "autosnippets"
    )
  end
  start = clock()
  assert(match() == nil)
  result.cases[#result.cases + 1] =
    { name = "first_lookup/" .. suffix, unit = "ms", samples = { (clock() - start) / 1e6 }, failures = 0 }
  collectgarbage("collect")
  result.cases[#result.cases + 1] = {
    name = "indexed_heap/" .. suffix,
    unit = "KiB",
    samples = { collectgarbage("count") - before },
    failures = 0,
  }
  measure("no_match/" .. suffix, match, function(v)
    assert(v == nil)
  end, 10)
  if not pattern then
    lines("not_a_trigger0")
    measure("same_suffix_miss/" .. suffix, match, function(v)
      assert(v == nil)
    end, 10)
  end
  lines(pattern and ("rx" .. size .. "_42 ") or ("snippet" .. size))
  measure("last_match/" .. suffix, match, function(v)
    assert(v and v.trigger == (pattern and "rx" .. size .. "_(%d+) " or "snippet" .. size))
  end, 10)
end
clear()
vim.fn.writefile({ vim.json.encode(result) }, assert(vim.env.SNIPPET_BENCH_RESULT))
