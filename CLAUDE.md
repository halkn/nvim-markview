# CLAUDE.md — nvim-markview

このファイルは、本コードベースで作業する AI アシスタント向けのコンテキストを提供します。

## プロジェクト概要

**nvim-markview** は、ユーザーのデフォルトブラウザでリアルタイムの Markdown プレビューを表示する Neovim プラグインです。外部ランタイム依存なしに純粋な Lua で実装されており、Neovim のイベントループ内で `vim.uv`（libuv）を使って軽量な HTTP サーバーを動作させています。

- **言語:** Lua（Neovim プラグイン）
- **ランタイム:** Neovim 0.10+（`vim.uv` が必要）
- **依存関係:** なし（純粋な Lua + Neovim 標準ライブラリ）
- **ライセンス:** MIT

---

## リポジトリ構成

```
nvim-markview/
├── plugin/
│   └── markview.lua          # プラグインエントリポイント — Neovim ユーザーコマンドを登録
├── lua/
│   └── markview/
│       ├── init.lua          # 公開 API: setup(), open(), close(), toggle()
│       ├── server.lua        # HTTP/SSE サーバー（vim.uv TCP）
│       ├── parser.lua        # Markdown → HTML レンダラー
│       ├── template.lua      # 完全な HTML ページビルダー（CSS + JS 埋め込み）
│       └── util.lua          # debounce() と find_free_port() ユーティリティ
├── doc/
│   └── markview.txt          # Neovim :help ドキュメント
└── README.md
```

---

## アーキテクチャ

### データフロー

```
[Neovim バッファ]
    |
    | TextChanged / TextChangedI autocmd
    v
[util.debounce(200ms)]           -- タイピング中の過剰な更新を防ぐ
    |
    | デバウンス完了後に fn() を呼び出し
    v
[server.push(markdown)]
    |
    | parser.render(markdown) -> HTML 文字列
    v
[全 /events クライアントへ SSE ブロードキャスト]
    |
    | "data: <エスケープ済み HTML>\n\n"
    v
[ブラウザ EventSource.onmessage]
    |
    | #content の innerHTML を置換、スクロール位置を復元
    v
[ライブプレビュー更新完了]
```

### HTTP サーバーエンドポイント

`127.0.0.1:<port>` にバインドされた同一の `vim.uv` TCP サーバーが両エンドポイントを処理します。

| エンドポイント  | メソッド | 用途                                               |
|----------------|----------|----------------------------------------------------|
| `/`            | GET      | 完全な HTML ページ（初回ページロード）             |
| `/events`      | GET      | SSE ストリーム — 変更時にレンダリング済み HTML を push |
| その他         | GET      | 404 Not Found                                      |

サーバーは意図的に `127.0.0.1`（ループバック）のみでリッスンし、パブリックインターフェイスには公開しません。

---

## モジュール責務

### `plugin/markview.lua`
- プラグインのニ重読み込み防止ガード（`vim.g.loaded_markview`）。
- 3 つの Neovim ユーザーコマンドを登録: `:MarkviewOpen`、`:MarkviewClose`、`:MarkviewToggle`。
- `setup()` は**呼び出さない** — それはユーザーの責任。

### `lua/markview/init.lua`
プラグインのコア。バッファごとの状態を管理し、すべてのサブシステムを調整します。

**主要な内部実装:**
- `state` テーブル: `table<bufnr, { srv, port, augroup }>` — バッファごとのアクティブなプレビューを追跡。
- `config` テーブル: `vim.tbl_deep_extend` で `default_config` とユーザー指定オプションをマージ。
- `detect_browser()`: `vim.loop.os_uname().sysname` を参照し、`open`（macOS）、`cmd /c start`（Windows）、`xdg-open`（Linux/WSL）を選択。
- `M.open(bufnr)`: サーバーを起動し、autocmd（`TextChanged`、`TextChangedI`、`BufDelete`）を作成し、初回プッシュを行い、100ms 遅延後にブラウザを開く。
- `M.close(bufnr)`: `srv.stop()` を呼び出し、augroup を削除し、state をクリア。
- `M.setup(opts)`: 設定をマージし、必要に応じて `auto_open` 用の `FileType markdown` autocmd を登録し、トグルキーマップをバインド。

### `lua/markview/server.lua`
`vim.uv.new_tcp()` を使った HTTP サーバーの実装。

