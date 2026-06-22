# Loop Engineering 🔄

**自律コーディングループ（Ralph Wiggum 手法）の汎用テンプレート**

AIエージェントによる自律的なコーディング→検証→コミットのループを、既存プロジェクトに簡単に導入できるテンプレート一式です。

> 設計原則の詳細は [Loop-engineering-template-guide.md](templates/Loop-engineering-template-guide.md) を参照してください。

## 概要

Loop Engineering は、以下のサイクルを自動で繰り返す仕組みです：

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│  1. AIエージェントがタスクを1つ選んで実装            │
│     ↓                                               │
│  2. バックプレッシャー（Lint → Build → Test）        │
│     ↓                                               │
│  3-a. 成功 → コミット＆タグ＆プッシュ → 1へ戻る     │
│  3-b. 失敗 → ロールバック or 人間の介入 → 1へ戻る   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## コアプリミティブ

本テンプレートは、ループシステムを構成する以下のプリミティブに対応しています：

| プリミティブ   | 対応ファイル              | 説明                               |
| :------------- | :------------------------ | :--------------------------------- |
| **自動化**     | `loop.bash`               | ループの自動実行・検証・Git操作    |
| **ワークツリー** | `loop.bash` (設定で有効化) | エージェントの作業領域を main から隔離 |
| **スキル**     | `SKILL.md`                | ビルド手順・規約の永続的な記録     |
| **状態の記録** | `AGENT.md`, `fix_plan.md` | エージェントの学習記録とタスク進捗 |

## ファイル構成と役割

```
your-project/
├── .loop/                           # Loop Engineering の全ファイル
│   ├── loop.bash                    # メインのループスクリプト
│   ├── loop.config.yaml             # 設定ファイル（言語・CLI・Git等）
│   ├── agent_prompt_template.md     # エージェントへのプロンプト
│   ├── SKILL.md                     # プロジェクトスキル定義（ビルド手順・規約）
│   ├── AGENT.md                     # エージェント学習記録（状態ファイル）
│   └── fix_plan.md                  # タスク計画書（状態ファイル）
└── specs/                           # 仕様書ディレクトリ（1機能1ファイル）
```

### 各ファイルの役割

| ファイル                        | 誰が管理        | 役割                                             |
| ---------------------------- | --------------- | ------------------------------------------------ |
| `.loop/loop.config.yaml`     | 👤 人間         | 言語・CLIツール・Git設定の一元管理               |
| `.loop/loop.bash`            | 👤 人間         | ループの実行制御・オーケストレーション           |
| `.loop/agent_prompt_template.md` | 👤 人間     | エージェントへのシステム指示・ルール定義         |
| `.loop/SKILL.md`             | 👤 人間         | プロジェクトのビルド手順・コーディング規約       |
| `.loop/AGENT.md`             | 🤖 エージェント | 発見したコマンド・過去のバグの教訓を記録         |
| `.loop/fix_plan.md`          | 🤖 エージェント | タスクの進捗を記録・更新                         |
| `specs/*`                    | 👤 人間         | 機能仕様書（エージェントが実装の指針として参照） |

## 導入ガイド

Loop Engineering の導入方法は2つあります。目的に応じて選んでください。

| パターン                        | ユースケース                                                 | 所要時間 |
| :------------------------------ | :----------------------------------------------------------- | :------- |
| **A. 既存プロジェクトに導入**   | すでにコードベースがあり、自律ループで開発を加速したい       | 約10分   |
| **B. 新規プロジェクトで始める** | ゼロからプロジェクトを立ち上げ、最初からループ駆動で開発する | 約15分   |

---

### パターン A: 既存プロジェクトに導入する

既存のコードベースに Loop Engineering を追加し、AIエージェントにタスクを自律実行させます。

#### ステップ 1: テンプレートをコピー

このリポジトリの `templates/` から、既存プロジェクトに必要なファイルをコピーします。

