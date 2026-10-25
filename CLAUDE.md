# こんこん花札道中

妖怪賭場を舞台にした花札のデッキ構築ローグライク（ブラウザゲーム）。
前作『借金3000万！3日で返せ！』（~/Projects/maiddragoncasino）とは別プロジェクト・別URL。

## 企画の要点
- 主人公：見習い狐のコン（ボケ）と、お目付け役の狛狐ギン（ツッコミ）。賭けて負けた「あぶらあげ」を取り返す一夜の話
- 3つの宿場 × 3戦（小場・大場・親分）＝9戦。目標点を超えれば勝ち、出す回数を使い切ったら終わり
- 点 ＝ チップ × 倍率。月の組み合わせで「形」（一対・三つ組・続き月・同種…）、花札の伝統の「役」（猪鹿蝶・赤短…）で上乗せ
- 勝つと文（お金）→ 夜市で式神（ずっと効く）・巻物（形のレベル上げ）・お札（札をいじる）を買う
- 親分は特殊な決まりを課す。最後は九尾の玉藻
- キャラはファーリー（ケモノ）向け、全年齢、コメディ。激しい点滅はしない

## コード
- `scripts/cards.gd`: 花札48枚の定義（月・種類・役の印）。札は Dictionary で、強化で書き換える
- `scripts/rules.gd`: 数値（目標点・報酬・手札枚数）と、形・役・式神・お札・親分の定義表
- `scripts/scoring.gd`: 点の計算。演出用に steps（何がいくつ足されたか）を順に返す。式神の効果は id ごとにここで解釈
- `scripts/run.gd`: 1回の挑戦の状態（山札・手札・お金・式神）。画面を持たないのでボットからも使う
- `scripts/game.gd`: 画面と進行。TITLE → INTRO（場の前・会話）→ PLAY → PAYOUT → SHOP → … → CLEAR / GAMEOVER
  - 画面は状態ごとに組み立て、向きが変わったら組み直す（PLAY は `_layout_play()` で配置だけ直す）
  - 演出中は `busy` で操作を止める。会話中は画面全体のタップで次へ
  - デバッグビルドのみ F1 +20文 / F2 その場で勝ち / F3 負け / F4 最後の親分へ
- `scripts/card_view.gd`: 札1枚の描画（絵の上に月と種類の札を重ねる）
- `scripts/scenario.gd`: セリフ集。`scripts/ui_style.gd`: 色とパネル
- `scripts/screen.gd`（Autoload `Screen`）: 縦横で基準解像度を 1280x720 / 720x1280 に切り替える
- `scripts/audio.gd`（Autoload `Audio`）: `Audio.bgm("den")` / `Audio.sfx("chip")` / `Audio.jingle("win")`。M でミュート

## バランス確認
- `godot --headless -s res://tools/balance_sim.gd -- 50 detail`（数秒）
- ボットは毎回「一番点の高い出し方」を全探索で選び、弱い手なら捨てる。店では式神を優先して買う
- ボットは役の組み合わせ探しが人間より上手く、店の買い方は人間より下手
- 書き出しは GDScript の構文エラーがあっても成功してしまう。公開前に sim を1回流すと気付ける

## 素材
- 画像：`tools/gen_image.sh <出力> "<プロンプト>" [参照画像]`（Codex の画像生成）。生成元は `art/raw/`（ゲームに含めない）
  - 透過は緑背景で生成して `tools/chroma_key.py`。花札は月ごとに4枚並べて生成し、切り分けて `assets/images/cards/<月>_<0-3>.png`
  - 生成AI素材であることはタイトルに明記している
- 音：`python3 tools/make_audio.py`（三味線・琴・笛・太鼓を合成。外部素材なし）→ `godot --headless --import`
  - BGM の `.wav.import` は `edit/loop_mode=2`（作り直したら確認）

## コマンド・公開
- Godot 4.7.2（`godot` = ~/.local/bin/godot、非.NET版）。GDScript のみ、Compatibility レンダラー
- Webエクスポート: `godot --headless --export-release "Web" build/web/index.html`
- 公開: main に push すると GitHub Actions が書き出して GitHub Pages へ（Gentou30/konkon-hanafuda）
- タイトルに build（コミットSHA）を表示。Pages のキャッシュは最大10分残る
