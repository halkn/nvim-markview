local M = {}

local function escape_html(s)
  s = s:gsub("&", "&amp;")
  s = s:gsub("<", "&lt;")
  s = s:gsub(">", "&gt;")
  s = s:gsub('"', "&quot;")
  return s
end

-- Generate URL-friendly anchor id from heading text
local function slugify(text)
  text = text:gsub("<[^>]+>", "") -- strip HTML tags
  text = text:lower()
  text = text:gsub("[^%w%s%-]", "")
  text = text:gsub("%s+", "-")
  text = text:gsub("%-+", "-")
  text = text:gsub("^%-+", ""):gsub("%-+$", "")
  return text
end

local function apply_inline(s)
  -- Images before links
  s = s:gsub("!%[(.-)%]%((.-)%)", function(alt, src)
    return '<img src="' .. src .. '" alt="' .. escape_html(alt) .. '">'
  end)
  -- Links
  s = s:gsub("%[(.-)%]%((.-)%)", function(text, href)
    return '<a href="' .. href .. '">' .. text .. "</a>"
  end)
  -- Bold (**text** or __text__)
  s = s:gsub("%*%*(.-)%*%*", "<strong>%1</strong>")
  s = s:gsub("__(.-)__", "<strong>%1</strong>")
  -- Italic (*text* or _text_)
  s = s:gsub("%*(.-)%*", "<em>%1</em>")
  s = s:gsub("_(.-)_", "<em>%1</em>")
  -- Inline code
  s = s:gsub("`(.-)`", function(code)
    return "<code>" .. escape_html(code) .. "</code>"
  end)
  -- Strikethrough
  s = s:gsub("~~(.-)~~", "<del>%1</del>")
  return s
end

-- Parse a GFM table and return HTML string, or nil if not a table
local function parse_table(lines, i)
  local header_line = lines[i]
  local sep_line = lines[i + 1]
  if not sep_line then
    return nil, i
  end
  -- Separator must match: | :---: | --- | etc.
  if not sep_line:match("^|?%s*:?%-+:?%s*|") then
    return nil, i
  end

  -- Parse alignments from separator
  local alignments = {}
  for cell in sep_line:gmatch("[^|]+") do
    cell = cell:match("^%s*(.-)%s*$")
    if cell:match("^:.*:$") then
      table.insert(alignments, "center")
    elseif cell:match(":$") then
      table.insert(alignments, "right")
    else
      table.insert(alignments, "left")
    end
  end

  local function parse_row(line)
    local cells = {}
    line = line:match("^|?(.-)%s*|?$")
    for cell in (line .. "|"):gmatch("(.-)|") do
      table.insert(cells, cell:match("^%s*(.-)%s*$"))
    end
    return cells
  end

  local html = { "<table>\n<thead>\n<tr>" }
  local headers = parse_row(header_line)
  for j, cell in ipairs(headers) do
    local align = alignments[j] or "left"
    table.insert(html, '<th align="' .. align .. '">' .. apply_inline(escape_html(cell)) .. "</th>")
  end
  table.insert(html, "</tr>\n</thead>\n<tbody>")

  local j = i + 2
  while j <= #lines and lines[j]:match("^|") do
    local cells = parse_row(lines[j])
    table.insert(html, "<tr>")
    for k, cell in ipairs(cells) do
      local align = alignments[k] or "left"
      table.insert(html, '<td align="' .. align .. '">' .. apply_inline(escape_html(cell)) .. "</td>")
    end
    table.insert(html, "</tr>")
    j = j + 1
  end

  table.insert(html, "</tbody>\n</table>")
  return table.concat(html, "\n"), j - 1
end