```bash
# このリポジトリをクローン（まだの場合）
git clone https://github.com/your-org/loop-engineering.git

# .loop/ ディレクトリごと既存プロジェクトにコピー
cd loop-engineering
cp -r templates/.loop /path/to/your-project/

# 仕様書ディレクトリを作成
mkdir -p /path/to/your-project/specs
```

#### ステップ 2: 設定ファイルを編集

プロジェクトのルートに移動し、言語・ビルドコマンド・CLIツールを設定します。

```bash
cd /path/to/your-project
```

`.loop/loop.config.yaml` を編集：

```yaml
project:
  name: "your-existing-project"
  description: "既存プロジェクトの説明"

agent:
  cli: "claude" # 使用するAIエージェント（gemini / claude / codex / copilot）

# 既存プロジェクトのビルド・テストコマンドをそのまま記入
backpressure:
  lint_command: "npm run lint" # 既存のリントコマンド
  build_command: "npm run build" # 既存のビルドコマンド
  test_command: "npm test" # 既存のテストコマンド
```

#### ステップ 3: SKILL.md にプロジェクト情報を記述

エージェントがプロジェクトの文脈を理解できるよう、既存のビルド手順や規約を記録します。

```markdown
# SKILL.md

## プロジェクト概要

- **プロジェクト名**: my-web-app
- **技術スタック**: TypeScript, React, Express, PostgreSQL
- **概要**: ユーザー管理機能を持つWebアプリケーション

## ビルド・テスト手順

npm ci # 依存関係のインストール
npm run build # ビルド
npm test # テスト

## 既知の注意点

- ESM環境のため、インポートには .js 拡張子が必須
- テストではPostgreSQLのDockerコンテナが必要
```

#### ステップ 4: 仕様書と計画を作成

```bash
# 既存の機能や改善点を仕様書として記述
vi specs/user-auth.md       # 例: 認証機能の仕様
vi specs/api-v2.md          # 例: API v2 の仕様

# 実装したいタスクをリストアップ
vi fix_plan.md
```

`fix_plan.md` の例：

```markdown
# Fix Plan

This is the state of our implementation.

- [ ] Implement user authentication with JWT [specs/user-auth.md] <!-- CURRENT TARGET -->
- [ ] Add rate limiting to API endpoints [specs/api-v2.md]
- [ ] Fix N+1 query in user listing endpoint

## Notes
```

#### ステップ 5: ループを実行

```bash
chmod +x .loop/loop.bash
./.loop/loop.bash
```

> **💡 ヒント**: 最初はテストが充実しているモジュールから始めると安全です。テストがバックプレッシャーとして機能し、エージェントの出力品質が担保されます。

---

### パターン B: 新規プロジェクトで始める

ゼロからプロジェクトを立ち上げ、最初からループ駆動で開発します。

#### ステップ 1: プロジェクトを初期化

```bash
# プロジェクトディレクトリを作成
mkdir my-new-project && cd my-new-project
git init

# プロジェクトの基盤を作成（言語に応じて）
# Node.js の場合:
npm init -y

# Python の場合:
# python -m venv .venv && source .venv/bin/activate && pip install pytest

# Rust の場合:
# cargo init
```

#### ステップ 2: Loop Engineering テンプレートをコピー

```bash
# このリポジトリから .loop/ ディレクトリをコピー
cp -r /path/to/loop-engineering/templates/.loop ./

# 仕様書ディレクトリとログ除外を設定
mkdir -p specs
echo ".loop/.loop-logs/" >> .gitignore
echo ".loop-work/" >> .gitignore
```

#### ステップ 3: 仕様書を先に書く（重要）

> **⚠️ 新規プロジェクトでは、コードの前に仕様書を書くことが最も重要です。**
> エージェントは仕様書（`specs/`）を実装の指針として使います。仕様が曖昧だと、エージェントの出力も曖昧になります。

仕様書は「1機能1ファイル」で作成します：

```bash
vi specs/core-data-model.md   # データモデルの仕様
vi specs/auth.md               # 認証の仕様
vi specs/api-endpoints.md      # APIエンドポイントの仕様
```

