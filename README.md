# MagicActions

Magic Mouse のタッチ面のタップ・スワイプ・TipTap・ストローク（図形描画）に任意のアクション（キーボードショートカット送出、アプリ/URL 起動、シェル・AppleScript 実行、システム操作）を割り当てられる常駐 Mac アプリ。BetterTouchTool の Magic Mouse 機能を、ライブタッチ表示キャンバスと「実演して登録する」レコーディング方式の GUI で再構成したもの。

Magic Trackpad / 内蔵トラックパッドでも動作する（設定でオフにできる）。

## 動作要件

- macOS 15 以降（macOS 26.5 で開発・検証）
- Magic Mouse（1st/2nd gen）または Magic Trackpad
- 権限: アクセシビリティ（アクション実行に必須）、入力監視（スクロール抑制に使用）

## ビルド

```bash
brew install xcodegen   # 未導入の場合
./scripts/build.sh      # → build/DerivedData/Build/Products/Debug/MagicActions.app
./scripts/build.sh test # 単体テスト実行
```

初回起動時は設定ウィンドウの「権限」タブから アクセシビリティ / 入力監視 を許可すること。Debug ビルドは ad-hoc 署名のため、リビルドすると TCC 許可の再付与が必要になる場合がある（設定の一覧から一度削除して追加し直すのが確実）。

## 使い方

- メニューバーのマウスアイコン → 「設定を開く…」
- ジェスチャ: プロファイル（グローバル / アプリ別）ごとのジェスチャ一覧。「追加 → ジェスチャを実演して追加…」で、実機の上でジェスチャを1回行うと自動認識され、そのままアクションを割り当てられる
- ライブビュー: 実機のタッチをリアルタイム描画。認識ログも表示（受信の健全性確認を兼ねる）
- ストローク: 組み込み（丸・Z・V・4方向ライン）に加え、実機の面に描いてカスタムストロークを登録できる。ストロークは「面の先端側で一拍置いてから描く」と発動する
- 権限: TCC の状態表示と設定ペインへの誘導

## ジェスチャ語彙と競合について

Magic Mouse の面はネイティブのスクロール／ページスワイプと物理的に共有されるため、既定ではネイティブ動作と競合しない語彙（タップ系）を推奨する。

- 安全: 1〜3本指タップ（ゾーン限定可）、TipTap、ストローク
- 注意: 1本指スワイプはスクロールと本質的に競合するため、スクロール量が大きい場合は自動的に破棄される
- 物理クリックを伴うタッチはジェスチャとして扱われない（誤発火防止）

## アーキテクチャ

```
MagicActions/
  Multitouch/   MultitouchBridge.h（私有 framework 宣言）, TouchService（列挙・監視・再接続）
  Engine/       GestureDetector（純粋ステートマシン）, GestureEngine（キュー・タイマー）,
                StrokeRecognizer（$1 Unistroke）, GestureModels, EngineSettings
  Actions/      Action モデル, ActionDispatcher（CGEvent 送出ほか）
  Config/       AppConfig（プロファイル・バインディング・テンプレート）, ConfigStore（JSON 永続化）
  Permissions/  PermissionMonitor（AX / 入力監視の状態・要求）
  Support/      ButtonMonitor, ScrollSuppressor, HUDController, FrontmostAppMonitor, LoginItemManager
  App/          AppState（配線）, MagicActionsApp（MenuBarExtra + 設定ウィンドウ）
  UI/           設定画面一式（ライブキャンバス・レコーダー・アクションピッカー等）
spike/          M0 検証 CLI（mtdump: デバイス列挙とタッチダンプ, permcheck: TCC 状態）
```

設定ファイル: `~/Library/Application Support/MagicActions/config.json`

## 既知の制約

- 私有フレームワーク `MultitouchSupport.framework` に依存するため、App Store 配布は不可。macOS メジャーアップデートで動かなくなる可能性が常にある（`spike/mtdump` で切り分け可能）
- サンドボックス無効・Debug は ad-hoc 署名。配布する場合は Developer ID 署名＋公証が必要
- キーボードショートカット送出は US/JIS などレイアウト差の影響を受ける場合がある（キーコードベースのため）
- Magic Mouse 2 の Family ID は 112/113 と推定（実機接続時に `spike/mtdump` で要確認。想定外の ID だった場合は `TouchTypes.swift` の `DeviceKind.from` に追記する）
