#!/bin/bash
# 最小限の自律コーディングループ（Ralph Wiggum手法）の例

while true; do
    echo "=== 新しい自律ループを開始します ==="
    
    # 1. 計画書(@fix_plan.md)と仕様書(specs/)を確定スタックとして割り当て、エージェントを起動 [5]
    # 1回につき、最も重要と判断した1つのタスクのみを処理させる [2]
    # （※「agent-cli」はプロジェクトで使用しているCLIツールに置き換えてください）
    agent-cli --prompt "
      Study @specs/* for the compiler specifications and @fix_plan.md to understand the plan so far [6].
      Choose the most important thing to implement from @fix_plan.md and execute it [2].
      DO NOT IMPLEMENT PLACEHOLDER or minimal implementations [7].
      Before making changes, search the codebase using parallel subagents (do not assume it's not implemented) [8].
    "

    # 2. バックプレッシャー（ビルドおよびテストによる自動検証） [3]
    echo "コードをテスト中..."
    # 例としてRustプロジェクトのテストを実行（言語に応じて cargo test や npm test 等に変更） [3]
    cargo test
    TEST_RESULT=$?

    # 3. 検証結果に応じた条件分岐
    if [ $TEST_RESULT -eq 0 ]; then
        echo "テストが正常に通過しました。自動完了処理を開始します [4]"
        
        # 計画書（@fix_plan.md）の完了項目を更新し、変更をコミットしてプッシュ [4]
        git add -A
        git commit -m "auto: Ralph loop completed an increment and updated @fix_plan.md" [4]
        git push origin main [4]
        
        # バージョンタグの自動付与（0.0.0からパッチバージョンを1ずつインクリメント） [4]
        LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
        if [ -z "$LATEST_TAG" ]; then
            NEW_TAG="0.0.0"
        else
            # タグの末尾（パッチ）を1増やす [4]
            BASE=$(echo $LATEST_TAG | cut -d. -f1-2)
            PATCH=$(echo $LATEST_TAG | cut -d. -f3)
            NEW_TAG="$BASE.$((PATCH + 1))"
        fi
        
        git tag $NEW_TAG [4]
        git push origin $NEW_TAG [4]
        echo "バージョン $NEW_TAG をプッシュしました。次のループに移行します。"

    else
        echo "テストまたはビルドが失敗しました [4]"
        echo "追加のロギングやデバッグログを元にエージェントに再評価させる（ループバック）か、人間の介入を求めます [9, 10]"
        
        # エージェントが自力で解決できない状態（コンテキストウィンドウの溢れ等）に陥った場合、
        # 人間が介入してリセットするか、新しいプロンプトで救出する判断を下します [10]
        read -p "git reset --hard を実行して最初からやり直しますか？ (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            git reset --hard HEAD [10]
        else
            echo "ループを一時停止します。手動でコードを確認してください。"
            break
        fi
    fi

    # API制限や負荷を考慮した短いインターバル
    sleep 5
done