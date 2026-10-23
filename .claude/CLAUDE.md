# lawmux（この fork）での作業ルール

このリポジトリは manaflow-ai/cmux の個人 fork「lawmux」です。lawmux で動くエージェントは
**このファイルを一次のルール**として扱います。詳細は [LAWMUX.md](../LAWMUX.md)。

## 本家の CLAUDE.md との関係

- ルート直下の `CLAUDE.md`（`AGENTS.md` はそのシンボリックリンク）と `skills/` は本家
  manaflow-ai/cmux のものをそのまま取り込んでいて、lawmux では書き換えません。本家チーム向けの
  手順・方針なので、**本家の情報として参照するだけ**にし、lawmux での作業はこのファイルに従います。
  両方に書いてあることが食い違ったら、このファイルが優先です。
- 本家の `CLAUDE.md` のうち、lawmux では当てはまらない項目:
  - fleet ビルド、cmuxterm-hq へのリンク、`dev-build` ラベル、`full-ci`。lawmux では本家 CI も fleet も動かしていない。
  - `gh-merge-green` や review subagent 必須のマージ手順。fork の PR はユーザーが動作確認してから
    `gh pr merge` する（下の「ブランチ運用」）。
  - タグ付き Debug ビルド必須・素の `xcodebuild` 禁止。lawmux では `scripts/lawmux-build-release.sh` を使う。
  - 「本家の open PR を先に探して載せる」「PR を manaflow-ai/cmux に出す」。lawmux の変更は
    `LawrenceTurnerW/lawmux` に PR を出す。本家に出すのは、本家向けにわざわざ作った変更のときだけ。
  - `web/`、`workers/`、`services/` などサーバー側の手順。lawmux では使わない。
- 本家の `CLAUDE.md` でそのまま役に立つもの: skills の対応表（アーキテクチャ、デバッグ、
  ローカライズ、テスト配線、ショートカット）、`scripts/verify-local.py`、`STYLE.md`、
  「ユーザーが使っている `/Applications/cmux.app`（`com.cmuxterm.app`）を絶対に終了・置き換えしない」。
- この checkout が lawmux かどうかは `CMUX_BUNDLE_ID` で分かる（`com.lawrenceturnerw.lawmux` なら
  lawmux の中で動いている）。
- 本家由来のファイルが lawmux で読み込まれるのは仕方がないが、fork 側のルールは本家が持たない
  この `.claude/CLAUDE.md` にだけ書き、本家の `CLAUDE.md` には足さない（毎週の取り込みで衝突するため）。

## 改造の方針

- 本家の更新を取り込み続けるので、変更は最小限にする。許されるのは
  (1) 定数の差し替え（`// lawmux:` コメントを付ける）、(2) `lawmux-*` という名前の新規ファイル。
- 使わない機能やディレクトリを削除しない。本家のテスト、workflow、`scripts/reload*.sh`、
  README の多言語版は触らない。本家のテストが lawmux で一部失敗するのは想定内。
- `web/`、`workers/`、`services/` などの BUSL ディレクトリは触らない（lawmux では使わない）。

## ビルドと確認

- 変更後は `python3 scripts/verify-local.py` を通す。Release ビルドと入れ替えは、ユーザーが頼んだとき、
  または自分の Swift 変更の動作を見せる必要があるときだけ行う。本家の取り込み後は verify-local まで
  通して報告すれば十分で、ビルドを自分から始めない（10 分以上かかり、lawmux の中から走らせることになる）。
- Release ビルドと `/Applications/lawmux.app` への入れ替えは
  `./scripts/lawmux-build-release.sh --install --open`。この fork では素の `xcodebuild`
  （このスクリプト経由）を使ってよい。本家の `reload.sh --launch` はチーム認証が要るので使えない。
- 自分（Claude）が lawmux の中で動いているときは必ず `--detach` を付ける
  （`CMUX_BUNDLE_ID` が `com.lawrenceturnerw.lawmux` なら lawmux の中）。lawmux の終了で
  自分のシェルも落ちるので、終了・入れ替え・再起動は切り離したプロセスに任せ、
  再起動後にセッション復元で戻ってきてから続きをやる。ログは DerivedData の `lawmux-install.log`。
- 入れ替えを頼まれたら、ユーザーに頼み返さず自分で実行する。専用のワークスペースを CLI で作って、その中で走らせる:
  `cmux workspace create --cwd ~/Work/lawmux --command "./scripts/lawmux-build-release.sh --install --open --detach"`。
  復元で戻ってきたら、そのワークスペースを閉じる。再起動で ref（`workspace:…`）は振り直されるので、
  `--name "lawmux install"` を付けて作り、`cmux workspace list` のタイトルで探して `cmux workspace close --workspace <ref> --force`。
- `/Applications/cmux.app`（`com.cmuxterm.app`）は本家のアプリで、ユーザーが使っている。
  絶対に終了・置き換えしない。lawmux（`com.lawrenceturnerw.lawmux`）の終了は作業上必要なら行ってよい。

## ブランチ運用

- コミットの author / committer は GitHub の noreply アドレス
  （`LawrenceTurnerW <46259390+LawrenceTurnerW@users.noreply.github.com>`）。この checkout の
  `git config user.email` に設定済み。会社メールを公開履歴に残さない。
- 機能追加・修正は `feature/<name>` ブランチで作業し、push して PR を作る。ユーザーが動作確認
  したあとにマージする（`gh pr merge --merge --delete-branch`）。
- 積み重ねた PR（base が別の feature ブランチ）は、下の PR をマージする前に
  `gh pr edit <n> --base main` で上の PR のベースを付け替える。付け替えずに `--delete-branch` で
  マージすると、上の PR は再オープンできない形で自動クローズされる（#5 で発生）。
- `gh pr create` は必ず `--repo LawrenceTurnerW/lawmux --base main` を付ける。fork なので、
  付け忘れると本家 manaflow-ai/cmux に PR が立ってしまう。保険として `.claude/settings.json` の
  `GH_REPO` が gh の向き先を fork に固定し、ユーザー側のグローバル hook（gh-fork-guard）が
  fork checkout での `--repo` なし書き込みコマンドを実行前に拒否する。
- 本家向けの PR（例: #23657 `sidebar.hiddenStatusKeys`）は `upstream/main` から切ったブランチで作り、
  本家の CLAUDE.md の手順（test → fix の順、`### Observed / Not run`、Changelog 行）に従う。
  本家側のマージはメンテナ待ちで、こちらからは `gh-merge-green` も API マージも使わない。
- `main` に直接 push してよいのは、本家の取り込み（`scripts/lawmux-sync-upstream.sh`）と
  ドキュメントの軽微な修正だけ。
- PR 本文の末尾に `🤖 Generated with [Claude Code](https://claude.com/claude-code)` を付ける。

## 本家の取り込み

- `./scripts/lawmux-sync-upstream.sh`（Issue「upstream updates pending」が合図）。push はユーザーに任せる。
- `upstream` は `main` だけ fetch する（refspec を main に固定済み）。素の `git fetch upstream` を全ブランチで
  走らせない。本家の main が壊れていてビルドが通らないときは、最小の修正を `// lawmux:` 付きで当てて進める。
- `verify-local.py` の `swift-syntax` は選ばれた Swift ファイルを 1 回の `swiftc -parse` にまとめるので、
  トップレベル文を持つ本家のスクリプト（`scripts/ci/pr_media_ocr.swift` など）が他のファイルと一緒に
  選ばれると落ちる。単体で通れば取り込みの問題ではない。
- 本家のタグは写さない。lawmux のタグは `lawmux-vX.Y.Z`。
