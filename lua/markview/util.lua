local M = {}

---@param fn function
---@param ms number  delay in milliseconds
---@return function
function M.debounce(fn, ms)
  local timer = vim.uv.new_timer()
  return function(...)
    local args = { ... }
    timer:stop()
    timer:start(ms, 0, vim.schedule_wrap(function()
      fn(unpack(args))
    end))
  end
end

---@param start_port number
---@return number|nil
function M.find_free_port(start_port)
  for port = start_port, start_port + 100 do
    local tcp = vim.uv.new_tcp()
    local ok = pcall(function()
      tcp:bind("127.0.0.1", port)
    end)
    tcp:close()
    if ok then
      return port
    end
  end
  return nil
end

return M
