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
print("core: " .. count .. " assertions passed")
