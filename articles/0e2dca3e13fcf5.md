---
title: "Nim製フルスタックWebフレームワークBasolatoがめざす開発の姿とそれを実現するアーキテクチャ"
emoji: "⬟"
type: "idea" # tech: 技術記事 / idea: アイデア
topics: []
published: false
---

## 組織がアプリケーションを作るとは
- PdMと片岡飛鳥と加地倫三
  - https://www.youtube.com/watch?v=0w8h5Xx_gUA
  - https://www.youtube.com/watch?v=BYak18NRxlo

## 学習コストと保守性
高い生産性を維持し続けるには、以下のようにスムーズに開発できることが大事です
- プログラムを書く
- コンパイルする
- 型の不一致などでコンパイルエラーが発生する
- コンパイルエラーを修正する
- コンパイルに成功する
- 実行する
- ランタイムエラーが発生する
- ランタイムエラーを修正する
- 完成

例えばコンパイルエラーが発生しているのにその原因がわからないとか、ランタイムエラーが発生していてその原因はわかるがどう直せばいいのかわからないとか、そういう状況が発生していてはいけないわけです。

## なぜNimなのか
## Webフレームワークが担う役割
## PMF前の開発、PMF後の開発


## PMF前後をシームレスに繋げる軽量なドメイン駆動設計