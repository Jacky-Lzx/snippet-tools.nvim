local r = require("snippet_tools.registry")
local count = 0
local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
  count = count + 1
end
local function ctx(before, ft)
  return { before = before, filetype = ft or "lua", cache = {} }
end
r.add("all", { { trigger = "todo", body = "TODO: $0" } })
r.add("lua", {
  { trigger = "fn", body = "function $0 end" },
  { trigger = "table(%d+)x(%d+) ", pattern = true, auto = true, body = "$0" },
  { trigger = "hidden", body = "$0", hidden = true },
  {
    trigger = "guard",
    body = "$0",
    condition = function()
      return false
    end,
  },
})
eq(3, #r.available(ctx("")))
eq("fn", r.find(ctx("fn"), false).trigger)
eq(nil, r.find(ctx("xfn"), false))
eq(nil, r.find(ctx("guard"), false))
local entry, match = r.find(ctx("table3x4 "), true)
eq("table(%d+)x(%d+) ", entry.trigger)
eq({ "3", "4" }, match.captures)
eq(true, r.has_auto("lua"))
eq(false, r.has_auto("rust"))
r.extend("markdown", { "lua" })
r.extend("lua", { "markdown" }) -- Cycles neither loop nor duplicate definitions.
eq(3, #r.available(ctx("", "markdown")))
r.add("lua", { { trigger = "new", body = "new" } })
eq(false, r.has_auto("markdown"))
eq("new", r.find(ctx("new", "markdown"), false).trigger)
eq(false, pcall(r.add, "lua", { { trigger = "bad", body = "${" } }))
eq(false, pcall(r.add, "lua", { { trigger = "bad", body = "text", auto = "true" } }))
eq(false, pcall(r.add, "lua", { { trigger = "bad", body = "text", priority = math.huge } }))
eq("new", r.find(ctx("new"), false).trigger)
print("registry: " .. count .. " assertions passed")
