#!/bin/bash
# ============================================================
# Loop Engineering - 自律コーディングループスクリプト
# ============================================================
# Ralph Wiggum 手法に基づく自律コーディングループの汎用実装。
# loop.config.yaml の設定を読み込み、以下のサイクルを繰り返す：
#   1. AIエージェントによるタスク実行
#   2. バックプレッシャー（lint → build → test）
#   3. 成功時: コミット＆タグ＆プッシュ → 次のループ
#      失敗時: ロールバックまたは停止
#
# 使い方: ./loop.bash [設定ファイルのパス]
#   デフォルトは ./loop.config.yaml
# ============================================================

set -euo pipefail

# -----------------------------------------------------------
# 定数
# -----------------------------------------------------------
# SCRIPT_DIR: loop.bash が置かれているディレクトリ（.loop/）
# PROJECT_ROOT: プロジェクトのルートディレクトリ（SCRIPT_DIR の親）
# なぜ分離するか: .loop/ ディレクトリに配置する設計で、
# Git操作やエージェント実行はプロジェクトルートで行う必要があるため。
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly DEFAULT_CONFIG="${SCRIPT_DIR}/loop.config.yaml"
readonly LOG_DIR="${SCRIPT_DIR}/.loop-logs"

# -----------------------------------------------------------
# ログ関数
# -----------------------------------------------------------
# タイムスタンプ付きのログをコンソールとファイルの両方に出力する
log() {
    local level="$1"
    shift
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local message="[${timestamp}] [${level}] $*"
    echo "$message"
    echo "$message" >> "${LOG_FILE}"
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }
log_ok()    { log "OK"    "$@"; }

# -----------------------------------------------------------
# YAML 簡易パーサー
# -----------------------------------------------------------
# yq が利用可能ならそちらを使い、なければ grep/sed で代替する。
# ネストは1階層（parent.child 形式）のみ対応。
#
# なぜ yq フォールバックが必要か:
#   yq はすべての環境にインストールされているわけではなく、
#   テンプレートの可搬性を優先するため簡易パーサーを用意している。
yaml_get() {
    local file="$1"
    local key="$2"
    local default="${3:-}"

    # yq が利用可能な場合は yq を使う（より堅牢）
    if command -v yq &> /dev/null; then
        local value
        value="$(yq eval ".${key}" "$file" 2>/dev/null)"
        if [ "$value" = "null" ] || [ -z "$value" ]; then
            echo "$default"
        else
            echo "$value"
        fi
        return
    fi

    # フォールバック: grep/sed による簡易パース
    # "parent.child" 形式のキーを分解して検索する
    local parent child
    if [[ "$key" == *.* ]]; then
        parent="$(echo "$key" | cut -d. -f1)"
        child="$(echo "$key" | cut -d. -f2-)"
    else
        parent=""
        child="$key"
    fi

    local value
    if [ -n "$parent" ]; then
        # 親セクション配下から子キーを検索
        value="$(awk -v parent="$parent" -v child="$child" '
            BEGIN { in_section = 0 }
            # 親セクションの開始を検出
            $0 ~ "^" parent ":" { in_section = 1; next }
            # 別のトップレベルキーに到達したらセクション終了
            in_section && /^[a-zA-Z]/ { in_section = 0 }
            # セクション内で子キーを検索
            in_section && $0 ~ "^[[:space:]]+" child ":" {
                # 値部分を抽出（クォートを除去）
                sub(/^[[:space:]]*[a-zA-Z_]+:[[:space:]]*/, "")
                gsub(/^["'\'']|["'\'']$/, "")
                print
                exit
            }
        ' "$file")"
    else
        # トップレベルキーを直接検索
        value="$(grep -E "^${child}:" "$file" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^["'\'']\|["'\'']$//g')"
    fi

    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# -----------------------------------------------------------
# 設定の読み込み
# -----------------------------------------------------------
load_config() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        log_error "設定ファイルが見つかりません: ${config_file}"
        log_error "loop.config.yaml を作成してください。テンプレートは templates/ にあります。"
        exit 1
    fi

    log_info "設定ファイルを読み込み中: ${config_file}"

    # プロジェクト情報
    PROJECT_NAME="$(yaml_get "$config_file" "project.name" "unnamed-project")"

    # エージェント設定
    AGENT_CLI="$(yaml_get "$config_file" "agent.cli" "gemini")"
    AGENT_CUSTOM_CMD="$(yaml_get "$config_file" "agent.custom_command" "")"
    AGENT_PROMPT_FILE="$(yaml_get "$config_file" "agent.prompt_file" "agent_prompt_template.md")"

    # スキル定義
    SKILL_FILE="$(yaml_get "$config_file" "skills.skill_file" "SKILL.md")"

    # バックプレッシャー設定
    LINT_COMMAND="$(yaml_get "$config_file" "backpressure.lint_command" "")"
    BUILD_COMMAND="$(yaml_get "$config_file" "backpressure.build_command" "")"
    TEST_COMMAND="$(yaml_get "$config_file" "backpressure.test_command" "")"

    # Git設定
    GIT_COMMIT_PREFIX="$(yaml_get "$config_file" "git.commit_prefix" "auto: loop")"
    GIT_BRANCH="$(yaml_get "$config_file" "git.branch" "main")"
    GIT_AUTO_TAG="$(yaml_get "$config_file" "git.auto_tag" "true")"
    GIT_INITIAL_TAG="$(yaml_get "$config_file" "git.initial_tag" "0.0.0")"

    # ループ設定
    LOOP_INTERVAL="$(yaml_get "$config_file" "loop.interval" "5")"
    LOOP_MAX_ITERATIONS="$(yaml_get "$config_file" "loop.max_iterations" "0")"
    LOOP_AUTO_RESET="$(yaml_get "$config_file" "loop.auto_reset_on_failure" "false")"

    # ワークツリー設定
    WORKTREE_ENABLED="$(yaml_get "$config_file" "worktree.enabled" "false")"
    WORKTREE_DIR="$(yaml_get "$config_file" "worktree.directory" ".loop-work")"
    WORKTREE_BRANCH="$(yaml_get "$config_file" "worktree.branch" "loop-auto")"

    log_info "プロジェクト: ${PROJECT_NAME}"
    log_info "エージェントCLI: ${AGENT_CLI}"
    log_info "プロンプトファイル: ${AGENT_PROMPT_FILE}"
    log_info "スキルファイル: ${SKILL_FILE}"
    log_info "テストコマンド: ${TEST_COMMAND:-（なし）}"
    if [ "$WORKTREE_ENABLED" = "true" ]; then
        log_info "ワークツリー: 有効 (${WORKTREE_DIR} / ${WORKTREE_BRANCH})"
    fi
}