**主要な内部実装:**
- `clients` リスト: オープン中の SSE `uv_tcp` ハンドルを保持。
- `current_html`: 最後にレンダリングされた HTML をキャッシュ。新しい SSE クライアントが接続した際に即座に送信するために使用。
- `make_http_response(status, headers, body)`: 生の HTTP/1.1 レスポンス文字列を構築。
- `parse_request_line(data)`: 生の HTTP リクエストバイトからメソッドとパスを抽出。
- `push(markdown)`: markdown → HTML にレンダリングし、改行を `\n` としてエスケープし、全ライブクライアントに `data: ...\n\n` を書き込み、切断済みハンドルを除去。
- `stop()`: 全 SSE クライアントと TCP サーバーハンドルを閉じる。
- uv コールバック内の Neovim API 呼び出しはすべて `vim.schedule()` でラップすること。

### `lua/markview/parser.lua`
シングルパスのステートマシン型 Markdown レンダラー。Markdown 文字列を HTML フラグメント（`<html>` ラッパーなし）に変換します。Azure DevOps wiki / pull request の Markdown 仕様に準拠しています。

**サポートする構文:**

| 要素              | 構文                                                      |
|-------------------|-----------------------------------------------------------|
| 見出し            | `# H1` 〜 `###### H6`（ATX のみ）                        |
| 太字              | `**text**` または `__text__`                              |
| 斜体              | `*text*` または `_text_`                                  |
| 取り消し線        | `~~text~~`                                                |
| インラインコード  | `` `code` ``                                              |
| リンク            | `[text](url)`                                             |
| 画像              | `![alt](src)`                                             |
| ハード改行        | 行末スペース2つ                                           |
| フェンスコードブロック | ` ```lang ` / ` ``` `                                |
| 順序なしリスト    | `- item`、`* item`                                        |
| 順序付きリスト    | `1. item`、`2. item`、…                                   |
| タスクリスト      | `- [ ] todo`、`- [x] done`（`[X]` も可）                 |
| ブロッククォート  | `> text`（再帰的、ネスト対応）                            |
| アドモニション    | `> [!NOTE]` / `> [!TIP]` / `> [!WARNING]` / `> [!IMPORTANT]` / `> [!CAUTION]` |
| GFM テーブル      | セパレーター行付きパイプ区切り                            |
| 水平線            | `---`、`***`、または `___`                                |
| Mermaid（コロン） | `::: mermaid` … `:::`（Azure DevOps ネイティブ構文）      |
| Mermaid（バッククォート） | ` ```mermaid ` … ` ``` `                        |
| 段落              | いずれにも一致しない行                                    |

**主要な内部実装:**
- `escape_html(s)`: `& < > "` をエスケープ — HTML に挿入する前にユーザーコンテンツに常に適用。
- `slugify(text)`: 見出しテキストから URL 安全なアンカー ID を生成（小文字化・非英数字除去・スペースをハイフンに変換）。
- `apply_inline(s)`: すべてのインラインパターンを適用。画像はリンクより先に処理し競合を回避。
- `flush_para()`: 保留中の段落を出力。行末スペース2つを `<br>` に変換してからフラッシュ。
- `flush_list()`、`flush_blockquote()`: 保留中の HTML を出力し状態フラグをリセットする状態遷移ヘルパー。
- `flush_blockquote()`: 最初の行が `[!TYPE]` の場合はアドモニションとして、それ以外は通常のブロッククォートとして出力。
- `parse_table(lines, i)`: 先読みパーサー。コミット前に `lines[i+1]` のセパレーター行パターンを確認。
- `M.render(markdown)` はブロッククォートとアドモニションの内部コンテンツに対して再帰的に自身を呼び出す。

**パーサー順序（ブロック要素のチェック優先順）:**
1. フェンスコードブロック（` ``` `）
2. コンテナブロック（`:::`）— Mermaid 等
3. ブロッククォート（`>`）— アドモニション判定を含む
4. ATX 見出し（`#`）
5. 水平線（`---` 等）
6. GFM テーブル（`|`）
7. 順序なしリスト（`-`、`*`）— タスクリスト判定を含む
8. 順序付きリスト（`1.`）
9. 空行
10. 段落

**パーサー順序（インラインパターンの適用順）:**
1. 画像 `![…](…)` — リンクより先に処理（`[…](…)` が内部にマッチするのを防ぐため）
2. リンク `[…](…)`
3. 太字 `**…**` / `__…__`
4. 斜体 `*…*` / `_…_`
5. インラインコード `` `…` ``
6. 取り消し線 `~~…~~`

### `lua/markview/template.lua`
ブラウザ用の完全な HTML ページを構築します。

