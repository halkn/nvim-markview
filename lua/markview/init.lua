local util = require("markview.util")
local server = require("markview.server")

local M = {}

---@type table<number, { srv: table, port: number, augroup: string }>
local state = {}

local default_config = {
  port = 8765,
  auto_open = false,
  debounce_ms = 200,
  browser = nil,
  theme = "auto",
  keymaps = {
    toggle = "<leader>mp",
  },
}

---@type table
local config = vim.deepcopy(default_config)

local function detect_browser()
  if config.browser then
    return config.browser
  end
  local uname = vim.loop.os_uname()
  local sysname = uname and uname.sysname or ""
  if sysname == "Darwin" then
    return "open"
  elseif sysname:find("Windows") then
    return "cmd /c start"
  else
    -- Linux / WSL
    return "xdg-open"
  end
end

local function open_browser(url)
  local browser = detect_browser()
  local cmd
  if browser == "cmd /c start" then
    cmd = { "cmd", "/c", "start", url }
  else
    cmd = vim.split(browser, "%s+")
    table.insert(cmd, url)
  end
  vim.fn.jobstart(cmd, { detach = true })
end

---@param bufnr number
function M.open(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if state[bufnr] then
    vim.notify("[markview] Already open for buffer " .. bufnr, vim.log.levels.INFO)
    return
  end

  local port = util.find_free_port(config.port)
  if not port then
    vim.notify("[markview] No free port found", vim.log.levels.ERROR)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local base_dir = (filepath and filepath ~= "") and vim.fn.fnamemodify(filepath, ":h") or nil

  local srv = server.start(bufnr, port, config, base_dir)
  local augroup = "markview_buf_" .. bufnr

  state[bufnr] = { srv = srv, port = port, augroup = augroup }

  -- Initial push
  local md = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  srv.push(md)

  local debounced_push = util.debounce(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    srv.push(content)
  end, config.debounce_ms)

  vim.api.nvim_create_augroup(augroup, { clear = true })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = bufnr,
    callback = debounced_push,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      M.close(bufnr)
    end,
  })

  local url = "http://127.0.0.1:" .. port
  vim.notify("[markview] Opening preview at " .. url, vim.log.levels.INFO)

  -- Small delay to let the server start accepting connections
  vim.defer_fn(function()
    open_browser(url)
  end, 100)
end

---@param bufnr number|nil
function M.close(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local s = state[bufnr]
  if not s then
    vim.notify("[markview] Not open for buffer " .. bufnr, vim.log.levels.INFO)
    return
  end

  s.srv.stop()
  pcall(vim.api.nvim_del_augroup_by_name, s.augroup)
  state[bufnr] = nil

  vim.notify("[markview] Preview closed", vim.log.levels.INFO)
end

---@param bufnr number|nil
function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if state[bufnr] then
    M.close(bufnr)
  else
    M.open(bufnr)
  end
end

---@param opts table|nil
function M.setup(opts)
  config = vim.tbl_deep_extend("force", default_config, opts or {})

  if config.auto_open then
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "markdown",
      callback = function(ev)
        M.open(ev.buf)
      end,
    })
  end

  if config.keymaps and config.keymaps.toggle then
    vim.keymap.set("n", config.keymaps.toggle, function()
      M.toggle()
    end, { desc = "Toggle Markview preview" })
  end
end

return M
