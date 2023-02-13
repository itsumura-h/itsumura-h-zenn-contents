---
title: "Nimのメモリ管理を理解する⑤ ― ムーブセマンティクスとデストラクタ"
emoji: "👑"
type: "idea" # tech: 技術記事 / idea: アイデア
topics: ["nim"]
published: false
---

この記事はNimのメモリ管理を理解するシリーズの5作目になります。今回は公式ドキュメントの[Nim Destructors and Move Semantics](https://nim-lang.org/docs/destructors.html)を翻訳して、Nimのメモリ管理について更に理解を進めていこうと思います。

---

〜Nimのメモリ管理を理解するシリーズ〜
- [Nimのメモリ管理を理解する① ― Nimの新しいGC、ARCについて](https://qiita.com/dumblepy/items/be660c17556d73aa3570)
- [Nimのメモリ管理を理解する② ― Nimのムーブセマンティクス](https://zenn.dev/dumblepy/articles/af2b2b9f8fd890)
- [Nimのメモリ管理を理解する③ ― GCなしのNim](https://zenn.dev/dumblepy/articles/0dcbc08aed1a25.md)

---

## このドキュメントについて
本書は、従来のGCを用いず、デストラクタとムーブセマンティクスに基づいたNimランタイムを紹介します。この新しいランタイムの利点は、Nim のプログラムがヒープサイズを気にしなくなることと、マルチコアマシンを有効に活用するためのプログラムが書きやすくなることです。また、ファイルやソケットなどのクローズコールを手動で行う必要がなくなるという嬉しい特典もあります。

この文書は、Nim におけるムーブセマンティクスとデストラクタの動作に関する正確な仕様であることを目的としています。

## モチベーションを高めるサンプルコード
ここで説明した言語機構を用いると、カスタムseqは次のように書くことができます。

```nim
type
  myseq*[T] = object
    len, cap: int
    data: ptr UncheckedArray[T]

proc `=destroy`*[T](x: var myseq[T]) =
  if x.data != nil:
    for i in 0..<x.len: `=destroy`(x.data[i])
    dealloc(x.data)

proc `=trace`[T](x: var myseq[T]; env: pointer) =
  # `=trace` は、サイクルコレクタ `--mm:orc` が
  # オブジェクトグラフをトレースする方法を理解することを可能にします。
  if x.data != nil:
    for i in 0..<x.len: `=trace`(x.data[i], env)

proc `=copy`*[T](a: var myseq[T]; b: myseq[T]) =
  # 自己割り当てでは何もしない:
  if a.data == b.data: return
  `=destroy`(a)
  wasMoved(a)
  a.len = b.len
  a.cap = b.cap
  if b.data != nil:
    a.data = cast[typeof(a.data)](alloc(a.cap * sizeof(T)))
    for i in 0..<a.len:
      a.data[i] = b.data[i]

proc `=sink`*[T](a: var myseq[T]; b: myseq[T]) =
  # move assignment, optional.
  # Compiler is using `=destroy` and `copyMem` when not provided
  `=destroy`(a)
  wasMoved(a)
  a.len = b.len
  a.cap = b.cap
  a.data = b.data

proc add*[T](x: var myseq[T]; y: sink T) =
  if x.len >= x.cap:
    x.cap = max(x.len + 1, x.cap * 2)
    x.data = cast[typeof(x.data)](realloc(x.data, x.cap * sizeof(T)))
  x.data[x.len] = y
  inc x.len

proc `[]`*[T](x: myseq[T]; i: Natural): lent T =
  assert i < x.len
  x.data[i]

proc `[]=`*[T](x: var myseq[T]; i: Natural; y: sink T) =
  assert i < x.len
  x.data[i] = y

proc createSeq*[T](elems: varargs[T]): myseq[T] =
  result.cap = elems.len
  result.len = elems.len
  result.data = cast[typeof(result.data)](alloc(result.cap * sizeof(T)))
  for i in 0..<result.len: result.data[i] = elems[i]

proc len*[T](x: myseq[T]): int {.inline.} = x.len
```