# Zig_80 日本語Documentation Style Guide

## 目的

初心者向け説明、利用者向け仕様、将来構想で同じ概念を同じ言葉で表し、実装状態を誤解させないための表記方針です。

## 用語

一般概念は初出で日本語＋英語、その後は日本語を基本とします。

| 推奨する初出 | 以後の表記 |
|---|---|
| レジスタ（Register） | レジスタ |
| メモリ（Memory） | メモリ |
| 命令（Instruction） | 命令 |
| アドレス（Address） | アドレス |
| フラグ（Flag） | フラグ |
| スタック（Stack） | スタック |
| バス（Bus） | バス |
| ブレークポイント（Breakpoint） | ブレークポイント |
| シンボル（Symbol） | シンボル |
| ソースマップ（Source Map） | ソースマップ |

UIの正式名称は`Source`ビュー、`CPU`パネル、`Instruction`カード、`Logic Analyzer`のように英語のまま表記できます。命令Mnemonic、Register名、Signal名、CLI Command、Key名はCode Styleで表します。

## 実装状態

- 実装済み: 「対応します」「表示します」
- 制限: 「現在は〜だけです」「〜には未対応です」
- 将来案: 「将来的には〜を検討しています」「構想段階です」

未実装CLI例は実行可能なCode Blockへ混ぜず、「提案」「未実装」と直前に明記します。Logical Bus Eventをcycle-accurate、実時間、電気Timingとは表現しません。

## 文書の役割

- Tutorial: 順番に読み、Z80 Programmingを学ぶ
- Reference: 現在の実装仕様を必要時に調べる
- Guides: 目的別の実践手順
- Architecture: 責務境界、設計判断、将来構想
- Roadmap: 未実装項目と依存関係

Markdownを正本とし、GitHub上で直接読める構造を維持します。

