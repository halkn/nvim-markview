# nvim-markview

Real-time Markdown browser preview for Neovim — no Node.js or pandoc required.

## Features

- Live preview in your default browser via Server-Sent Events (SSE)
- Pure Lua implementation using `vim.uv` (libuv) — zero external dependencies
- GitHub-flavored Markdown: headings, fenced code, tables, lists, blockquotes, and more
- Auto dark/light theme following OS `prefers-color-scheme`
- Scroll position preserved on updates
- Multiple buffer support

## Requirements

- Neovim 0.10+
- A web browser

## Installation

### lazy.nvim

```lua
{
  "halkn/nvim-markview",
  ft = "markdown",
  opts = {},
}
```

### packer.nvim

```lua
use {
  "halkn/nvim-markview",
  config = function()
    require("markview").setup()
  end,
}
```

## Usage

Open a Markdown file, then:

| Command            | Description                          |
|--------------------|--------------------------------------|
| `:MarkviewOpen`    | Start the preview server and open browser |
| `:MarkviewClose`   | Stop the preview server              |
| `:MarkviewToggle`  | Toggle the preview                   |

Default keymap: `<leader>mp` to toggle.

## Configuration

```lua
require("markview").setup({
  port        = 8765,    -- HTTP server starting port
  auto_open   = false,   -- auto-preview when opening *.md files
  debounce_ms = 200,     -- delay (ms) before pushing SSE update
  browser     = nil,     -- nil = OS default (xdg-open / open / start)
  theme       = "auto",  -- "auto" | "light" | "dark"
  keymaps     = {
    toggle = "<leader>mp",
  },
})
```

## How It Works

```
[Neovim buffer] ──TextChanged──> [debounce] ──> [server.push(md)]
                                                      |
                                            [parser.render(md)]
                                                      |
                                            [SSE: data: html]
                                                      |
                                            [Browser DOM update]
```

`vim.uv.new_tcp()` runs a lightweight HTTP server inside Neovim's event loop.
`GET /` serves the initial HTML page; `GET /events` maintains a persistent
SSE connection. Every buffer change triggers a debounced push of re-rendered
HTML to all connected browser tabs.

## License

MIT
