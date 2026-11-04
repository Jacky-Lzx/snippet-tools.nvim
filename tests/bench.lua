local parser = require("snippet_tools.parser")
local render = require("snippet_tools.render")
local registry = require("snippet_tools.registry")
local clock = vim.uv.hrtime
local function bench(name, iterations, fn)
  for _ = 1, 100 do
    fn()
  end
  local samples = {}
  for i = 1, iterations do
    local start = clock()
    fn()
    samples[i] = (clock() - start) / 1000
  end
  table.sort(samples)
  print(
    ("%s: median %.2f us, p95 %.2f us (%d iterations)"):format(
      name,
      samples[math.ceil(iterations * 0.5)],
      samples[math.ceil(iterations * 0.95)],
      iterations
    )
  )
end
local body = "function ${1:name}(${2:args})\n\t${3:body}\nend -- $1$0"
local compiled = parser.parse(body)
bench("cached parse", 2000, function()
  parser.parse(body)
end)
bench("render 3 fields + mirror", 2000, function()
  render.render(compiled)
end)
local definitions = {}
for i = 1, 2000 do
  definitions[i] = { trigger = "trigger" .. i, body = "${1:value}$0", auto = i % 2 == 0 }
end
registry.add("lua", definitions)
local ctx = { filetype = "lua", before = "nomatch", cache = {} }
bench("literal auto no-match / 2000 definitions", 3000, function()
  registry.find(ctx, true)
end)
ctx.before = "trigger2000"
bench("literal auto match / 2000 definitions", 3000, function()
  registry.find(ctx, true)
end)
bench("has_auto / 2000 definitions", 3000, function()
  registry.has_auto("lua")
end)
print("Microbenchmarks only; run tests/tui.py for real input correctness.")
