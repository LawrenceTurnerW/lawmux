# lawmux

lawmux は [manaflow-ai/cmux](https://github.com/manaflow-ai/cmux) の個人 fork です。
cmux のターミナル部分（macOS アプリ・CLI）を、自分の環境向けに調整して使うためのリポジトリです。

- ライセンス: 本家と同じく、macOS アプリ・CLI などは GPL-3.0-or-later です（[LICENSE](LICENSE)）。
  `web/` や `workers/` などのサーバー部分は本家と同じ BUSL-1.1 のままで、lawmux では使っていません。
- 「cmux」は Manaflow, Inc. のプロダクト名です。lawmux は本家とは無関係の非公式 fork で、
  不具合を本家に報告しないでください。
- バイナリは配布していません。各自でソースからビルドしてください。
- Claude Code などのエージェント向けのルールは [.claude/CLAUDE.md](.claude/CLAUDE.md) にあります。
  ルート直下の `CLAUDE.md` は本家のものをそのまま置いているだけで、lawmux での作業には `.claude/CLAUDE.md` が優先です。

## 本家 cmux との違い

| 項目 | cmux | lawmux |
| --- | --- | --- |
| Release ビルドの Bundle ID | `com.cmuxterm.app` | `com.lawrenceturnerw.lawmux` |
| アプリの表示名 | cmux | lawmux |
| 設定ファイル | `~/.config/cmux/` | `~/.config/lawmux/` |
| 制御ソケットなどの状態 | `~/.local/state/cmux/` | `~/.local/state/lawmux/` |
| 利用状況の送信（PostHog） | あり | なし |
| クラッシュレポート（Sentry） | あり | なし |
| 自動アップデート（Sparkle） | あり | なし（`git pull` して再ビルド） |
| サイドバーの最新通知テキスト（`sidebar.showNotificationMessage`） | 既定で表示 | 既定で非表示（設定でオンに戻せる） |
| 内蔵ブラウザ（`browser.disabled`） | 既定で有効 | 既定で無効（設定で有効に戻せる） |
| ターミナル内リンクの開き先（`browser.openTerminalLinksInCmuxBrowser`） | 既定で内蔵ブラウザ | 既定で外部ブラウザ |
| 新規ワークスペースの開始ディレクトリ（`app.workspaceInheritWorkingDirectory`） | 現在のワークスペースの cwd を引き継ぐ | 引き継がない。設定 → App → Default Workspace Path（`app.defaultWorkspacePath`）、未設定なら Ghostty の `working-directory`、それもなければホーム |
| Default Workspace Path（`app.defaultWorkspacePath`）の意味 | Open Folder ダイアログの初期フォルダのみ。設定画面に項目なし | それに加えて、新規ワークスペースの開始ディレクトリ。設定 → 「一般」グループ先頭の **lawmux** ページで指定できる |
| 通知でワークスペースを並び替え（`app.reorderOnNotification`） | 通知を受けたワークスペースをサイドバーの先頭へ移動 | 並び替えない（設定 → アプリ で戻せる） |
| サイドバー左下のサインインボタン（feature flag `sidebar-account-button-enabled-release`） | 表示 | 非表示。`defaults write com.lawrenceturnerw.lawmux cmux.flags.override.sidebar-account-button-enabled-release -bool true` で戻せる |
| サイドバー左下のクラウドボタンとデバイスアイコン（`sidebar.showCloudDeviceIcons`） | 既定で表示 | 既定で非表示（設定 → Sidebar で戻せる） |
| システム全体のホットキー（`shortcuts.bindings.showHideAllWindows`、`app.systemWideHotkeyEnabled`） | ⌘⌥⌃.、既定でオフ | Shift+Space、既定でオン（設定 → Global Hotkey で変更） |

Bundle ID・設定・ソケットが分かれているので、本家 cmux と同時にインストール・起動できます。

lawmux で既定値を変えた項目は、`cmux config get <key>` の「(default)」表示には反映されません。
この表示は `web/data/cmux.schema.json` の既定値（本家のまま。BUSL ディレクトリなので lawmux では触らない）を
出しているためで、アプリの実際の挙動は上の表のとおりです。

lawmux で追加した設定画面の文言は、本家の文字列カタログ（`Resources/Localizable.xcstrings`）には入れていません
（カタログは全 9 言語の整合チェックがかかり、本家と衝突しやすいためです）。代わりに lawmux 側の `LawmuxText` で
表示言語が日本語なら日本語、それ以外は英語を出します。
CLI のコマンド名は本家と同じ `cmux` のままです。

本家の設定を引き継ぎたい場合は、最初に一度だけコピーしてください。

```sh
mkdir -p ~/.config/lawmux
cp -R ~/.config/cmux/. ~/.config/lawmux/
```

## ソースからのビルド

### 必要なもの

- macOS 14 以降
- Xcode（App Store 版。Command Line Tools だけでは不可）
- Homebrew

```sh
# Xcode を有効にする
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept

# Ghostty のビルドには Zig 0.16 系が必要（brew の zig は 0.17 なので不可）
# Go は Release ビルドに含まれるトンネル拡張のビルドに必要（拡張自体は lawmux では動きません）
brew install zig@0.16 bun rustup go
brew link --force zig@0.16
rustup default stable   # 1.88 以上が必要。古い場合は rustup update stable
```

Xcode 26 以降では Metal コンパイラが別配布なので、初回に一度だけ入れます。

```sh
xcodebuild -downloadComponent MetalToolchain
```

### Release ビルド（通常はこちら）

```sh
git clone --recursive https://github.com/LawrenceTurnerW/lawmux.git
cd lawmux
./scripts/setup.sh
./scripts/lawmux-build-release.sh --install --open
```

`lawmux-build-release.sh` は Release 構成をビルドし、`cmux.app` を `lawmux.app` に改名して
署名を検証したうえで、`--install` なら `/Applications/lawmux.app` に置き、`--open` なら起動します。
署名はアドホック（Apple Developer 登録なし）です。自分でビルドしたアプリなので Gatekeeper の
警告は出ません。本家 cmux が起動したままでも実行できます。

更新するときは `git pull`（または `scripts/lawmux-sync-upstream.sh`）のあと、同じコマンドを
もう一度実行してください。起動中の lawmux があれば先に終了します。

lawmux 自身のターミナルの中からビルドするときは `--detach` を付けます。

```sh
./scripts/lawmux-build-release.sh --install --open --detach
```

ビルドはその場で行い、「lawmux を終了 → 入れ替え → 再起動」だけを端末から切り離した
プロセスに任せます（終了した瞬間にスクリプト自身が道連れになるのを避けるため）。
ログは `~/Library/Developer/Xcode/DerivedData/lawmux-release/lawmux-install.log` に残ります。
再起動後はセッション復元で元のワークスペースが戻り、Claude Code を動かしていたペインは
`claude --resume` で会話に復帰します（入れ替え直前の応答は途切れます）。

ビルド時間を抑えるため、既定では **この Mac のアーキテクチャだけ**（M シリーズなら arm64）を
**差分コンパイル**でビルドします。本家の Release は Universal（arm64 + x86_64）かつ
Whole Module Optimization で、アプリ本体が 2,700 ファイル超の 1 モジュールなので、
そのままだと 1 行の変更でも 10 分以上かかります。

| 環境変数 | 効果 | 使いどころ |
| --- | --- | --- |
| `LAWMUX_UNIVERSAL=1` | x86_64 も含めた Universal バイナリにする | Intel Mac にも配りたいとき |
| `LAWMUX_WMO=1` | 本家と同じ Whole Module Optimization にする | 改造が落ち着いて安定版を作るとき |

どちらも切り替えた直後の 1 回はキャッシュが使えず、フルビルドになります。
DerivedData は `~/Library/Developer/Xcode/DerivedData/lawmux-release` に置かれ、
`LAWMUX_DERIVED_DATA` で変更できます。

### 開発用（Debug）ビルド

本家の開発フローをそのまま使えます。タグ付きビルドは Bundle ID が
`com.cmuxterm.app.debug.lawmux`、名前が「cmux DEV lawmux」になります。

```sh
CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag lawmux
open "$HOME/Library/Developer/Xcode/DerivedData/cmux-lawmux/Build/Products/Debug/cmux DEV lawmux.app"
```

`reload.sh --launch` は本家チーム向けのログイン情報（`~/.secrets/cmuxterm-dev.env`）がないと
起動を拒否するので、`--launch` を付けずにビルドし、出力された `.app` を `open` で開きます。

### 使えない機能

- Cloud 関連機能（ログイン、Cloud ターミナル、TunnelExtension）は Manaflow のサーバーと
  Apple の署名を前提にしているため、lawmux では動きません。

### テストについて

本家のテストの一部は、変更前のパスや Bundle ID（`~/.local/state/cmux`、`com.cmuxterm.app` など）を
直書きしているため、lawmux では失敗します。本家の取り込み時の衝突を増やさないよう、
テスト側は意図的に直していません。lawmux では本家の CI も動かしていないので、
変更の確認はビルドと実機での動作確認で行っています。

## lawmux 固有の機能

### ワークスペースのタイトル

サイドバーのタイトルは次の優先順位で決まります。上 2 つは本家の仕組み（`customTitle`）のままで、
3 つ目を lawmux が足しています（`Sources/LawmuxWorkspaceTitlePolicy.swift`）。

1. ユーザーが付けた名前（右クリック → Rename、`cmux rename-workspace`）
2. エージェント連携の自動命名（会話内容から付く名前）
3. フォーカス中のターミナルの cwd が属する **git worktree のディレクトリ名**（`.git` を上に辿って探す。
   linked worktree なら worktree 側のフォルダ名）
4. 本家どおりの端末タイトル（git 管理外のディレクトリのとき）

cwd が変わるたびに 3 を計算し直します。本家側の差し込みは `Workspace+TitleOwnership.swift` と
`Workspace.swift` の各 1 か所です。


### Claude のマスコット表示

`~/.config/lawmux/icons/` に画像を置くと、Claude Code が動いているワークスペースの行で、タイトルの前に
マスコットが出ます（`Sources/LawmuxMascotStatusView.swift`）。サイドバーの `claude_code` ピル
（Running / Idle / Needs input）と同じ情報を絵にしただけで、ピル自体はそのまま残ります。
画像はリポジトリには入れていません。各自で用意してください。

| ファイル | いつ出るか | 無いとき |
| --- | --- | --- |
| `claude-running.gif` | 処理中（モデルの応答、ツール実行、サブエージェント） | 表示機能ごと無効（本家と同じ見た目） |
| `claude-idle.png` | 次の入力待ち | running の画像を止めて薄く表示 |
| `claude-needs-input.png` | 許可や質問で止まっている | running の画像を止めて表示 |

アニメーション GIF は処理中だけ動きます。形式は NSImage が読めるものなら何でも構いません。
大きさは通知バッジと同じ 16pt 基準（フォント倍率に追従）なので、ドット絵なら 32〜80px 四方が目安です。
ファイルを差し替えると、更新日時を見て次の再描画で読み直します。
Claude を起動していない行、終了した行には出ません。`sidebar.showCustomMetadata` を切るとピルと一緒に消えます。
本家側の差し込みは `SidebarWorkspaceRowCellView.swift` の `// lawmux:` 5 行です。

### Shift+Space でアプリを呼び出す／戻る

本家の「Show/Hide All Windows」（システム全体のホットキー）の登録機構を使い、押したときの
動作だけ lawmux 専用の実装（`Sources/LawmuxGlobalHotkeyWindowMaximizer.swift` の
`LawmuxGlobalHotkey`）に差し替えています。権限は不要です。

- lawmux 以外が前面：そのアプリを記憶して lawmux を呼び出し、**マウスカーソルがある画面**で
  ウィンドウを画面いっぱいにします（2 画面でも、カーソル側に出ます）。ウィンドウは
  **今いる仮想デスクトップ**に出てきます（`.moveToActiveSpace`）。デスクトップは切り替わりません。
- lawmux が前面：記憶しておいたアプリに戻ります。記憶がなければ lawmux を隠します。

押したときの判断はログに残るので、挙動がおかしいときは次で確認できます。

```sh
log show --predicate 'subsystem == "com.lawrenceturnerw.lawmux"' --last 10m --style compact
```

本家は Command / Option / Control のいずれかを必須にしていて Shift+Space を受け付けないため、
lawmux ではその検証を Shift だけでも通るよう緩めています（`// lawmux:` の 2 か所）。
本家側の変更は、この 2 か所と `AppDelegate` のホットキー入口の数行だけです。

既定で有効で、キーも Shift+Space です（本家の既定は ⌘⌥⌃. で、フラグはオフ）。別の Mac でビルドしても
設定なしでそのまま使えます。変えたいときは設定 → Global Hotkey か、次の 2 つで上書きできます。

```sh
# ショートカット本体（~/.config/lawmux/cmux.json に書かれる）
/Applications/lawmux.app/Contents/Resources/bin/cmux config set shortcuts.bindings.showHideAllWindows '"shift+space"'
# 有効化フラグ（設定 → Global Hotkey → Enable System-Wide Hotkey と同じ）
defaults write com.lawrenceturnerw.lawmux systemWideHotkey.enabled -bool false
```

lawmux が起動していないときはホットキーは反応しません（アプリ内で登録しているため）。
Shift+Space は他のアプリでも lawmux に取られます。

## 本家の更新の取り込み

週に一度、GitHub Actions（`lawmux-upstream-check`）が本家の更新を確認し、
未取り込みのコミットがあれば Issue で知らせます。取り込みはローカルで行います。

```sh
./scripts/lawmux-sync-upstream.sh
```

本家から取り込んだ workflow は、同じ Actions が自動で無効にします。

`upstream` リモートは `main` だけを取得する設定にしておきます。本家にはブランチが大量にあり、
素の `git fetch upstream` が全ブランチを取りに行って長時間かかるためです（同期スクリプト自体は
`fetch upstream main` しかしません）。

```sh
git remote add -t main upstream https://github.com/manaflow-ai/cmux.git   # 新規 clone のとき
git config remote.upstream.fetch "+refs/heads/main:refs/remotes/upstream/main"  # 既存の clone を直すとき
```

### タグとバージョン

- 本家の `vX.Y.Z` タグは fork には写しません。同期スクリプトは `main` だけを取り込みます。
  本家のタグは本家のコミット（lawmux の変更なし）を指すので、lawmux のタグとしては意味がないためです。
- バージョン番号（`CFBundleShortVersionString`）は本家の `MARKETING_VERSION` をそのまま使います。
- 目印が欲しいときは、本家と衝突しない名前で `main` にタグを打ちます（例: `lawmux-v0.65.2`）。
  配布物はないので、タグに CI は要りません。
- About 画面の「ソースコード」リンクは、ビルドに埋め込まれたコミット（`Info.plist` の `CMUXCommit`）を
  指します。タグがなくても、そのビルドの正確なソースに飛びます。
