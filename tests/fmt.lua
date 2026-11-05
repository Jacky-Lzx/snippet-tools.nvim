local s = require("snippet_tools")
assert(not package.loaded["snippet_tools.fmt"], "Formatter should load only on first use")
local render = require("snippet_tools.render").render
local count = 0
local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
  count = count + 1
end
local function text(nodes)
  return render(nodes).text
end
local function bad(template, args, opts, message)
  local ok, err = pcall(s.fmt, template, args, opts)
  assert(not ok and tostring(err):find(message, 1, true), tostring(err))
  count = count + 1
end

eq("hello name!", text(s.fmt("hello {}!", s.i(1, "name"))))
local single = s.i(1, "single")
eq({ single }, s.fmt("{}", single))
eq("A C D N A", text(s.fmt("{} {3} {} {name} {1}", { "A", "B", "C", "D", name = "N" }, { strict = false })))
eq("N A", text(s.fmt("{name} {}", { "A", name = "N" })))
eq("kind / value", text(s.fmt("{kind} / {value}", { kind = s.i(1, "kind"), value = s.i(2, "value") })))
eq("text", text(s.fmt("{kind}", { kind = "text" })))
eq("variable", text(s.fmt("{kind}", { kind = "variable" })))
eq("fallback", text(s.fmt("{}", require("snippet_tools.parser").parse("${MISSING:fallback}")[1])))
eq("{name}", text(s.fmt("{{{}}}", s.i(1, "name"))))
eq("<name>", text(s.fmta("<<<>>>", s.i(1, "name"))))
eq("[value]", text(s.fmt("[[[]]]", { "value" }, { delimiters = "[]" })))
eq("value", text(s.fmta("[]", { "value" }, { delimiters = "[]" })))
for _, delimiters in ipairs({ "()", "%$", "^]", "-?", [[\/]] }) do
  eq("value", text(s.fmt(delimiters, { "value" }, { delimiters = delimiters })))
end
eq("$1 ${2:literal} \\alpha", text(s.fmt("$1 {} \\alpha", { "${2:literal}" })))
eq("left/right", text(s.fmt("{}", { { s.i(1, "left"), s.t("/"), s.i(2, "right") } })))
eq("one one", text(s.fmt("{name} {name}", { name = s.i(1, "one") })))
eq("", text(s.fmt("")))
eq("", text(s.fmt("\n \t\n\n")))
eq("\n \t\n", text(s.fmt("{}", { "\n \t\n" })))
eq("a\n  b", text(s.fmt("\n\n    a\n      b\n  \n")))
eq("\n    a\n", text(s.fmt("\n    a\n", nil, { trim_empty = false, dedent = false })))
eq("    a", text(s.fmt("\n    a\n", nil, { dedent = false })))
eq("\na\n", text(s.fmt("\n    a\n", nil, { trim_empty = false })))
eq("a\n\tb", text(s.fmt("    a\n      b", nil, { indent_string = "  " })))
eq("a\n\t\tb", text(s.fmt("a\n\\t\\tb", nil, { indent_string = [[\t]] })))
eq(
  "\\begin{table}\n  body\n\\end{table}",
  text(s.fmta(
    [[
    \begin{<env>}
      <body>
    \end{<env>}
  ]],
    { env = s.i(1, "table"), body = s.i(0, "body") }
  ))
)
eq(
  "one/one!",
  text(s.fmt("{source}/{computed}", {
    source = s.i(1, "one"),
    computed = s.f(function(a)
      return a[1] .. "!"
    end, { 1 }),
  }))
)
local args = { name = s.i(1, "old") }
local opts = { strict = true }
local before = vim.deepcopy(args)
local formatted = s.fmt("{name}/{name}", args, opts)
eq(before, args)
eq({ strict = true }, opts)
eq("old/old", text(formatted))
local mirrors = 0
for _, record in ipairs(render(formatted).records) do
  if record.kind == "mirror" then
    mirrors = mirrors + 1
  end
end
eq(1, mirrors)
eq("old", text(s.fmt("{name}", args)))

bad("{}", {}, nil, "missing argument 1")
bad("{name}", {}, nil, "missing argument name")
bad("text", { s.i(1) }, nil, "unused argument 1")
eq("text", text(s.fmt("text", { s.i(1) }, { strict = false })))
bad("{", {}, nil, "missing closing delimiter")
bad("}", {}, nil, "unescaped closing delimiter")
bad("{a{b}", {}, nil, "nested placeholder")
bad("{0}", { [0] = s.i(0) }, nil, "positive integers")
bad("{-1}", {}, nil, "positive integers")
bad("{1.5}", {}, nil, "positive integers")
bad("", {}, { delimiters = "{{" }, "two distinct ASCII")
bad("", {}, { delimiters = "abc" }, "two distinct ASCII")
bad("", {}, { delimiters = "é" }, "two distinct ASCII")
bad("", {}, { dedent = "yes" }, "invalid option dedent")
bad("", {}, { trim_empty = 1 }, "invalid option trim_empty")
bad("", {}, { indent_string = "\n" }, "must not contain a newline")
bad("", {}, { unknown = true }, "unknown option unknown")
bad(1, {}, nil, "template must be a string")
bad("", "wrong", nil, "arguments must be a node or table")
bad("", {}, false, "options must be a table")
assert(not package.loaded.luasnip, "Native formatting must not load LuaSnip")
print("fmt: " .. count .. " assertions passed")
