local parser = require("markview.parser")
local template = require("markview.template")

local M = {}

local MIME_TYPES = {
  png  = "image/png",
  jpg  = "image/jpeg",
  jpeg = "image/jpeg",
  gif  = "image/gif",
  svg  = "image/svg+xml",
  webp = "image/webp",
  ico  = "image/x-icon",
  bmp  = "image/bmp",
}

local function get_mime_type(path)
  local ext = path:match("%.([^%.]+)$")
  if ext then
    return MIME_TYPES[ext:lower()] or "application/octet-stream"
  end
  return "application/octet-stream"
end

local function make_http_response(status, headers, body)
  local lines = { "HTTP/1.1 " .. status }
  for k, v in pairs(headers) do
    table.insert(lines, k .. ": " .. v)
  end
  table.insert(lines, "")
  table.insert(lines, body)
  return table.concat(lines, "\r\n")
end

local function parse_request_line(data)
  local method, path = data:match("^(%u+)%s+([^%s]+)")
  return method, path
end

---@param bufnr number
---@param port number
---@param config table
---@param base_dir string|nil  Directory of the Markdown file (for serving relative images)
---@return { push: fun(markdown: string), scroll_to: fun(cursor_line: number, total_lines: number), stop: fun() }
function M.start(bufnr, port, config, base_dir)
  local clients = {} -- SSE client handles
  local current_html = ""

  local tcp_server = vim.uv.new_tcp()
  tcp_server:bind("127.0.0.1", port)
  tcp_server:listen(128, function(err)
    if err then
      vim.schedule(function()
        vim.notify("[markview] server listen error: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    local client = vim.uv.new_tcp()
    tcp_server:accept(client)

    -- Read the request
    local request_data = {}
    client:read_start(function(read_err, chunk)
      if read_err or not chunk then
        -- Connection closed or error before we could read
        if not read_err then
          -- EOF
        end
        return
      end

      table.insert(request_data, chunk)
      local full = table.concat(request_data)

      -- Wait for end of HTTP headers
      if not full:find("\r\n\r\n") then
        return
      end

      client:read_stop()

      local method, path = parse_request_line(full)

      if path == "/" and method == "GET" then
        -- Serve the full page
        vim.schedule(function()
          local md = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
          local body_html = parser.render(md, base_dir)
          current_html = body_html
          local page = template.full_page(body_html, config)
          local response = make_http_response("200 OK", {
            ["Content-Type"] = "text/html; charset=UTF-8",
            ["Content-Length"] = tostring(#page),
            ["Connection"] = "close",
            ["Cache-Control"] = "no-cache",
          }, page)
          client:write(response, function()
            client:shutdown(function()
              client:close()
            end)
          end)
        end)

      elseif path == "/events" and method == "GET" then
        -- SSE endpoint: keep connection alive
        local sse_headers = table.concat({
          "HTTP/1.1 200 OK",
          "Content-Type: text/event-stream",
          "Cache-Control: no-cache",
          "Connection: keep-alive",
          "Access-Control-Allow-Origin: *",
          "",
          "",
        }, "\r\n")
        client:write(sse_headers)

        -- Send current content immediately
        if current_html ~= "" then
          local escaped = current_html:gsub("\n", "\\n")
          client:write("data: " .. escaped .. "\n\n")
        end

        table.insert(clients, client)

        -- Handle client disconnect
        client:read_start(function(_, _)
          -- Client disconnected or sent something
          -- Remove from clients list
          for idx, c in ipairs(clients) do
            if c == client then
              table.remove(clients, idx)
              break
            end
          end
          if not client:is_closing() then
            client:close()
          end
        end)

      elseif method == "GET" and path:match("^/images/") then
        -- Serve a local image file relative to base_dir
        local rel = path:match("^/images/(.+)$")
        -- Decode percent-encoded characters (e.g. %20 -> space)
        rel = rel and rel:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        local served = false
        if base_dir and rel and not rel:match("%.%.") then
          local full_path = base_dir .. "/" .. rel
          local fd = vim.uv.fs_open(full_path, "r", 438)
          if fd then
            local stat = vim.uv.fs_fstat(fd)
            if stat then
              local data = vim.uv.fs_read(fd, stat.size, 0)
              vim.uv.fs_close(fd)
              if data then
                local mime = get_mime_type(rel)
                local response = make_http_response("200 OK", {
                  ["Content-Type"] = mime,
                  ["Content-Length"] = tostring(#data),
                  ["Connection"] = "close",
                  ["Cache-Control"] = "no-cache",
                }, data)
                client:write(response, function()
                  client:shutdown(function()
                    client:close()
                  end)
                end)
                served = true
              end
            else
              vim.uv.fs_close(fd)
            end
          end
        end
        if not served then
          local body = "Not Found"
          local response = make_http_response("404 Not Found", {
            ["Content-Type"] = "text/plain",
            ["Content-Length"] = tostring(#body),
            ["Connection"] = "close",
          }, body)
          client:write(response, function()
            client:shutdown(function()
              client:close()
            end)
          end)
        end

      else
        -- 404
        local body = "Not Found"
        local response = make_http_response("404 Not Found", {
          ["Content-Type"] = "text/plain",
          ["Content-Length"] = tostring(#body),
          ["Connection"] = "close",
        }, body)
        client:write(response, function()
          client:shutdown(function()
            client:close()
          end)
        end)
      end
    end)
  end)

  local function push(markdown)
    local body_html = parser.render(markdown, base_dir)
    current_html = body_html
    local escaped = body_html:gsub("\n", "\\n")
    local payload = "data: " .. escaped .. "\n\n"

    -- Write to all SSE clients, remove dead ones
    local alive = {}
    for _, c in ipairs(clients) do
      if not c:is_closing() then
        c:write(payload, function(write_err)
          if write_err then
            if not c:is_closing() then
              c:close()
            end
          end
        end)
        table.insert(alive, c)
      end
    end
    clients = alive
  end

  local function scroll_to(cursor_line, total_lines)
    local ratio = cursor_line / math.max(total_lines, 1)
    local payload = "event: scroll\ndata: " .. string.format("%.6f", ratio) .. "\n\n"
    local alive = {}
    for _, c in ipairs(clients) do
      if not c:is_closing() then
        c:write(payload, function(write_err)
          if write_err then
            if not c:is_closing() then
              c:close()
            end
          end
        end)
        table.insert(alive, c)
      end
    end
    clients = alive
  end

  local function stop()
    -- Close all SSE clients
    for _, c in ipairs(clients) do
      if not c:is_closing() then
        c:close()
      end
    end
    clients = {}
    if not tcp_server:is_closing() then
      tcp_server:close()
    end
  end

  return { push = push, scroll_to = scroll_to, stop = stop }
end

return M
