-- Semantic fixtures shared by both engines. No engine-specific definition files.
local M = {}
function M.table_text(rows, cols)
  local lines, index = {}, 0
  local function row(separator)
    local cells = {}
    for col = 1, cols do
      if separator then
        cells[col] = "-"
      else
        index = index + 1
        cells[col] = tostring(index)
      end
    end
    lines[#lines + 1] = "| " .. table.concat(cells, " | ") .. " |"
  end
  row(false)
  row(true)
  for _ = 2, rows do
    row(false)
  end
  lines[#lines + 1] = ""
  return lines
end
function M.native(kind, count)
  local s = require("snippet_tools")
  if kind == "choice" then
    return { s.c(1, { "red", "blue" }), s.i(0) }
  end
  if kind == "mirror" then
    local result = { s.i(1, "field") }
    for _ = 1, count or 10 do
      result[#result + 1] = s.t("/")
      result[#result + 1] = s.rep(1)
    end
    result[#result + 1] = s.i(0)
    return result
  end
  if kind == "table" then
    return {
      s.d(1, function()
        local result, index = {}, 0
        local function row(separator)
          result[#result + 1] = s.t("| ")
          for col = 1, count do
            if separator then
              result[#result + 1] = s.t("-")
            else
              index = index + 1
              result[#result + 1] = s.i(index, tostring(index))
            end
            if col < count then
              result[#result + 1] = s.t(" | ")
            end
          end
          result[#result + 1] = s.t(" |\n")
        end
        row(false)
        row(true)
        for _ = 2, count do
          row(false)
        end
        return result
      end),
      s.i(0),
    }
  end
  return { s.t("<"), s.i(1, "field"), s.t(">"), s.i(0) }
end
function M.luasnip(kind, count)
  local s = require("luasnip")
  local result
  if kind == "choice" then
    result = {
      s.choice_node(1, {
        s.snippet_node(nil, { s.insert_node(1, "red") }),
        s.snippet_node(nil, { s.insert_node(1, "blue") }),
      }),
      s.insert_node(0),
    }
  elseif kind == "mirror" then
    result = { s.insert_node(1, "field") }
    for _ = 1, count or 10 do
      result[#result + 1] = s.text_node("/")
      result[#result + 1] = s.function_node(function(args)
        return args[1]
      end, { 1 })
    end
    result[#result + 1] = s.insert_node(0)
  elseif kind == "table" then
    result = {
      s.dynamic_node(1, function()
        local children, index = {}, 0
        local function row(separator)
          children[#children + 1] = s.text_node("| ")
          for col = 1, count do
            if separator then
              children[#children + 1] = s.text_node("-")
            else
              index = index + 1
              children[#children + 1] = s.insert_node(index, tostring(index))
            end
            if col < count then
              children[#children + 1] = s.text_node(" | ")
            end
          end
          children[#children + 1] = s.text_node({ " |", "" })
        end
        row(false)
        row(true)
        for _ = 2, count do
          row(false)
        end
        return s.snippet_node(nil, children)
      end, {}),
      s.insert_node(0),
    }
  else
    result = { s.text_node("<"), s.insert_node(1, "field"), s.text_node(">"), s.insert_node(0) }
  end
  return s.snippet("bench", result)
end
function M.collection(engine, size, pattern)
  local defs = {}
  if engine == "snippet-tools" then
    local s = require("snippet_tools")
    for i = 1, size do
      defs[i] = {
        trigger = pattern and ("rx" .. i .. "_(%d+) ") or ("snippet" .. i),
        pattern = pattern,
        auto = true,
        word = false,
        body = { s.t("<"), s.i(1), s.t(">"), s.i(0) },
      }
    end
    s.add("bench", defs)
  else
    local s = require("luasnip")
    for i = 1, size do
      defs[i] = s.snippet({
        trig = pattern and ("rx" .. i .. "_(%d+) ") or ("snippet" .. i),
        regTrig = pattern,
        wordTrig = false,
        snippetType = "autosnippet",
      }, { s.text_node("<"), s.insert_node(1), s.text_node(">"), s.insert_node(0) })
    end
    s.add_snippets("bench", defs, { type = "autosnippets" })
  end
end
return M
