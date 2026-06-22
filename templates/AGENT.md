# AGENT.md - Agent Learning Log (State File)

> このファイルはAIエージェントが自律的に更新する学習記録（状態ファイル）です。
> ループを重ねる中で発見した正しいコマンド、ビルド手順、過去のバグの教訓を記録します。
> 人間はレビューできますが、原則としてエージェントが管理するファイルです。

## Discovered Commands & Build Procedures

<!-- エージェントが正しいコマンドを発見した場合、ここに記録する -->
<!-- 同じ間違いを繰り返さないための永続的なメモリとして機能する -->

<!-- 例:
- `cargo test -- --nocapture` でテスト出力を確認できる
- `npm run build` の前に `npm ci` が必要
- Python環境では `python -m pytest` が推奨（パスの問題を回避）
-->

## Past Bugs & Lessons Learned

<!-- 過去に遭遇したバグとその解決策を記録し、再発を防ぐ -->

<!-- 例:
- ❌ `import { foo } from './bar'` → ✅ `import { foo } from './bar.js'` (ESM環境では拡張子必須)
- ❌ テストで `setTimeout` を使用 → ✅ `vi.useFakeTimers()` を使う（タイムアウト不安定を回避）
-->

## Environment-Specific Notes

<!-- このプロジェクト固有の環境設定や制約を記録する -->

<!-- 例:
- CI では Node.js 20.x を使用（18.x では crypto モジュールの挙動が異なる）
- ローカル開発では .env.local が必要（.env.example をコピー）
-->
