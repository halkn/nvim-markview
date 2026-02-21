local M = {}

local CSS = [[
:root {
  --bg: #ffffff;
  --fg: #1f2328;
  --border: #d0d7de;
  --code-bg: #f6f8fa;
  --link: #0969da;
  --blockquote-border: #d0d7de;
  --blockquote-fg: #57606a;
  --table-header-bg: #f6f8fa;
  --hr-color: #d0d7de;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117;
    --fg: #e6edf3;
    --border: #30363d;
    --code-bg: #161b22;
    --link: #58a6ff;
    --blockquote-border: #30363d;
    --blockquote-fg: #8b949e;
    --table-header-bg: #161b22;
    --hr-color: #30363d;
  }
}
* { box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  font-size: 16px;
  line-height: 1.6;
  color: var(--fg);
  background: var(--bg);
  margin: 0;
  padding: 0;
}
#content {
  max-width: 800px;
  margin: 0 auto;
  padding: 32px 16px;
}
h1, h2, h3, h4, h5, h6 {
  margin-top: 24px;
  margin-bottom: 16px;
  font-weight: 600;
  line-height: 1.25;
}
h1 { font-size: 2em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
h2 { font-size: 1.5em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
h3 { font-size: 1.25em; }
h4 { font-size: 1em; }
h5 { font-size: 0.875em; }
h6 { font-size: 0.85em; }
p { margin-top: 0; margin-bottom: 16px; }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
code {
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
  font-size: 0.875em;
  background: var(--code-bg);
  padding: 0.2em 0.4em;
  border-radius: 6px;
}
pre {
  background: var(--code-bg);
  border-radius: 6px;
  padding: 16px;
  overflow: auto;
  margin-bottom: 16px;
}
pre code {
  background: none;
  padding: 0;
  font-size: 0.875em;
}
blockquote {
  margin: 0 0 16px;
  padding: 0 1em;
  border-left: 4px solid var(--blockquote-border);
  color: var(--blockquote-fg);
}
ul, ol {
  margin-top: 0;
  margin-bottom: 16px;
  padding-left: 2em;
}
li { margin-bottom: 4px; }
table {
  border-collapse: collapse;
  width: 100%;
  margin-bottom: 16px;
}
th, td {
  border: 1px solid var(--border);
  padding: 6px 13px;
}
th { background: var(--table-header-bg); font-weight: 600; }
tr:nth-child(even) td { background: var(--code-bg); }
hr {
  border: none;
  border-top: 1px solid var(--hr-color);
  margin: 24px 0;
}
img { max-width: 100%; }
del { text-decoration: line-through; opacity: 0.7; }
]]

local JS = [[
(function() {
  var evtSource = new EventSource('/events');
  evtSource.onmessage = function(e) {
    var scrollY = window.scrollY;
    var html = e.data.replace(/\\n/g, '\n');
    document.getElementById('content').innerHTML = html;
    window.scrollTo(0, scrollY);
  };
  evtSource.onerror = function() {
    // Reconnect is handled automatically by EventSource
  };
})();
]]

---@param body_html string
---@param config table
---@return string
function M.full_page(body_html, config)
  local theme = (config and config.theme) or "auto"
  local color_scheme = ""
  if theme == "light" then
    color_scheme = '<meta name="color-scheme" content="light">'
  elseif theme == "dark" then
    color_scheme = '<meta name="color-scheme" content="dark">'
  end

  return table.concat({
    "<!DOCTYPE html>",
    "<html>",
    "<head>",
    '<meta charset="UTF-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    color_scheme,
    "<title>Markview</title>",
    "<style>",
    CSS,
    "</style>",
    "</head>",
    "<body>",
    '<div id="content">',
    body_html,
    "</div>",
    "<script>",
    JS,
    "</script>",
    "</body>",
    "</html>",
  }, "\n")
end

return M
