**自律的なコーディングエージェントを最大限に活用し、自分自身の代わりにエージェントへプロンプトを送り続けるシステム（ループ）を1から構築するための、体系的な情報をまとめたテンプレートガイドです。**

---

# ループエンジニアリング構築テンプレート・ガイド

ループエンジニアリングとは、開発者がエージェントを都度プロンプトするのをやめ、**エージェントを自律的にプロンプトして反復・完了させるシステムそのものを設計すること**を指します。

本ガイドは、モノリシックなアプローチ（単一リポジトリ、単一プロセスで1ループ1タスクを処理する構造）を前提に、1から自律ループシステム（テンプレート）を構築するための構成要素、原則、およびプロンプトとスクリプトのひな形を提供します。

---

## 1. ループシステムを構成する「6つのコア・プリミティブ」

理想的なループシステムは、以下の5つの機能部品（プリミティブ）と、1つの永続的な外部メモリ（状態）で構成されます。

| プリミティブ                                | ループ内での役割                                                                                                                   | 具体的な実装手段・ツール例                                                      |
| :------------------------------------------ | :--------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------ |
| **1. 自動化<br>(Automations)**              | 定期的な起動、課題の自動発見とトリアージ、完了条件（`/goal`）までの自律反復。                                                      | GitHub Actions, cron, lifecycle hooks, `/loop` または `/goal` コマンド          |
| **2. ワークツリー<br>(Worktrees)**          | 複数の並行エージェント間のファイル衝突（Mechanical collision）を回避するための、個別作業領域の隔離。                               | `git worktree`, `isolation: worktree` 設定, `--worktree` フラグ                 |
| **3. スキル<br>(Skills)**                   | プロジェクト独自のコンテキスト、ビルド手順、過去のバグの教訓（規約）を記録し、エージェントが毎回ゼロからルールを憶測するのを防ぐ。 | リポジトリ内の `SKILL.md`（必要に応じてスクリプトや資産を同梱）                 |
| **4. コネクター<br>(Plugins / Connectors)** | ファイルシステムを超えて、外部のイシュートラッカー、データベース、Slack等の通信ツールと接続する。                                  | MCP（Model Context Protocol）サーバー、各種ツールのプラグイン                   |
| **5. サブエージェント<br>(Sub-agents)**     | コードを実装する側（Maker）と、それを検証する側（Checker）で、役割やプロンプト指示、モデルを分割する。                             | TOML等で定義された専門エージェント群（`.claude/agents/` などのチーム構成）      |
| **6. 状態の記録<br>(State)**                | エージェントがセッション間で記憶を失うため、進捗や計画をコンテキストの外（ディスク上）に記録して永続化する。                       | ディスク上のMarkdownファイル（`@fix_plan.md`, `@AGENT.md`）、またはLinearボード |

---

## 2. ループテンプレート設計の「3大鉄則」

### ① スタックの決定的な割り当て（Allocate the Stack）

エージェントは毎回「冷え切ったコンテキスト」で起動します。そのため、各ループの開始時には**計画書（`@fix_plan.md`）と仕様書（`specs/`）という同一のコンテキストスタックを必ず確定的にロード**させ、前回の状態をシームレスに引き継がせます。

### ② メインコンテキストは「スケジューラー」に徹する（Extend Context Window）

LLMの性能はコンテキストウィンドウの消費に伴い、約150kトークン付近（147k〜152k付近）でクリッピング（出力品質の低下）を起こします。
これを防ぐため、メインエージェント自身にファイルの書き換えやログの要約などの高コストな割り当て（アロケーション）作業を直接行わせてはいけません。メインエージェントは司令塔（スケジューラー）に徹し、**実際の探索や実装、要約作業はサブエージェント（Sub-agents）をフォークして実行**させます。

- **探索・書き込み**: 複数のサブエージェントを並列で実行可能にして高速化。
- **検証（ビルド/テスト）**: 並列で実行すると競合や不要な情報（逆圧）が押し寄せる（bad form back pressure）ため、必ず**「1つのサブエージェント」**のみに実行・評価を制限する。

