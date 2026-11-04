local s = require("snippet_tools")
return {
  {
    trigger = "table(%d+)x(%d+) ",
    pattern = true,
    auto = true,
    hidden = true,
    description = "Generate a Markdown table (rows include the header)",
    condition = function(_, match)
      return match.start_col == 0
    end,
    body = {
      s.d(1, function(_, ctx)
        local rows = math.min(32, math.max(1, tonumber(ctx.match.captures[1])))
        local columns = math.min(32, math.max(1, tonumber(ctx.match.captures[2])))
        local result, index = {}, 0
        for row = 1, rows do
          result[#result + 1] = s.t("| ")
          for _ = 1, columns do
            index = index + 1
            result[#result + 1] = s.i(index, row == 1 and "Heading" or "")
            result[#result + 1] = s.t(" | ")
          end
          result[#result + 1] = s.t("\n")
          if row == 1 then
            result[#result + 1] = s.t("|" .. string.rep(" --- |", columns) .. "\n")
          end
        end
        return result
      end),
      s.i(0),
    },
  },
}