仕様書の例（`specs/core-data-model.md`）：

```markdown
# Core Data Model

## User

- id: UUID (auto-generated)
- email: string (unique, required)
- name: string (required)
- created_at: timestamp

## Constraints

- Email must be valid format
- Name must be 1-100 characters
- Soft delete (is_deleted flag, not actual deletion)
```

#### ステップ 4: 設定ファイルとSKILL.mdを編集

`loop.config.yaml`：

```yaml
project:
  name: "my-new-project"
  description: "新規プロジェクトの説明"

agent:
  cli: "gemini" # 使用するAIエージェント

backpressure:
  lint_command: "npm run lint"
  build_command: "npm run build"
  test_command: "npm test"
```

`SKILL.md` にプロジェクトの技術スタックとコーディング規約を記述します。

#### ステップ 5: 計画を作成してループを開始

`fix_plan.md`：

```markdown
# Fix Plan

This is the state of our implementation.

- [ ] Set up project structure and configuration [specs/core-data-model.md] <!-- CURRENT TARGET -->
- [ ] Implement core data models [specs/core-data-model.md]
- [ ] Implement authentication module [specs/auth.md]
- [ ] Implement API endpoints [specs/api-endpoints.md]
- [ ] Add integration tests

## Notes
```

```bash
# 初回コミットを作成（エージェントがベースラインとして使用）
git add -A
git commit -m "initial: Loop Engineering テンプレートを配置"

# ループを開始
chmod +x .loop/loop.bash
./.loop/loop.bash
```

> **💡 ヒント**: 新規プロジェクトでは、最初のタスクをプロジェクト基盤のセットアップ（ディレクトリ構成、設定ファイル、CI設定等）にすると、以降のタスクでエージェントが一貫した構造で作業できます。

## 設定リファレンス

### `loop.config.yaml` の全項目

| セクション     | キー                    | 型     | デフォルト                   | 説明                                                    |
| -------------- | ----------------------- | ------ | ---------------------------- | ------------------------------------------------------- |
| `project`      | `name`                  | string | `"my-project"`               | プロジェクト名                                          |
| `project`      | `description`           | string | `""`                         | プロジェクトの説明                                      |
| `agent`        | `cli`                   | string | `"gemini"`                   | 使用するCLI: `gemini` / `claude` / `copilot` / `custom` |
| `agent`        | `custom_command`        | string | `""`                         | カスタムCLI使用時のコマンド                             |
| `agent`        | `prompt_file`           | string | `"agent_prompt_template.md"` | プロンプトテンプレートファイルのパス                    |
| `skills`       | `skill_file`            | string | `"SKILL.md"`                 | プロジェクトスキル定義ファイルのパス                    |
| `backpressure` | `lint_command`          | string | `""`                         | リントコマンド（空でスキップ）                          |
| `backpressure` | `build_command`         | string | `""`                         | ビルドコマンド（空でスキップ）                          |
| `backpressure` | `test_command`          | string | `""`                         | テストコマンド（空でスキップ）                          |
| `git`          | `commit_prefix`         | string | `"auto: loop"`               | コミットメッセージのプレフィックス                      |
| `git`          | `branch`                | string | `"main"`                     | プッシュ先ブランチ                                      |
| `git`          | `auto_tag`              | bool   | `true`                       | 自動タグ付けの有効/無効                                 |
| `git`          | `initial_tag`           | string | `"0.0.0"`                    | タグの初期値                                            |
| `loop`         | `interval`              | int    | `5`                          | ループ間隔（秒）                                        |
| `loop`         | `max_iterations`        | int    | `0`                          | 最大ループ回数（0=無制限）                              |
| `loop`         | `auto_reset_on_failure` | bool   | `false`                      | 失敗時に自動リセットするか                              |
| `worktree`     | `enabled`               | bool   | `false`                      | ワークツリーの有効/無効                                |
| `worktree`     | `directory`             | string | `".loop-work"`               | ワークツリーのディレクトリ名                        |
| `worktree`     | `branch`                | string | `"loop-auto"`                | ワークツリー用ブランチ名                              |

