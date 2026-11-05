local p = require("snippet_tools.parser")
local r = require("snippet_tools.render")
local n = require("snippet_tools.nodes")
local count = 0
local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
  count = count + 1
end
local function render(s)
  return r.render(p.parse(s))
end
eq("hello world / world", render("hello ${1:world} / $1$0").text)
eq("name name", render("$1 ${1:name}").text)
eq("outer inner / inner", render("${1:outer ${2:inner}} / $2").text)
eq("$1 } \\alpha", render("\\$1 \\} \\alpha").text)
eq("one,two", render("${1|one\\,two,three|}").text)
eq("fallback", render("${UNKNOWN:fallback}").text)
eq("UNKNOWN", render("$UNKNOWN").text)
eq(true, render("$UNKNOWN").groups["root/1"] ~= nil)
eq("default", r.render(p.parse("${NAME:default}"), { variables = { NAME = "" } }).text)
eq(true, render("${UNKNOWN:${1:inner}}").groups["root/1"] ~= nil)
eq("inner-inner", render("$1-${UNKNOWN:${1:inner}}").text)
eq("value", r.render(p.parse("$NAME"), { variables = { NAME = "value" } }).text)
eq(false, pcall(p.parse, "${1:unfinished"))
eq(false, pcall(p.parse, "${1/a/b/}"))
eq(false, pcall(render, "${1:$1}"))
local body = {
  n.insert(1, "49"),
  n.text(" / "),
  n.func(function(a)
    return tostring(98 - tonumber(a[1]))
  end, { 1 }),
  n.choice(2, { "text", { n.text("["), n.insert(1, "nested"), n.text("]") } }),
  n.dynamic(3, function(a)
    return { n.insert(1, a[1] .. " generated") }
  end, { 1 }),
}
local result = r.render(body)
eq("49 / 49text49 generated", result.text)
eq(true, result.groups["root/3@dynamic/1"] ~= nil)
eq("49 / 49[nested]49 generated", r.render(body, { choices = { ["root/2"] = 2 } }).text)
eq(
  "[inner]=[inner]",
  r.render({ n.mirror(1), n.text("="), n.choice(1, { { n.text("["), n.insert(1, "inner"), n.text("]") } }) }).text
)
eq(
  "child=child",
  r.render({ n.mirror(1), n.text("="), n.dynamic(1, function()
    return n.insert(1, "child")
  end) }).text
)
-- Direct/LSP expansion must work on an empty line, before typing a trigger.
local variables = require("snippet_tools.variables")
eq("", variables.snapshot().TM_CURRENT_WORD)
local engine = require("snippet_tools")
engine.setup({ keymap = false })
eq(true, engine.expand("${TM_CURRENT_WORD:fallback}"))
eq("fallback", vim.api.nvim_get_current_line())
engine.stop()
vim.api.nvim_win_set_cursor(0, { 1, 0 })
eq("fallback", variables.snapshot().TM_CURRENT_WORD)
eq("override", variables.snapshot({ variables = { TM_CURRENT_WORD = "override" } }).TM_CURRENT_WORD)
print("core: " .. count .. " assertions passed")