### ③ 1ループにつき、タスクは厳密に「1つ」（One Item per Loop）

ループ内の複雑性を極限まで下げるため、1回の反復処理（1ループ）で処理させるタスクは**「厳密に1つ」**に絞ります。一度に複数のことを行わせようとすると、非決定的なエラーを招きシステムが脱線します。

---

## 3. 1から構築するループエンジニアリング・テンプレート

以下は、自律リポジトリ内に構築すべきファイル構造と、ループを実行するための具体的なプロンプト・スクリプトのテンプレートです。

### 📁 推奨されるファイル構造

```text
your-repo/
├── specs/                   # 1機能1ファイルの形式で記述された仕様書
│   ├── auth.md
│   └── stdlib/
│       └── core_helper.md
├── .claude/agents/          # サブエージェントの定義（TOML等）
├── SKILL.md                 # プロジェクトのビルド手順や規約（Skills）
├── @fix_plan.md             # 状態：エージェントが更新する優先度付きTODOリスト
├── @AGENT.md                # 状態：エージェントが学習したビルド手順・コマンド記録
└── loop.sh                  # 最小限の自動検証Bashスクリプト
```

### 📝 1. 状態ファイルのテンプレート（`@fix_plan.md`）

エージェントがチェックボックスを更新し、進捗をディスク上に記録するためのファイルです。

```markdown
# Project Fix Plan

This is the state of our implementation. The scheduler agent and sub-agents will update this file at the end of every loop when tests pass.

- [x] Implement core lexer specifications [specs/lexer.md] (Completed in v0.0.1)
- [ ] Implement missing standard library authentication module [specs/stdlib/auth.md] <!-- CURRENT TARGET -->
- [ ] Implement database connector schema verification [specs/database.md]
- [ ] Resolve any TODOs or placeholders found in src/\*
```

### 📝 2. エージェント起動時の「スタック・プロンプトテンプレート」

ループ開始時に、メインエージェント（スケジューラー）にロードさせるプロンプトの記述例です。

```text
================================================================================
ROLE & SYSTEM INSTRUCTIONS
================================================================================
You are the monolithic controller of the autonomous building loop.
Your primary job is to coordinate and schedule work without saturating your primary context window.
You must delegate expensive tasks (searching, file editing) to parallel sub-agents.

================================================================================
DETERMINISTIC CONTEXT STACK
================================================================================
1. Current Plan: Study @fix_plan.md to understand the current goals and past completions.
2. Specifications: Study all files under @specs/* to guide your technical implementation patterns.
3. Learnt Agent Rules: Study @AGENT.md to recall correct compiler/build commands.

================================================================================
CORE RULE & STOPPING CONDITION
================================================================================
- Execute ONE ITEM from the @fix_plan.md per loop. Choose the most important pending item.
- BEFORE MAKING CHANGES: Search the codebase using parallel sub-agents. DO NOT assume an item is not implemented. Nondeterministic search can fail—think hard and double check.
- NO CHEATING: Do NOT write placeholders, mock outputs, or simple/minimal implementations. We want FULL and complete implementations as per the specs folder. DO NOT IMPLEMENT PLACEHOLDERS OR I WILL YELL AT YOU.
- BACKPRESSURE VALIDATION: After making changes, spin up exactly 1 single sub-agent to run tests and build verification. Do not fan out multiple sub-agents for test/build tasks (to avoid bad form back pressure).
- CAPTURE TEST MOTIVATION: When writing tests, always capture the "why" (the motivation and business logic) behind the test in code comments or docstrings. This serves as instructions for future loops so they won't mistakenly delete or modify the verification.
- ERROR LOGGING: If compilation fails, you may add extra logging to find the root cause, and auto-debug via loopback.
- LEARNING PERSISTENCE: If you discover a new, correct way to run commands or run tests, update @AGENT.md using a brief sub-agent call. Do not repeat previous command-line mistakes.
- COMMIT & TAG: Once all tests pass, update @fix_plan.md (marking the target item as complete), stage all changes, commit them with a meaningful descriptive message, push to the remote repository, and increment the git patch version tag (e.g. 0.0.1 -> 0.0.2).
================================================================================
```