### 言語別プリセット

<details>
<summary>🦀 Rust</summary>

```yaml
backpressure:
  lint_command: "cargo clippy -- -D warnings"
  build_command: "cargo build"
  test_command: "cargo test"
```

</details>

<details>
<summary>📦 Node.js / TypeScript</summary>

```yaml
backpressure:
  lint_command: "npm run lint"
  build_command: "npm run build"
  test_command: "npm test"
```

</details>

<details>
<summary>🐍 Python</summary>

```yaml
backpressure:
  lint_command: "ruff check ."
  build_command: ""
  test_command: "pytest"
```

</details>

<details>
<summary>🐹 Go</summary>

```yaml
backpressure:
  lint_command: "golangci-lint run"
  build_command: "go build ./..."
  test_command: "go test ./..."
```

</details>

## 対応AIエージェントCLI

| CLI                                                           | 設定値    | インストール                               | 備考                                          |
| ------------------------------------------------------------- | --------- | ------------------------------------------ | --------------------------------------------- |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli)     | `gemini`  | `npm install -g @google/gemini-cli`        | `--prompt` フラグでプロンプトを渡す           |
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `claude`  | `npm install -g @anthropic-ai/claude-code` | `--print` フラグでワンショット実行            |
| [Codex CLI](https://github.com/openai/codex)                  | `codex`   | `npm install -g @openai/codex`             | `codex exec` で非インタラクティブ実行         |
| [GitHub Copilot CLI](https://docs.github.com/en/copilot)      | `copilot` | `gh extension install github/gh-copilot`   | `gh copilot suggest` で実行                   |
| カスタム                                                      | `custom`  | —                                          | `agent.custom_command` に任意のコマンドを設定 |

## 3大鉄則

本テンプレートは以下の設計原則に基づいています：

1. **スタックの決定的な割り当て** — 毎ループ開始時に `fix_plan.md` + `specs/` + `AGENT.md` + `SKILL.md` を確定的にロード
2. **メインコンテキストはスケジューラーに徹する** — 実装・検索はサブエージェントに委譲し、コンテキストウィンドウの消費を抑制
3. **1ループ1タスク** — 1回のイテレーションで処理するタスクは厳密に1つだけ

## 運用上の注意（Human in the Loop）

- **検証責任は人間にある**: 自動テストが通っても、「完了」はエージェントの自己申告。最終確認は常に人間の責任。
- **「理解の衰退」の回避**: ループが高速にコードを生成するため、人間は定期的に生成コードをレビューする義務がある。
- **「認知の降伏」の拒絶**: エージェントの提案を盲信せず、人間が最終的な品質をコントロールし続ける。

## 前提条件

- **必須**: Bash 4.0 以上、Git
- **推奨**: [yq](https://github.com/mikefarah/yq)（YAML パーサー。なくても動作しますが堅牢性向上）
- **いずれか1つ**: 上記の AI エージェント CLI ツール

## トラブルシューティング

### Q: `yq` がインストールされていないと表示される

`loop.bash` は `yq` がなくても動作しますが、複雑な YAML 構造の場合は誤読する可能性があります。

```bash
# macOS
brew install yq

# Linux
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq
```

### Q: テストが失敗してループが止まる

`loop.config.yaml` の `loop.auto_reset_on_failure` を `true` に設定すると、テスト失敗時に自動で `git reset --hard` してリトライします（注意: 変更はすべて破棄されます）。

### Q: エージェントがコンテキストウィンドウを使い切る

ループを停止し、`fix_plan.md` を見直してタスクを小さく分割してください。エージェントに渡すコンテキスト（`specs/` 内のファイル数）を減らすことも有効です。

### Q: プロンプトをカスタマイズしたい

`agent_prompt_template.md` を直接編集してください。スクリプトの変更は不要です。

### Q: ループを途中で安全に止めたい

`Ctrl+C` で停止できます。未コミットの変更は残りますので、`git status` で確認してください。

## ライセンス

MIT
