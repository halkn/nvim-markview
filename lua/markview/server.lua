local parser = require("markview.parser")
local template = require("markview.template")

local M = {}

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
---@return { push: fun(markdown: string), stop: fun() }
function M.start(bufnr, port, config)
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
          local body_html = parser.render(md)
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
    local body_html = parser.render(markdown)
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

  return { push = push, stop = stop }
end

return M