# -----------------------------------------------------------
# AIエージェントの実行
# -----------------------------------------------------------
# 設定された CLI ツールに応じてエージェントを呼び出す。
# 各ツールのプロンプト渡し方の違いを吸収する。
run_agent() {
    local prompt="$1"

    log_info "AIエージェントを起動中 (${AGENT_CLI})..."

    case "${AGENT_CLI}" in
        gemini)
            # Gemini CLI: --prompt フラグでプロンプトを渡す
            gemini --prompt "$prompt"
            ;;
        claude)
            # Claude Code: --print フラグでワンショット実行
            claude --print "$prompt"
            ;;
        codex)
            # OpenAI Codex CLI: exec サブコマンドで非インタラクティブ実行
            codex exec "$prompt"
            ;;
        copilot)
            # GitHub Copilot CLI
            gh copilot suggest "$prompt"
            ;;
        custom)
            if [ -z "$AGENT_CUSTOM_CMD" ]; then
                log_error "カスタムCLIが指定されていません（agent.custom_command を設定してください）"
                return 1
            fi
            # カスタムコマンド: $PROMPT 変数でプロンプトを渡す
            PROMPT="$prompt" eval "$AGENT_CUSTOM_CMD"
            ;;
        *)
            log_error "未知のエージェントCLI: ${AGENT_CLI}"
            log_error "対応ツール: gemini, claude, codex, copilot, custom"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------
# バックプレッシャー（検証パイプライン）
# -----------------------------------------------------------
# lint → build → test の順に実行する。
# どのステップで失敗したかを明示して戻り値で返す。
#
# 戻り値:
#   0 = すべて成功
#   1 = lint 失敗
#   2 = build 失敗
#   3 = test 失敗
run_backpressure() {
    # ステップ 1: Lint
    if [ -n "$LINT_COMMAND" ]; then
        log_info "=== Lint を実行中: ${LINT_COMMAND} ==="
        if ! eval "$LINT_COMMAND"; then
            log_error "Lint が失敗しました"
            return 1
        fi
        log_ok "Lint 通過"
    fi

    # ステップ 2: Build
    if [ -n "$BUILD_COMMAND" ]; then
        log_info "=== Build を実行中: ${BUILD_COMMAND} ==="
        if ! eval "$BUILD_COMMAND"; then
            log_error "Build が失敗しました"
            return 2
        fi
        log_ok "Build 通過"
    fi

    # ステップ 3: Test
    if [ -n "$TEST_COMMAND" ]; then
        log_info "=== Test を実行中: ${TEST_COMMAND} ==="
        if ! eval "$TEST_COMMAND"; then
            log_error "Test が失敗しました"
            return 3
        fi
        log_ok "Test 通過"
    fi

    return 0
}