**主要な内部実装:**
- `CSS`: Azure DevOps カラーパレット（フォント: Segoe UI、アクセント: `#0078d4`）、テーマ用 CSS カスタムプロパティ、`prefers-color-scheme: dark` メディアクエリ、アドモニション・タスクリスト・Mermaid のスタイリングを含む埋め込み複数行文字列。
- `hljs_css(theme)`: `config.theme` に基づいて highlight.js のスタイルシート `<link>` タグを生成。`"auto"` の場合はメディアクエリで light/dark を切り替え。
- `build_js(theme)`: `EventSource` クライアントと highlight.js・mermaid.js の初期化コードを生成。SSE 更新のたびに `hljs.highlightElement()` と `mermaid.run()` を呼び出す。`config.theme` に応じて Mermaid のテーマ（`"default"` / `"dark"`）を設定。
- `M.full_page(body_html, config)`: `<!DOCTYPE html>…</html>` を組み立て。highlight.js（CDN）・mermaid.js（CDN）の `<script>` / `<link>` タグを含む。`config.theme` が `"auto"` でない場合に `<meta name="color-scheme" content="light|dark">` を挿入。

**CDN 依存:**
- highlight.js 11.9.0: `cdnjs.cloudflare.com` — コードブロックのシンタックスハイライト
- mermaid.js v11: `cdn.jsdelivr.net` — Mermaid ダイアグラムのレンダリング
- オフライン環境ではこれらの機能は動作しないが、コンテンツ自体は表示される。

### `lua/markview/util.lua`
- `M.debounce(fn, ms)`: `vim.uv` タイマーで `fn` をラップ。各呼び出しでタイマーをリセット。`ms` ミリ秒の無活動後に `fn` を発火。タイマーコールバックから Neovim API を安全に呼び出すために `vim.schedule_wrap` を使用。
- `M.find_free_port(start_port)`: `start_port` から `start_port + 100` まで反復し、`pcall` 内で `tcp:bind()` を試みる。最初に正常にバインドできたポートを返し、見つからない場合は `nil` を返す。

---

## 設定オプション

デフォルト値（`init.lua` 内）:

```lua
{
  port        = 8765,           -- 開始ポート; 使用中の場合は最大 +100 まで自動インクリメント
  auto_open   = false,          -- FileType=markdown 時にプレビューを自動開始
  debounce_ms = 200,            -- バッファ変更イベントのデバウンス時間（ミリ秒）
  browser     = nil,            -- nil = OS デフォルト; string = 明示的なコマンド
  theme       = "auto",         -- "auto" | "light" | "dark"
  keymaps     = {
    toggle = "<leader>mp",      -- false/nil に設定すると無効化
  },
}
```

ユーザーは `require("markview").setup(opts)` を呼び出して上書きします。Config はモジュールレベルのテーブルで、`setup()` は `open()` より前に呼び出す必要があります。

---

## 開発規約

### Lua スタイル
- 厳格なリンターは設定されていません。既存ファイルのスタイルに従ってください: 2 スペースインデント、ローカルとモジュール関数は snake_case。
- 型アノテーションは EmmyLua/LuaLS 形式（`---@param`、`---@return`、`---@type`）を使用 — すべての公開関数で維持すること。
- モジュールパターン: すべてのファイルは単一の `local M = {}` テーブルを返す。
- 外部ライブラリは使用しない。`vim.*` API と Lua 標準ライブラリのみを使用。

### Neovim API の使用
- libuv バインディングには `vim.uv` を使用（`vim.loop` は非推奨エイリアス）。
- `vim.uv` コールバック内での Neovim API 呼び出し（`vim.api.*`、`vim.notify`、`vim.schedule` など）は必ず `vim.schedule(function() … end)` でラップすること。
- 非同期コールバック内でバッファコンテンツにアクセスする前に、`vim.api.nvim_buf_is_valid(bufnr)` でバッファの有効性を確認すること。

### エラーハンドリング
- 正常に失敗しうる操作（ポートバインディング、augroup 削除など）には `pcall` を使用。
- ユーザー向け通知には `vim.notify("[markview] <メッセージ>", vim.log.levels.<LEVEL>)` を使用。`[markview]` プレフィックスを維持すること。

### 新しい Markdown 構文の追加
1. `lua/markview/parser.lua` の `M.render()` 内にパースロジックを追加。
2. インライン構文: `apply_inline()` に `gsub` を追加。
3. ブロック構文: メインの `while i <= #lines do` ループに新しい `if` ブランチを追加。新しいブロックタイプの HTML を出力する前に、必ず関連する `flush_*()` ヘルパーを呼び出すこと。
4. パーサー順序を遵守 — ブロックはこの優先順位でチェックされる: フェンスコードブロック → コンテナブロック（:::）→ ブロッククォート → 見出し → 水平線 → GFM テーブル → 順序なしリスト → 順序付きリスト → 空行 → 段落。
5. 新しい要素にスタイリングが必要な場合は `lua/markview/template.lua` に CSS を追加。