### 📝 3. 最小限の自動検証「Bashループスクリプト」（`loop.sh`）

エージェントを自動で回し続け、成果物をGitでセーブポイント化するための、Ralph Wiggumスタイルの最小限のスクリプトです。

```bash
#!/bin/bash
# 最小限の自律ループスクリプト (Based on Ralph Wiggum Technique)

set -u

# ループの実行制限やAPIコスト制御のために、手動で割り込めるように待機を挟む
INTERVAL=5

while true; do
    echo "=================================================="
    echo "🤖 [NEW LOOP] ループプロセスを開始します..."
    echo "=================================================="

    # エージェントCLIの実行（使用ツールに応じてコマンドを変更してください）
    # 決定的なコンテキストスタックの指示をプロンプトで渡し、1タスクを実行させる
    agent-cli --prompt-file ./agent_prompt_template.txt

    # バックプレッシャー：テストとビルドによる自動評価
    echo "⚙️  バックプレッシャーの印加：テストを実行中..."
    npm test # プロジェクト環境に合わせたテストコマンド（cargo test, pytest 等）
    TEST_RESULT=$?

    if [ $TEST_RESULT -eq 0 ]; then
        echo "✅ 検証に成功しました。Git自動化処理に移行します。"

        # 成果物の保存と、状態のコミット＆プッシュ
        git add -A
        git commit -m "auto(loop): implemented increment and updated fix_plan.md"
        git push origin main

        # バージョンタグの自動的なインクリメント（0.0.0ベース）
        LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
        if [ -z "$LATEST_TAG" ]; then
            NEW_TAG="0.0.0"
        else
            BASE=$(echo "$LATEST_TAG" | cut -d. -f1-2)
            PATCH=$(echo "$LATEST_TAG" | cut -d. -f3)
            NEW_TAG="$BASE.$((PATCH + 1))"
        fi

        git tag "$NEW_TAG"
        git push origin "$NEW_TAG"
        echo "🎉 バージョン $NEW_TAG をプッシュしました。次のタスクへ移行します。"

    else
        echo "❌ 検証（ビルド/テスト）に失敗しました。"
        echo "エージェントが自力で解決できない状態（デバッグの迷走）に陥っている可能性があります。"

        # 人間のレビューおよび判断の介入
        read -p " git reset --hard を実行してループを今回の開始前まで差し戻しますか？ (y/n): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            git reset --hard HEAD
            echo "リポジトリを以前の安定コミットまでリセットしました。プロンプトをチューニングして再実行してください。"
        else
            echo "手動修正のため、ループを一時的に停止します。"
            break
        fi
    fi

    echo "次のループ開始まで ${INTERVAL}秒 待機します..."
    sleep $INTERVAL
done
```

---

## 4. 運用上の注意点と人間の意思決定（Human in the Loop）

- **検証責任は人間にある**:
  自動検証（テスト、型システム、静的解析）を配線しても、「完了した」というエージェントの主張はあくまで自己申告であり、証明ではありません。最終的にコードが本当に正常動作するか確認する責任は常に人間にあります。
- **「理解の衰退（Comprehension debt）」の回避**:
  ループがコードを自律的かつ超高速で生成するため、コードベースと開発者自身の理解に大きな乖離が生まれやすくなります。これを防ぐため、人間は定期的にループが生成したコードやテストを読む義務があります。
- **「認知の降伏（Cognitive surrender）」の拒絶**:
  システムが勝手に動くからといって、エージェントの提案を盲信し、思考を放棄してはいけません。ループは開発を加速させる「エンジニアの梃子（レバレッジ）」であり、人間が最終的な品質をコントロールし続ける必要があります。

---

👉 この自律ループをプロジェクトに配線する前に、既存コードベースを汚さないための「仕様書（Specs）を設計する最初の対話プロンプト」を試してみますか？