# -----------------------------------------------------------
# 成功時の処理（コミット → タグ → プッシュ）
# -----------------------------------------------------------
handle_success() {
    local iteration="$1"

    log_ok "すべての検証をパスしました（イテレーション #${iteration}）"

    # 変更をコミット（プロジェクトルートで実行）
    git -C "$PROJECT_ROOT" add -A
    git -C "$PROJECT_ROOT" commit -m "${GIT_COMMIT_PREFIX}: イテレーション #${iteration} 完了、fix_plan.md を更新"

    # 自動タグ付け
    if [ "$GIT_AUTO_TAG" = "true" ]; then
        local latest_tag new_tag
        latest_tag="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"

        if [ -z "$latest_tag" ]; then
            new_tag="$GIT_INITIAL_TAG"
        else
            # パッチバージョンをインクリメント（例: 0.0.1 → 0.0.2）
            local base patch
            base="$(echo "$latest_tag" | cut -d. -f1-2)"
            patch="$(echo "$latest_tag" | cut -d. -f3)"
            new_tag="${base}.$((patch + 1))"
        fi

        git -C "$PROJECT_ROOT" tag "$new_tag"
        log_info "タグを作成: ${new_tag}"
    fi

    # リモートにプッシュ
    git -C "$PROJECT_ROOT" push origin "$GIT_BRANCH"
    if [ "$GIT_AUTO_TAG" = "true" ]; then
        git -C "$PROJECT_ROOT" push origin --tags
    fi

    log_ok "変更をプッシュしました"

    # ワークツリー有効時: 成果をメインブランチにマージ
    if [ "$WORKTREE_ENABLED" = "true" ]; then
        log_info "ワークツリーの変更を ${GIT_BRANCH} にマージ中..."
        local original_dir
        original_dir="$(pwd)"

        # メインブランチに切り替えてマージ
        git -C "$PROJECT_ROOT" merge "$WORKTREE_BRANCH" --no-edit
        git -C "$PROJECT_ROOT" push origin "$GIT_BRANCH"
        if [ "$GIT_AUTO_TAG" = "true" ]; then
            git -C "$PROJECT_ROOT" push origin --tags
        fi
    fi
}

# -----------------------------------------------------------
# 失敗時の処理
# -----------------------------------------------------------
handle_failure() {
    local step_code="$1"
    local step_name

    case "$step_code" in
        1) step_name="Lint" ;;
        2) step_name="Build" ;;
        3) step_name="Test" ;;
        *) step_name="不明なステップ" ;;
    esac

    log_error "${step_name} が失敗しました"

    if [ "$LOOP_AUTO_RESET" = "true" ]; then
        log_warn "自動リセットが有効です。git reset --hard を実行します"
        git reset --hard HEAD
        return 0
    fi

    # 人間に確認を求める
    log_warn "失敗したステップ: ${step_name}"
    log_warn "選択肢:"
    log_warn "  r) git reset --hard して最初からやり直す"
    log_warn "  c) ループを続行（エージェントに修正させる）"
    log_warn "  q) ループを停止して手動で確認する"

    read -rp "選択してください (r/c/q): " choice
    case "$choice" in
        r)
            log_info "git reset --hard HEAD を実行します"
            git reset --hard HEAD
            ;;
        c)
            log_info "ループを続行します"
            ;;
        q)
            log_info "ループを停止します。手動でコードを確認してください。"
            exit 0
            ;;
        *)
            log_warn "無効な選択です。ループを停止します。"
            exit 0
            ;;
    esac
}

# -----------------------------------------------------------
# エージェントプロンプトの構築
# -----------------------------------------------------------
# なぜ外部ファイルから読み込むか:
#   ガイドの「① スタックの決定的な割り当て」に従い、プロンプトを
#   スクリプトから分離することで、チューニング時にスクリプト自体の
#   変更が不要になる。また、プロジェクトごとにプロンプトをカスタマイズしやすい。
build_agent_prompt() {
    local prompt_file="${AGENT_PROMPT_FILE}"

    if [ ! -f "$prompt_file" ]; then
        log_error "プロンプトテンプレートが見つかりません: ${prompt_file}"
        log_error "agent_prompt_template.md を作成してください。テンプレートは templates/ にあります。"
        exit 1
    fi

    cat "$prompt_file"
}