### 新しい設定オプションの追加
1. `lua/markview/init.lua` の `default_config` にデフォルト値を追加。
2. 型付きテーブルを拡張する場合は LuaLS アノテーション（`---@field`）を追加。
3. オプションが消費される場所まで `config` を渡す（すでに `server.start` と `template.full_page` に渡されている）。
4. `doc/markview.txt` と `README.md` に新しいオプションを記載。

### バッファごとの状態
`init.lua` の `state` テーブルがアクティブなプレビューの唯一の信頼できる情報源:
```lua
state[bufnr] = { srv = <サーバーハンドル>, port = <数値>, augroup = <文字列> }
```
- 開始・停止の前に必ず `state[bufnr]` を確認。
- クローズ時に必ず `state[bufnr] = nil` を設定。
- `BufDelete` autocmd が自動的に `M.close()` を呼び出す — ほとんどのフローでは手動クリーンアップは不要。

### SSE プロトコルのメモ
- サーバーが送信する SSE フレーム: `data: <ペイロード>\n\n`（イベントを終了する 2 つの改行）。
- HTML ペイロード内の改行は送信前にリテラル文字列 `\n` にエスケープし、JavaScript クライアントが `.replace(/\\n/g, '\n')` でアンエスケープする。
- ブラウザの `EventSource` が自動的に再接続を処理するため、基本的な使用ではサーバーにキープアライブ ping を実装する必要はない。

---

## テスト

自動テストスイートはありません。手動テスト手順:

1. Markdown ファイルで Neovim を開く。
2. `:MarkviewOpen` を実行 — ブラウザが開いてコンテンツがレンダリングされることを確認。
3. バッファを編集 — 約 200ms 以内にプレビューが更新されることを確認。
4. バッファを閉じるか `:MarkviewClose` を実行 — サーバーが停止する（ポートが解放される）ことを確認。
5. `auto_open = true` でテスト — `FileType` autocmd が発火することを確認。
6. ポート衝突のテスト: 2 つの異なるバッファで 2 つのプレビューを開始 — それぞれが異なるポートを使用することを確認。
7. テーマオプションのテスト: `"light"`、`"dark"`、`"auto"`（ブラウザ開発者ツールで `color-scheme` メタタグを確認）。

---

## よくある落とし穴

- **`vim.uv` vs `vim.loop`**: 常に `vim.uv` を使用。`vim.loop` は Neovim 0.10+ で非推奨。
- **uv コールバック内の Neovim API**: `vim.schedule()` を忘れると "attempt to call a nil value" や Neovim アサーションエラーが発生する。
- **SSE 改行エスケープ**: HTML ペイロードの `\n` は SSE 送信前にリテラルの `\n`（2 文字）に置換する必要がある。そうしないとブラウザが各改行でイベントを分割する。
- **`parse_table` 先読み**: テーブルパーサーは `lines[i+1]` を読む — 拡張する際は `lines[i+1]` の存在チェックを必ずガードすること（既に実装済み）。
- **`apply_inline` の順序**: 画像はリンクより先に処理する必要がある。そうしないと `![alt](src)` が `[text](url)` パターンに部分マッチする。
- **`find_free_port` の副作用**: この関数はテストする各ポートに対して TCP ハンドルをバインドし即座に閉じる — これは意図的だが、ポートチェックがアトミックでないことを意味する。ローカルプラグインの実用上、競合状態は理論上は起こりうるが無視できる。
- **コンテナブロック（`:::`）とコードブロック（` ``` `）の優先順位**: コンテナブロックのチェックはコードブロックの `in_code_block` ガードの後に置くこと。コードブロック内の `:::` 行はそのままコード行として扱われる。
- **Mermaid の再レンダリング**: SSE 更新後に `#content` の innerHTML を置換すると、新しい `.mermaid` 要素は `data-processed` 属性を持たない。`mermaid.run()` を呼び出すだけで再レンダリングできる。
- **CDN オフライン時**: highlight.js / mermaid.js の CDN が利用できない場合でも、コードブロックやダイアグラムのソーステキスト自体は表示される（ハイライト・描画なし）。エラーにはならない。
- **Azure DevOps 非対応構文**: `\` による強制改行は Azure DevOps 非対応のため実装しない。行末スペース2つのみをサポートする。

---

## ブランチ / Git ワークフロー

- メインブランチ: `master`
- フィーチャー/フィックスブランチの命名パターン: `claude/<説明>-<id>`
- コミットメッセージは英語の命令形（例: `Add strikethrough support to parser`）。
- CI パイプラインなし — すべての検証は手動。
