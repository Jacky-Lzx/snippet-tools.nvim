-- Public LSP syntax only; no dependency on Neovim's private snippet parser.
local nodes = require("snippet_tools.nodes")
local M = {}
local cache, size = {}, 0

function M.parse(source)
  assert(type(source) == "string", "snippet-tools: snippet body must be a string")
  if cache[source] then
    return cache[source]
  end
  local at = 1
  local function fail(message)
    error(("snippet-tools: %s at byte %d"):format(message, at), 0)
  end
  local sequence
  sequence = function(nested, depth)
    if depth > 64 then
      fail("snippet nesting exceeds 64 levels")
    end
    local result, text = {}, {}
    local function flush()
      if #text > 0 then
        result[#result + 1] = nodes.text(table.concat(text))
        text = {}
      end
    end
    while at <= #source do
      local char = source:sub(at, at)
      if char == "}" and nested then
        break
      elseif char == "\\" and source:sub(at + 1, at + 1):match("[\\$}]") then
        text[#text + 1] = source:sub(at + 1, at + 1)
        at = at + 2
      elseif char == "$" then
        local braced = source:sub(at + 1, at + 1) == "{"
        local start = at + (braced and 2 or 1)
        local token = source:sub(start):match("^%d+") or source:sub(start):match("^[%a_][%w_]*")
        if not token then
          if braced then
            fail("expected placeholder or variable")
          end
          text[#text + 1], at = "$", at + 1
        else
          flush()
          at = start + #token
          local number = tonumber(token)
          local node = number and nodes.insert(number) or { kind = "variable", name = token }
          if braced then
            local sep = source:sub(at, at)
            if sep == ":" then
              at = at + 1
              node.children = sequence(true, depth + 1)
            elseif sep == "|" and number then
              at = at + 1
              local choices, part = {}, {}
              while at <= #source do
                local c = source:sub(at, at)
                if c == "|" and source:sub(at + 1, at + 1) == "}" then
                  choices[#choices + 1] = table.concat(part)
                  at = at + 1
                  break
                elseif c == "," then
                  choices[#choices + 1], part = table.concat(part), {}
                elseif c == "\\" and source:sub(at + 1, at + 1):match("[\\,|]") then
                  at = at + 1
                  part[#part + 1] = source:sub(at, at)
                else
                  part[#part + 1] = c
                end
                at = at + 1
              end
              node = nodes.choice(number, choices)
            elseif sep == "/" then
              fail("ECMAScript transformations are unsupported; use a Lua function node")
            elseif sep ~= "}" then
              fail("expected ':', '|', or '}'")
            end
            if source:sub(at, at) ~= "}" then
              fail("unterminated placeholder")
            end
            at = at + 1
          end
          result[#result + 1] = node
        end
      else
        text[#text + 1], at = char, at + 1
      end
    end
    flush()
    return result
  end
  local result = sequence(false, 0)
  -- Bound memory when servers generate a distinct snippet for each response.
  if size >= 256 then
    cache, size = {}, 0
  end
  cache[source], size = result, size + 1
  return result
end

return M
