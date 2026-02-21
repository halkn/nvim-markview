# CLAUDE.md — nvim-markview

This file provides context for AI assistants working in this codebase.

## Project Overview

**nvim-markview** is a Neovim plugin that renders a live Markdown preview in the user's default web browser. It is implemented entirely in Lua with zero external runtime dependencies, using `vim.uv` (libuv) to run a lightweight HTTP server inside Neovim's event loop.

- **Language:** Lua (Neovim plugin)
- **Runtime:** Neovim 0.10+ (requires `vim.uv`)
- **Dependencies:** None (pure Lua + Neovim standard library)
- **License:** MIT

---

## Repository Structure

```
nvim-markview/
├── plugin/
│   └── markview.lua          # Plugin entry point — registers Neovim user commands
├── lua/
│   └── markview/
│       ├── init.lua          # Public API: setup(), open(), close(), toggle()
│       ├── server.lua        # HTTP/SSE server (vim.uv TCP)
│       ├── parser.lua        # Markdown-to-HTML renderer
│       ├── template.lua      # Full HTML page builder (CSS + JS embedded)
│       └── util.lua          # debounce() and find_free_port() utilities
├── doc/
│   └── markview.txt          # Neovim :help documentation
└── README.md
```

---

## Architecture

### Data Flow

```
[Neovim buffer]
    |
    | TextChanged / TextChangedI autocmd
    v
[util.debounce(200ms)]           -- prevents update storm while typing
    |
    | fn() called after debounce settles
    v
[server.push(markdown)]
    |
    | parser.render(markdown) -> HTML string
    v
[SSE broadcast to all /events clients]
    |
    | "data: <escaped HTML>\n\n"
    v
[Browser EventSource.onmessage]
    |
    | replaces #content innerHTML, restores scroll position
    v
[Live preview updated]
```

### HTTP Server Endpoints

Both endpoints are served by the same `vim.uv` TCP server bound to `127.0.0.1:<port>`:

| Endpoint    | Method | Purpose                                              |
|-------------|--------|------------------------------------------------------|
| `/`         | GET    | Full HTML page (initial page load)                   |
| `/events`   | GET    | SSE stream — pushes rendered HTML on every change    |
| anything else | GET  | 404 Not Found                                        |

The server intentionally listens only on `127.0.0.1` (loopback), never on public interfaces.

---

## Module Responsibilities

### `plugin/markview.lua`
- Plugin guard (`vim.g.loaded_markview`) to prevent double-loading.
- Registers three Neovim user commands: `:MarkviewOpen`, `:MarkviewClose`, `:MarkviewToggle`.
- Does **not** call `setup()` — that is the user's responsibility.

### `lua/markview/init.lua`
The core of the plugin. Manages per-buffer state and orchestrates all subsystems.

**Key internals:**
- `state` table: `table<bufnr, { srv, port, augroup }>` — tracks active previews per buffer.
- `config` table: merged from `default_config` and user-provided options via `vim.tbl_deep_extend`.
- `detect_browser()`: inspects `vim.loop.os_uname().sysname` to pick `open` (macOS), `cmd /c start` (Windows), or `xdg-open` (Linux/WSL).
- `M.open(bufnr)`: starts server, creates autocmds (`TextChanged`, `TextChangedI`, `BufDelete`), does initial push, and opens the browser after a 100ms delay.
- `M.close(bufnr)`: calls `srv.stop()`, removes the augroup, clears state.
- `M.setup(opts)`: merges config, optionally registers a `FileType markdown` autocmd for `auto_open`, and binds the toggle keymap.

### `lua/markview/server.lua`
Implements the HTTP server using `vim.uv.new_tcp()`.

**Key internals:**
- `clients` list: holds open SSE `uv_tcp` handles.
- `current_html`: caches the last rendered HTML so new SSE clients receive it immediately on connect.
- `make_http_response(status, headers, body)`: builds a raw HTTP/1.1 response string.
- `parse_request_line(data)`: extracts method and path from the raw HTTP request bytes.
- `push(markdown)`: renders markdown → HTML, escapes newlines as `\n`, writes `data: ...\n\n` to all live clients, prunes dead handles.
- `stop()`: closes all SSE clients and the TCP server handle.
- All Neovim API calls inside uv callbacks must be wrapped in `vim.schedule()`.