# -----------------------------------------------------------
# ワークツリーのセットアップ
# -----------------------------------------------------------
# なぜワークツリーを使うか:
#   エージェントの変更を main ブランチから隔離することで、
#   テスト失敗時のリセットが安全になり、人間が main で
#   並行作業できるようになる。
setup_worktree() {
    if [ "$WORKTREE_ENABLED" != "true" ]; then
        return 0
    fi

    local worktree_path="${PROJECT_ROOT}/${WORKTREE_DIR}"

    log_info "ワークツリーをセットアップ中: ${worktree_path}"

    # ブランチが存在しなければ作成
    if ! git -C "$PROJECT_ROOT" rev-parse --verify "$WORKTREE_BRANCH" &>/dev/null; then
        log_info "ブランチ '${WORKTREE_BRANCH}' を作成"
        git -C "$PROJECT_ROOT" branch "$WORKTREE_BRANCH"
    fi

    # 既存のワークツリーがあれば削除して再作成
    if [ -d "$worktree_path" ]; then
        log_warn "既存のワークツリーを削除: ${worktree_path}"
        git -C "$PROJECT_ROOT" worktree remove "$worktree_path" --force 2>/dev/null || true
    fi

    # ワークツリーを作成
    git -C "$PROJECT_ROOT" worktree add "$worktree_path" "$WORKTREE_BRANCH"
    log_ok "ワークツリーを作成: ${worktree_path} (ブランチ: ${WORKTREE_BRANCH})"

    # ワークツリーに移動
    cd "$worktree_path"
    log_info "作業ディレクトリ: $(pwd)"
}

# -----------------------------------------------------------
# ワークツリーのクリーンアップ
# -----------------------------------------------------------
cleanup_worktree() {
    if [ "$WORKTREE_ENABLED" != "true" ]; then
        return 0
    fi

    local worktree_path="${PROJECT_ROOT}/${WORKTREE_DIR}"

    log_info "ワークツリーをクリーンアップ中..."

    # プロジェクトルートに戻る
    cd "$PROJECT_ROOT"

    # ワークツリーを削除
    if [ -d "$worktree_path" ]; then
        git -C "$PROJECT_ROOT" worktree remove "$worktree_path" --force 2>/dev/null || true
        log_ok "ワークツリーを削除: ${worktree_path}"
    fi
}

# -----------------------------------------------------------
# メインループ
# -----------------------------------------------------------
main() {
    local config_file="${1:-$DEFAULT_CONFIG}"
    local iteration=0

    # ログディレクトリの作成
    mkdir -p "$LOG_DIR"
    LOG_FILE="${LOG_DIR}/loop-$(date '+%Y%m%d-%H%M%S').log"

    log_info "============================================"
    log_info "Loop Engineering を開始します"
    log_info "============================================"

    # 設定の読み込み
    load_config "$config_file"

    log_info "プロジェクトルート: ${PROJECT_ROOT}"

    # プロジェクトルートに移動（エージェントはここで実行される）
    cd "$PROJECT_ROOT"

    # yq の有無を報告
    if command -v yq &> /dev/null; then
        log_info "YAML パーサー: yq を使用"
    else
        log_warn "yq が見つかりません。簡易パーサーを使用します（yq のインストールを推奨）"
    fi

    # ワークツリーのセットアップ（有効な場合のみ）
    setup_worktree

    # Ctrl+C 時にワークツリーをクリーンアップするトラップ設定
    if [ "$WORKTREE_ENABLED" = "true" ]; then
        trap 'log_warn "中断を検出。ワークツリーをクリーンアップ中..."; cleanup_worktree; exit 130' INT TERM
    fi

    # エージェントプロンプトの構築
    local agent_prompt
    agent_prompt="$(build_agent_prompt)"

    # メインループ
    while true; do
        iteration=$((iteration + 1))

        # 最大ループ回数のチェック
        if [ "$LOOP_MAX_ITERATIONS" -gt 0 ] && [ "$iteration" -gt "$LOOP_MAX_ITERATIONS" ]; then
            log_info "最大ループ回数（${LOOP_MAX_ITERATIONS}）に達しました。終了します。"
            break
        fi

        log_info "============================================"
        log_info "イテレーション #${iteration} を開始"
        log_info "============================================"

        # 1. AIエージェントの実行
        if ! run_agent "$agent_prompt"; then
            log_error "エージェントの実行に失敗しました"
            handle_failure 0
            sleep "$LOOP_INTERVAL"
            continue
        fi

        # 2. バックプレッシャー（lint → build → test）
        log_info "バックプレッシャーを実行中..."
        local bp_result=0
        run_backpressure || bp_result=$?

        # 3. 結果に応じた分岐
        if [ "$bp_result" -eq 0 ]; then
            handle_success "$iteration"
        else
            handle_failure "$bp_result"
        fi

        # ループインターバル
        log_info "${LOOP_INTERVAL}秒待機中..."
        sleep "$LOOP_INTERVAL"
    done

    # ワークツリーのクリーンアップ
    cleanup_worktree

    log_info "============================================"
    log_info "Loop Engineering を終了しました"
    log_info "合計イテレーション: ${iteration}"
    log_info "============================================"
}

# スクリプトのエントリーポイント
main "$@"
