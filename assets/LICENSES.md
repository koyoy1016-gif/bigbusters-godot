# 素材とライセンス

使った素材は、ここに記録する。

## フォント

| ファイル | 元のフォント | ライセンス | 入手先 | 備考 |
|---|---|---|---|---|
| `assets/fonts/NotoSansJP-Regular-subset.ttf` | Noto Sans JP Regular（Copyright 2014-2021 Adobe。Reserved Font Name 'Source'） | SIL Open Font License 1.1（再配布・同梱OK）。全文は `assets/fonts/NotoSansJP-OFL.txt` | npmパッケージ `@expo-google-fonts/noto-sans-jp` 0.4.4（`400Regular/NotoSansJP_400Regular.ttf`）。元はGoogle Fonts | 軽くするため、文字を絞った版（ASCII、ひらがな、カタカナ、JIS X 0208の漢字、記号。約6,970字、約2.1MB）。ヒンティングと字形の切り替え機能（GSUBなど）は外した |

- フォントを改変（文字の絞り込み）したので、ファイル名に Reserved Font Name の 'Source' を使っていない
- フォント単体を売ることはしない（OFLの条件）。ゲームに同梱するのは問題ない
- 必要な文字が増えたときは、文字を足して作り直す（作り方は `NOTES.md` の作業ログ）