---@param markdown string
---@return string
function M.render(markdown)
  local lines = vim.split(markdown, "\n")
  local html = {}
  local i = 1
  local in_code_block = false
  local code_lang = ""
  local code_lines = {}
  local in_list = false
  local list_ordered = false
  local in_para = false
  local para_lines = {}
  local in_blockquote = false
  local bq_lines = {}

  local function flush_para()
    if #para_lines > 0 then
      local parts = {}
      for j, pline in ipairs(para_lines) do
        -- Hard line breaks: trailing two spaces or backslash
        local has_break = pline:match("  $") or pline:match("\\$")
        local clean = pline:gsub("  $", ""):gsub("\\$", "")
        local escaped = apply_inline(escape_html(clean))
        if has_break and j < #para_lines then
          table.insert(parts, escaped .. "<br>")
        else
          table.insert(parts, escaped)
        end
      end
      table.insert(html, "<p>" .. table.concat(parts, " ") .. "</p>")
      para_lines = {}
      in_para = false
    end
  end

  local function flush_list()
    if in_list then
      if list_ordered then
        table.insert(html, "</ol>")
      else
        table.insert(html, "</ul>")
      end
      in_list = false
    end
  end

  local function flush_blockquote()
    if in_blockquote and #bq_lines > 0 then
      local first_line = bq_lines[1]
      -- Azure DevOps style admonitions: > [!NOTE], > [!WARNING], etc.
      local admonition_type = first_line:match("^%[!(%u+)%]%s*$")
      if admonition_type then
        local content_lines = {}
        for j = 2, #bq_lines do
          table.insert(content_lines, bq_lines[j])
        end
        local inner = M.render(table.concat(content_lines, "\n"))
        local atype = admonition_type:lower()
        -- Title-case: "NOTE" -> "Note"
        local title = admonition_type:sub(1, 1):upper() .. admonition_type:sub(2):lower()
        table.insert(html,
          '<div class="admonition ' .. atype .. '">\n' ..
          '<p class="admonition-title">' .. title .. '</p>\n' ..
          inner .. '\n</div>')
      else
        local inner = M.render(table.concat(bq_lines, "\n"))
        table.insert(html, "<blockquote>\n" .. inner .. "\n</blockquote>")
      end
      bq_lines = {}
      in_blockquote = false
    end
  end

  while i <= #lines do
    local line = lines[i]

    -- Fenced code block handling
    if line:match("^```") then
      if in_code_block then
        -- End code block
        if code_lang == "mermaid" then
          -- Mermaid diagram: render as div for mermaid.js
          table.insert(html, '<div class="mermaid">\n' .. table.concat(code_lines, "\n") .. '\n</div>')
        else
          local escaped = escape_html(table.concat(code_lines, "\n"))
          local lang_attr = code_lang ~= "" and (' class="language-' .. code_lang .. '"') or ""
          table.insert(html, "<pre><code" .. lang_attr .. ">" .. escaped .. "</code></pre>")
        end
        code_lines = {}
        code_lang = ""
        in_code_block = false
      else
        -- Start code block
        flush_para()
        flush_list()
        flush_blockquote()
        in_code_block = true
        code_lang = line:match("^```(.*)$") or ""
        code_lang = code_lang:match("^%s*(.-)%s*$")
      end
      i = i + 1
      goto continue
    end

    if in_code_block then
      table.insert(code_lines, line)
      i = i + 1
      goto continue
    end

    -- Blockquote
    if line:match("^>") then
      flush_para()
      flush_list()
      in_blockquote = true
      local bq_content = line:match("^>%s?(.*)$") or ""
      table.insert(bq_lines, bq_content)
      i = i + 1
      goto continue
    elseif in_blockquote then
      flush_blockquote()
    end

    -- ATX Headings
    local heading_level, heading_text = line:match("^(#{1,6})%s+(.*)")
    if heading_level then
      flush_para()
      flush_list()
      local level = #heading_level
      local rendered = apply_inline(escape_html(heading_text))
      local slug = slugify(heading_text)
      table.insert(html, '<h' .. level .. ' id="' .. slug .. '">' .. rendered .. '</h' .. level .. '>')
      i = i + 1
      goto continue
    end

    -- Horizontal rule
    if line:match("^%-%-%-+%s*$") or line:match("^%*%*%*+%s*$") or line:match("^___+%s*$") then
      flush_para()
      flush_list()
      table.insert(html, "<hr>")
      i = i + 1
      goto continue
    end

    -- GFM Table (check if next line is a separator)
    if line:match("^|") and lines[i + 1] and lines[i + 1]:match("^|?%s*:?%-") then
      flush_para()
      flush_list()
      local table_html, new_i = parse_table(lines, i)
      if table_html then
        table.insert(html, table_html)
        i = new_i + 1
        goto continue
      end
    end

    -- Unordered list
    local ul_item = line:match("^%s*[-*+]%s+(.*)")
    if ul_item then
      flush_para()
      if in_list and list_ordered then
        flush_list()
      end
      if not in_list then
        table.insert(html, "<ul>")
        in_list = true
        list_ordered = false
      end
      -- Task list items: - [x] / - [X] (checked), - [ ] (unchecked)
      local checked = ul_item:match("^%[[xX]%]%s*(.*)")
      local unchecked = ul_item:match("^%[ %]%s*(.*)")
      if checked then
        table.insert(html,
          '<li class="task-list-item"><input type="checkbox" checked disabled> ' ..
          apply_inline(escape_html(checked)) .. '</li>')
      elseif unchecked then
        table.insert(html,
          '<li class="task-list-item"><input type="checkbox" disabled> ' ..
          apply_inline(escape_html(unchecked)) .. '</li>')
      else
        table.insert(html, "<li>" .. apply_inline(escape_html(ul_item)) .. "</li>")
      end
      i = i + 1
      goto continue
    end

    -- Ordered list
    local ol_item = line:match("^%s*%d+%.%s+(.*)")
    if ol_item then
      flush_para()
      if in_list and not list_ordered then
        flush_list()
      end
      if not in_list then
        table.insert(html, "<ol>")
        in_list = true
        list_ordered = true
      end
      table.insert(html, "<li>" .. apply_inline(escape_html(ol_item)) .. "</li>")
      i = i + 1
      goto continue
    end

    -- Empty line
    if line:match("^%s*$") then
      flush_para()
      flush_list()
      i = i + 1
      goto continue
    end

    -- Paragraph
    flush_list()
    in_para = true
    table.insert(para_lines, line)
    i = i + 1

    ::continue::
  end

  -- Flush remaining state
  flush_para()
  flush_list()
  flush_blockquote()
  if in_code_block and #code_lines > 0 then
    local escaped = escape_html(table.concat(code_lines, "\n"))
    table.insert(html, "<pre><code>" .. escaped .. "</code></pre>")
  end

  return table.concat(html, "\n")
end

return M
