local M = {}

local CSS = [[
:root {
  --bg: #ffffff;
  --fg: #323130;
  --border: #edebe9;
  --code-bg: #f3f2f1;
  --link: #0078d4;
  --blockquote-border: #c8c6c4;
  --blockquote-fg: #605e5c;
  --table-header-bg: #f3f2f1;
  --hr-color: #edebe9;
  --admonition-note: #0078d4;
  --admonition-tip: #107c10;
  --admonition-warning: #c19c00;
  --admonition-important: #8764b8;
  --admonition-caution: #c50f1f;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1b1a19;
    --fg: #d2d0ce;
    --border: #484644;
    --code-bg: #292827;
    --link: #479ef5;
    --blockquote-border: #605e5c;
    --blockquote-fg: #9e9d9c;
    --table-header-bg: #292827;
    --hr-color: #484644;
    --admonition-note: #479ef5;
    --admonition-tip: #54b454;
    --admonition-warning: #fce100;
    --admonition-important: #b17ec8;
    --admonition-caution: #e37d80;
  }
}
* { box-sizing: border-box; }
body {
  font-family: "Segoe UI", -apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif;
  font-size: 14px;
  line-height: 1.6;
  color: var(--fg);
  background: var(--bg);
  margin: 0;
  padding: 0;
}
#content {
  max-width: 900px;
  margin: 0 auto;
  padding: 32px 24px;
}
h1, h2, h3, h4, h5, h6 {
  margin-top: 24px;
  margin-bottom: 8px;
  font-weight: 600;
  line-height: 1.25;
}
h1 { font-size: 2em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
h2 { font-size: 1.5em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
h3 { font-size: 1.25em; }
h4 { font-size: 1em; }
h5 { font-size: 0.875em; }
h6 { font-size: 0.85em; color: var(--blockquote-fg); }
h1 a, h2 a, h3 a, h4 a, h5 a, h6 a { color: inherit; text-decoration: none; }
p { margin-top: 0; margin-bottom: 16px; }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
code {
  font-family: ui-monospace, Consolas, "Courier New", monospace;
  font-size: 0.875em;
  background: var(--code-bg);
  padding: 0.2em 0.4em;
  border-radius: 3px;
  border: 1px solid var(--border);
}
pre {
  background: var(--code-bg);
  border-radius: 3px;
  border: 1px solid var(--border);
  padding: 16px;
  overflow: auto;
  margin-bottom: 16px;
}
pre code {
  background: none;
  padding: 0;
  font-size: 0.875em;
  border: none;
}
blockquote {
  margin: 0 0 16px;
  padding: 4px 16px;
  border-left: 4px solid var(--blockquote-border);
  color: var(--blockquote-fg);
}
blockquote > :last-child { margin-bottom: 0; }
ul, ol {
  margin-top: 0;
  margin-bottom: 16px;
  padding-left: 2em;
  margin-left: 1em;
}
ul ul, ul ol, ol ul, ol ol {
  margin-left: 0;
  margin-bottom: 0;
  margin-top: 4px;
}
li { margin-bottom: 4px; }
/* Task list */
li.task-list-item { list-style: none; margin-left: -1.5em; }
li.task-list-item input[type="checkbox"] {
  margin-right: 6px;
  cursor: default;
  vertical-align: middle;
}
table {
  border-collapse: collapse;
  width: 100%;
  margin-bottom: 16px;
}
th, td {
  border: 1px solid var(--border);
  padding: 6px 13px;
  text-align: left;
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
/* Admonitions (Azure DevOps style: > [!NOTE], > [!WARNING], etc.) */
.admonition {
  margin-bottom: 16px;
  padding: 8px 16px;
  border-left: 4px solid;
  border-radius: 0 3px 3px 0;
}
.admonition > :last-child { margin-bottom: 0; }
.admonition-title {
  font-weight: 600;
  margin-bottom: 4px;
  margin-top: 0;
  font-size: 0.875em;
  letter-spacing: 0.03em;
}
.admonition-title::before { margin-right: 6px; }
.admonition.note {
  border-color: var(--admonition-note);
  background: color-mix(in srgb, var(--admonition-note) 8%, transparent);
}
.admonition.note .admonition-title { color: var(--admonition-note); }
.admonition.note .admonition-title::before { content: "\2139"; }
.admonition.tip {
  border-color: var(--admonition-tip);
  background: color-mix(in srgb, var(--admonition-tip) 8%, transparent);
}
.admonition.tip .admonition-title { color: var(--admonition-tip); }
.admonition.tip .admonition-title::before { content: "\2714"; }
.admonition.warning {
  border-color: var(--admonition-warning);
  background: color-mix(in srgb, var(--admonition-warning) 10%, transparent);
}
.admonition.warning .admonition-title { color: var(--admonition-warning); }
.admonition.warning .admonition-title::before { content: "\26A0"; }
.admonition.important {
  border-color: var(--admonition-important);
  background: color-mix(in srgb, var(--admonition-important) 8%, transparent);
}
.admonition.important .admonition-title { color: var(--admonition-important); }
.admonition.important .admonition-title::before { content: "\0021"; }
.admonition.caution {
  border-color: var(--admonition-caution);
  background: color-mix(in srgb, var(--admonition-caution) 8%, transparent);
}
.admonition.caution .admonition-title { color: var(--admonition-caution); }
.admonition.caution .admonition-title::before { content: "\26D4"; }
/* Mermaid diagrams */
.mermaid {
  text-align: center;
  margin-bottom: 16px;
  overflow: auto;
}
/* Heading anchor hover link */
h1:hover .anchor-link,
h2:hover .anchor-link,
h3:hover .anchor-link,
h4:hover .anchor-link,
h5:hover .anchor-link,
h6:hover .anchor-link { opacity: 1; }
]]

-- highlight.js CSS links based on theme
local function hljs_css(theme)
  local base = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/"
  if theme == "light" then
    return '<link rel="stylesheet" href="' .. base .. 'github.min.css">'
  elseif theme == "dark" then
    return '<link rel="stylesheet" href="' .. base .. 'github-dark.min.css">'
  else
    -- auto: use media queries
    return table.concat({
      '<link rel="stylesheet" media="(prefers-color-scheme: light)" href="' .. base .. 'github.min.css">',
      '<link rel="stylesheet" media="(prefers-color-scheme: dark)" href="' .. base .. 'github-dark.min.css">',
    }, "\n")
  end
end

-- JS with highlight.js and mermaid.js integration
local function build_js(theme)
  local mermaid_theme
  if theme == "dark" then
    mermaid_theme = '"dark"'
  elseif theme == "light" then
    mermaid_theme = '"default"'
  else
    mermaid_theme = '(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) ? "dark" : "default"'
  end

  return [[
(function() {
  function afterRender() {
    if (window.hljs) {
      document.querySelectorAll('pre code').forEach(function(block) {
        hljs.highlightElement(block);
      });
    }
    if (window.mermaid) {
      var nodes = document.querySelectorAll('.mermaid:not([data-processed])');
      if (nodes.length > 0) {
        mermaid.run({ nodes: nodes });
      }
    }
  }

  // Initialize mermaid
  if (window.mermaid) {
    mermaid.initialize({ startOnLoad: false, theme: ]] .. mermaid_theme .. [[ });
  }

  var evtSource = new EventSource('/events');
  evtSource.onmessage = function(e) {
    var scrollY = window.scrollY;
    var html = e.data.replace(/\\n/g, '\n');
    document.getElementById('content').innerHTML = html;
    window.scrollTo(0, scrollY);
    afterRender();
  };
  evtSource.onerror = function() {
    // Reconnect is handled automatically by EventSource
  };

  window.addEventListener('load', afterRender);
})();
]]
end

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
    hljs_css(theme),
    "<style>",
    CSS,
    "</style>",
    "</head>",
    "<body>",
    '<div id="content">',
    body_html,
    "</div>",
    '<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>',
    '<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>',
    "<script>",
    build_js(theme),
    "</script>",
    "</body>",
    "</html>",
  }, "\n")
end

return M