### `lua/markview/parser.lua`
A single-pass, state-machine Markdown renderer. Converts a markdown string to an HTML fragment (no `<html>` wrapper).

**Supported syntax:**

| Element          | Syntax                         |
|------------------|--------------------------------|
| Headings         | `# H1` through `###### H6` (ATX only) |
| Bold             | `**text**` or `__text__`       |
| Italic           | `*text*` or `_text_`           |
| Strikethrough    | `~~text~~`                     |
| Inline code      | `` `code` ``                   |
| Links            | `[text](url)`                  |
| Images           | `![alt](src)`                  |
| Fenced code      | ` ```lang ` / ` ``` `          |
| Unordered list   | `- item`, `* item`, `+ item`   |
| Ordered list     | `1. item`, `2. item`, …        |
| Blockquote       | `> text` (recursive, nested)   |
| GFM table        | pipe-delimited with separator row |
| Horizontal rule  | `---`, `***`, or `___`         |
| Paragraph        | any non-matching line          |

**Key internals:**
- `escape_html(s)`: escapes `& < > "` — always applied to user content before inserting into HTML.
- `apply_inline(s)`: applies all inline patterns. Images are processed before links to avoid conflict.
- `flush_para()`, `flush_list()`, `flush_blockquote()`: state-transition helpers that emit pending HTML and reset state flags.
- `parse_table(lines, i)`: lookahead parser; checks `lines[i+1]` for separator row pattern before committing.
- `M.render(markdown)` calls itself recursively for blockquote inner content.

**Parser ordering (inline patterns applied in this order):**
1. Images `![…](…)` — before links to avoid `[…](…)` matching the inner part
2. Links `[…](…)`
3. Bold `**…**` / `__…__`
4. Italic `*…*` / `_…_`
5. Inline code `` `…` ``
6. Strikethrough `~~…~~`

### `lua/markview/template.lua`
Builds the complete browser HTML page.

**Key internals:**
- `CSS`: embedded multi-line string with GitHub-flavored styling, CSS custom properties for theming, and a `prefers-color-scheme: dark` media query.
- `JS`: small `EventSource` client — connects to `/events`, updates `#content` innerHTML on each message, preserves `window.scrollY`, relies on browser's built-in SSE reconnect.
- `M.full_page(body_html, config)`: assembles `<!DOCTYPE html>…</html>`. Injects `<meta name="color-scheme" content="light|dark">` when `config.theme` is not `"auto"`.

### `lua/markview/util.lua`
- `M.debounce(fn, ms)`: wraps `fn` with a `vim.uv` timer. Each call resets the timer; `fn` fires after `ms` milliseconds of silence. Uses `vim.schedule_wrap` to safely call Neovim APIs from the timer callback.
- `M.find_free_port(start_port)`: iterates from `start_port` to `start_port + 100`, attempting `tcp:bind()` inside a `pcall`. Returns the first port that binds successfully, or `nil`.

---

## Configuration Options

Defaults (in `init.lua`):

```lua
{
  port        = 8765,           -- starting port; auto-increments up to +100 if busy
  auto_open   = false,          -- auto-start preview on FileType=markdown
  debounce_ms = 200,            -- milliseconds to debounce buffer change events
  browser     = nil,            -- nil = OS default; string = explicit command
  theme       = "auto",         -- "auto" | "light" | "dark"
  keymaps     = {
    toggle = "<leader>mp",      -- set to false/nil to disable
  },
}
```

Users call `require("markview").setup(opts)` to override. Config is a module-level table — `setup()` must be called before `open()`.

---

## Development Conventions

### Lua Style
- No strict linter is configured. Follow the style of existing files: 2-space indentation, snake_case for locals and module functions.
- Type annotations use the EmmyLua/LuaLS format (`---@param`, `---@return`, `---@type`) — maintain these on all public functions.
- Module pattern: every file returns a single `local M = {}` table.
- No external libraries. Stick to `vim.*` APIs and the Lua standard library.

### Neovim API Usage
- Use `vim.uv` (not `vim.loop`) for libuv bindings — `vim.loop` is a deprecated alias.
- Any Neovim API call (`vim.api.*`, `vim.notify`, `vim.schedule`, etc.) invoked from inside a `vim.uv` callback **must** be wrapped in `vim.schedule(function() … end)`.
- Buffer validity should be checked with `vim.api.nvim_buf_is_valid(bufnr)` before accessing buffer contents inside async callbacks.

### Error Handling
- Use `pcall` around operations that may fail cleanly (e.g., port binding, augroup deletion).
- Use `vim.notify("[markview] <message>", vim.log.levels.<LEVEL>)` for user-facing notifications. Keep the `[markview]` prefix.

### Adding New Markdown Syntax
1. Add parsing logic in `lua/markview/parser.lua` inside `M.render()`.
2. Inline syntax: add a `gsub` in `apply_inline()`.
3. Block syntax: add a new `if` branch in the main `while i <= #lines do` loop. Always call relevant `flush_*()` helpers before emitting HTML for a new block type.
4. Respect parser ordering — blocks are checked in this priority: fenced code block → blockquote → heading → horizontal rule → GFM table → unordered list → ordered list → empty line → paragraph.
5. Add CSS in `lua/markview/template.lua` if the new element needs styling.

### Adding New Configuration Options
1. Add the default value to `default_config` in `lua/markview/init.lua`.
2. Add a LuaLS annotation (`---@field`) if extending a typed table.
3. Pass `config` through to wherever the option is consumed (it is already passed to `server.start` and `template.full_page`).
4. Document the new option in `doc/markview.txt` and `README.md`.

### Per-Buffer State
The `state` table in `init.lua` is the single source of truth for active previews:
```lua
state[bufnr] = { srv = <server handle>, port = <number>, augroup = <string> }
```
- Always check `state[bufnr]` before starting or stopping.
- Always set `state[bufnr] = nil` on close.
- The `BufDelete` autocmd calls `M.close()` automatically — no manual cleanup needed in most flows.

### SSE Protocol Notes
- SSE frames sent by the server: `data: <payload>\n\n` (two newlines to terminate the event).
- Newlines inside the HTML payload are escaped to the literal string `\n` before sending, then unescaped by the JavaScript client with `.replace(/\\n/g, '\n')`.
- The browser's `EventSource` handles reconnection automatically; the server does not need to implement keep-alive pings for basic use.

---

## Testing

There is no automated test suite. Manual testing steps:

1. Open Neovim with a Markdown file.
2. Call `:MarkviewOpen` — verify the browser opens and renders the content.
3. Edit the buffer — verify the preview updates within ~200ms.
4. Close the buffer or call `:MarkviewClose` — verify the server stops (port is freed).
5. Test with `auto_open = true` to verify the `FileType` autocmd fires.
6. Test port collision: start two previews for two different buffers — each should use a different port.
7. Test theme options: `"light"`, `"dark"`, `"auto"` (check browser dev tools for `color-scheme` meta tag).

---

## Common Pitfalls

- **`vim.uv` vs `vim.loop`**: always use `vim.uv`; `vim.loop` is deprecated in Neovim 0.10+.
- **Neovim API in uv callbacks**: forgetting `vim.schedule()` causes "attempt to call a nil value" or Neovim assertion errors.
- **SSE newline escaping**: the HTML payload must have all `\n` replaced with the literal `\n` (two characters) before sending over SSE, or the browser will split the event at each newline.
- **`parse_table` lookahead**: the table parser reads `lines[i+1]` — always guard with `lines[i+1]` existence check (already done) before extending.
- **`apply_inline` ordering**: images must be processed before links, otherwise `![alt](src)` partially matches the `[text](url)` pattern.
- **`find_free_port` side effect**: the function binds and immediately closes a TCP handle for each port tested — this is intentional but means the port check is not atomic. Race conditions are theoretically possible but negligible in practice for a local plugin.

---

## Branch / Git Workflow

- Main branch: `master`
- Feature/fix branches follow the pattern: `claude/<description>-<id>`
- Commit messages are plain English imperatives (e.g., `Add strikethrough support to parser`).
- There is no CI pipeline — all validation is manual.
