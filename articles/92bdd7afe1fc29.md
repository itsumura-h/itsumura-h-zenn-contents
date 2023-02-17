---
title: "Nimのメモリ管理を理解する⑤ ― ムーブセマンティクスとデストラクタ"
emoji: "👑"
type: "idea" # tech: 技術記事 / idea: アイデア
topics: ["nim"]
published: true
---

この記事はNimのメモリ管理を理解するシリーズの5作目になります。今回は公式ドキュメントの[Nim Destructors and Move Semantics](https://nim-lang.org/docs/destructors.html)を翻訳して、Nimのメモリ管理について更に理解を進めていこうと思います。

---

〜Nimのメモリ管理を理解するシリーズ〜
- [Nimのメモリ管理を理解する① ― Nimの新しいGC、ARCについて](https://qiita.com/dumblepy/items/be660c17556d73aa3570)
- [Nimのメモリ管理を理解する② ― Nimのムーブセマンティクス](https://zenn.dev/dumblepy/articles/af2b2b9f8fd890)
- [Nimのメモリ管理を理解する③ ― GCなしのNim](https://zenn.dev/dumblepy/articles/0dcbc08aed1a25)
- [Nimのメモリ管理を理解する④ ― ORC - アルゴリズムによるアドバンテージ](https://zenn.dev/dumblepy/articles/efffa86d9177b1)
- [Nimのメモリ管理を理解する⑤ ― ムーブセマンティクスとデストラクタ](https://zenn.dev/dumblepy/articles/92bdd7afe1fc29)

---

## このドキュメントについて
本書は、従来のGCを用いず、デストラクタとムーブセマンティクスに基づいたNimランタイムを紹介します。この新しいランタイムの利点は、Nim のプログラムがヒープサイズを気にしなくなることと、マルチコアマシンを有効に活用するためのプログラムが書きやすくなることです。また、ファイルやソケットなどのクローズコールを手動で行う必要がなくなるという嬉しい特典もあります。

この文書は、Nimにおけるムーブセマンティクスとデストラクタの動作に関する正確な仕様であることを目的としています。

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

## ライフタイムを追跡するフック
Nimの標準的な文字列型やseq型（動的配列）、その他の標準的なコレクションのメモリ管理は、いわゆる「Lifetime-tracking hooks」、つまり特定の型拘束演算子によって行われます。
各オブジェクト型T（Tは個別型でもよい）に対して3つの異なるフックがあり、 コンパイラによって暗黙のうちに呼び出されます。
(注意: ここでの「フック」という言葉は、動的結合や実行時の間接参照を意味するものではなく、暗黙の呼び出しは静的に結合され、インライン化される可能性もあります)。

### `=destroy` hook
`=destory` hookはオブジェクトの関連メモリを解放し、その他の関連するリソースを解放します。変数がスコープ外に出たときや、宣言されたルーチンが戻ろうとするときに、このフックによって破棄されます。

型Tに対するこのフックのプロトタイプは、次のようにする必要があります。
```nim
proc `=destroy`(x: var T)
```

`=destroy`の一般的なパターンはこのようになります。
```nim
proc `=destroy`(x: var T) =
  # まず'x'がどこか他でムーブされていないかチェックする
  if x.field != nil:
    freeResource(x.field)
```

### `=sink` hook
`=sink` hookは、オブジェクトをムーブする際に、ムーブ元からリソースを"盗んで"ムーブ先に渡します。オブジェクトをデフォルト値（オブジェクトの状態が開始した値）に戻すことで、ムーブ元のデストラクタがその後リソースを解放しないことが保証されます。オブジェクト`x`をデフォルト値に戻すことは、`wasMoved(x)`と記述されます。リソースがムーブ元から渡されない場合、コンパイラは`=destroy`と`copyMem`の組み合わせを代わりに使用します。これは効率的なので、ユーザーが独自の`=sink`演算子を実装する必要はほとんどなく、`=destroy`と`=copy`を提供するだけで十分で、あとはコンパイラが処理してくれます。

型Tに対するこのフックのプロトタイプは、次のようにする必要があります。
```nim
proc `=sink`(dest: var T; source: T)
```

`=sink`の一般的なパターンはこのようになります。
```nim
proc `=sink`(dest: var T; source: T) =
  `=destroy`(dest)
  wasMoved(dest)
  dest.field = source.field
```

> 注：`=sink`は自己割り当てをチェックする必要はありません。自己割り当てがどのように扱われるかは、このドキュメントの後の方で説明します。

### `=copy` hook
Nimの通常の代入は概念的には値をコピーします。コピーフックは`=sink`操作に変換できなかった代入のために呼ばれます。

型Tに対するこのフックのプロトタイプは、次のようにする必要があります。
```nim
proc `=copy`(dest: var T; source: T)
```

`=copy`の一般的なパターンはこのようになります。
```nim
proc `=copy`(dest: var T; source: T) =
  # リソースの自己割り当てを防ぐ
  if dest.field != source.field:
    `=destroy`(dest)
    wasMoved(dest)
    dest.field = duplicateResource(source.field)
```

`=copy`関数は`{.error.}`プラグマでマークすることができます。そうすれば、コピーにつながるような代入はコンパイル時に阻止されます。これは次のようになります。

```nim
proc `=copy`(dest: var T; source: T) {.error.}
```

この時にカスタムエラーメッセージ（例： `{.error: "custom error".}` ）を指定しても、エラーメッセージがコンパイラーから出力されることはありません。`{.error.}`プラグマの前に`=`がないことに注意してください。

### `=trace` hook
カスタム**コンテナ**タイプはNimのサイクルコレクターである`--mm:orc`を`=trace`フックでサポートすることができます。もしコンテナが`=trace`を実装していない場合、コンテナの助けを借りて構築された周期的なデータ構造はメモリやリソースをリークするかもしれませんが、メモリの安全性は損なわれません。

型Tに対するこのフックのプロトタイプは、次のようにする必要があります。
```nim
proc `=trace`(dest: var T; env: pointer)
```

`env`は、ORCがその内部状態を追跡するために使用され、組み込みの`=trace`操作の呼び出しに渡されるべきです。

通常、カスタムの`=trace`が必要になるのは、手動で割り当てたリソースを解放するカスタムの`=destroy`も使用する場合だけで、手動で割り当てたリソース内のアイテムから循環的に参照される可能性があり、これらの循環的に参照されるリソースを`-mm:orc`が破壊して収集したい場合のみです。しかし現在のところ、`=destroy`/`=trace`のどちらを先に使っても、自動的にもう一方のバージョンを作成し、それがペアの2番目の作成と衝突してしまうという相互利用の問題が生じています。この問題を回避するには、「フック」の2つ目を先に宣言して、自動生成を防止することです。

`=destroy`を`=trace`と共に使う一般的なパターンはこのようになります。
```nim
type
  Test[T] = object
    size: Natural
    arr: ptr UncheckedArray[T] # 生ポインタ

proc makeTest[T](size: Natural): Test[T] = # custom allocation...
  Test[T](size: size, arr: cast[ptr UncheckedArray[T]](alloc0(sizeof(T) * size)))


proc `=destroy`[T](dest: var Test[T]) =
  if dest.arr != nil:
    for i in 0 ..< dest.size: dest.arr[i].`=destroy`
    dest.arr.dealloc

proc `=trace`[T](dest: var Test[T]; env: pointer) =
  if dest.arr != nil:
    # trace the `T`'s which may be cyclic
    for i in 0 ..< dest.size: `=trace`(dest.arr[i], env)

# 必要であればその他のカスタム"hook"をこの後に実装していく...
```

> 注: `=trace`フック(これは-mm:orcでのみ使用される)は、現在他のフックより実験的で洗練されていません。

## ムーブセマンティクス
「ムーブ」は最適化されたコピー操作と見なすことができます。コピー操作の元リソースがその後使用されない場合、コピーはムーブに置き換えることができます。ここでは、`lastReadOf(x)`という表記を用いて、`x`がその後使用されないことを表現しています。この特性は静的な制御フロー解析によって計算されますが、`system.move`を明示的に使用することによっても強制することもできます。

## Swap
自己割り当てをチェックする必要があり、また`=copy`と`=sink`の内部で以前のオブジェクトを破壊する必要があることは、`system.swap`をそれ自身の組み込みプリミティブとして扱い、関係するオブジェクトのすべてのフィールドを`copyMem`または同等のメカニズムで交換することを強く示唆するものです。言い換えると、`swap(a, b)`は`let tmp = move(b); b = move(a); a = move(tmp)`のように単なる交換としては実装されていません。

このことは、さらなる結果をもたらします。

- 同じオブジェクトを指すポインタを含むオブジェクトは、Nimのモデルではサポートされていません。そうしなければ、スワップされたオブジェクトは一貫性のない状態になってしまいます。
- `Seqs`は実装上`realloc`を使用することができます。

## Sinkパラメーター
コレクションに変数を移動させるには、通常`sink`パラメータを使用します。`sink`パラメータに渡されたリソースは、その後で使われてはいけません。これは制御フローグラフの静的解析によって保証されます。もし、そのリソースが最後に使われたリソースであることが証明できない場合は、代わりにコピーが作成され、このコピーが`sink`パラメータに渡されます。

`sink`パラメータは`proc`本体の中で一度消費されるかもしれませんが、全く消費される必要はありません。この理由は、`proc put(t: var Table; k: sink Key, v: sink Value)`のようなシグネチャは、それ以上のオーバーロードなしに使えるべきで、`k`がすでにテーブルに存在する場合、`put`は`k`の所有権をとらないかもしれないからです。`sink`パラメータは、線形型システムではなく、アフィン型システムを可能にします。

採用された静的解析は限定的で、ローカル変数のみを対象としますが、オブジェクトとタプルフィールドは別個の存在として扱われる。
```nim
proc consume(x: sink Obj) = discard "no implementation"

proc main =
  let tup = (Obj(), Obj())
  consume tup[0]
  # tup[0]は消費されたが、tup[1]はまだ生存している
  echo tup[1]
```

時には、明示的に値を最終位置にムーブさせることが必要な場合もあります。
```nim
proc main =
  var dest, src: array[10, string]
  # ...
  for i in 0..high(dest):
    dest[i] = move(src[i])
```
実装は、さらに多くのムーブの最適化を実装することは許されていますが、必須ではありません（現在では手動での最適化は不要になっています）。

## Sinkパラメーターによる推論
現在の実装では、`sink`パラメータ推論を限定的に行うことができます。しかしコマンドラインで`--sinkInference:on`を指定するか`push`プラグマによって有効にする必要があります。

あるセクションでコードの推論を有効にするには、`{.push sinkInference: on.}`...`{.pop.}`のブロックを使うことでできます。

`.nosinks`プラグマを使用すると、特定のルーチンでこの推論を無効にすることができます。
```nim
proc addX(x: T; child: T) {.nosinks.} =
  x.s.add child
```
推論アルゴリズムの詳細については、現在ドキュメント化はされていません。

## リライトルール
> 注：許可される実装方法は2種類あります。
> 
> - 生成される「最終」セクションは、ルーチン本体全体を包む1つのセクションとすることができます。
> - 生成された「最終」セクションは、スコープを囲むようにラップされます。

現在の実装では、戦略(2)に従っています。つまり、スコープの終端でリソースが破壊されます。

```nim
var x: T; stmts
---------------             (destroy-var)
var x: T; try stmts
finally: `=destroy`(x)


g(f(...))
------------------------    (nested-function-call)
g(let tmp;
bitwiseCopy tmp, f(...);
tmp)
finally: `=destroy`(tmp)


x = f(...)
------------------------    (function-sink)
`=sink`(x, f(...))


x = lastReadOf z
------------------          (move-optimization)
`=sink`(x, z)
wasMoved(z)


v = v
------------------   (self-assignment-removal)
discard "nop"


x = y
------------------          (copy)
`=copy`(x, y)


f_sink(g())
-----------------------     (call-to-sink)
f_sink(g())


f_sink(notLastReadOf y)
--------------------------     (copy-to-sink)
(let tmp; `=copy`(tmp, y);
f_sink(tmp))


f_sink(lastReadOf y)
-----------------------     (move-to-sink)
f_sink(y)
wasMoved(y)
```

## オブジェクトと配列の構築
オブジェクトと配列の構築は、関数が`sink`パラメータを持つ関数呼び出しとして扱われます。

## デストラクタの除去
`wasMoved(x);`の後に`=destroy(x)`を実行すると、互いに相殺します。実装では、効率とコードサイズを改善するために、これを利用することが推奨されます。現在の実装では、この最適化が行われています。

## 自己割り当て
`wasMoved`と組み合わせた`=sink`は、自己割り当てに対応できますが、あまり良くはありません。

`x = x`という単純なケースを`=sink(x, x); wasMoved(x)`にすると、`x`の値が失われてしまうからです。解決策としては、以下のような単純な自己割り当てがあります。

- シンボル: `x = x`
- フィールドアクセス: `x.f = x.f`
- コンパイル時にインデックスが分かっている配列、シーケンス、文字列のアクセス： `x[0] = x[0]`

これらは、何もしない空の文に変換されます。コンパイラはこれ以上のケースを自由に最適化することができます。

複雑なケースは`x = f(x)`の変形のように見えますが、ここでは`x = select(rand() < 0.5, x, y)`を考えてみます。

```nim
proc select(cond: bool; a, b: sink string): string =
  if cond:
    result = a # aはresultへムーブされる
  else:
    result = b # bはresultへムーブされる

proc main =
  var x = "abc"
  var y = "xyz"
  # 自己割り当てができる
  x = select(true, x, y)
```

これは以下のように変換されます。

```nim
proc select(cond: bool; a, b: sink string): string =
  try:
    if cond:
      `=sink`(result, a)
      wasMoved(a)
    else:
      `=sink`(result, b)
      wasMoved(b)
  finally:
    `=destroy`(b)
    `=destroy`(a)

proc main =
  var
    x: string
    y: string
  try:
    `=sink`(x, "abc")
    `=sink`(y, "xyz")
    `=sink`(x, select(true,
      let blitTmp = x
      wasMoved(x)
      blitTmp,
      let blitTmp = y
      wasMoved(y)
      blitTmp))
    echo [x]
  finally:
    `=destroy`(y)
    `=destroy`(x)
```

このように、この変換は自己割り当てに対して上手く機能します。

## 借用の型
`proc p(x: sink T)`は`proc p`が`x`の所有権を持つことを意味します。さらに生成/コピー <-> 破壊のペアを排除するために、関数の戻り値の型を貸し出したことを明示するために`lent T`としてアノテートすることができます。

`sink`と`lent`アノテーションによって、（すべてではないにしても）ほとんどの余計なコピーと破壊を取り除くことができます。

`lent T`は`var T`と同様に隠れポインタです。ポインタがその起源より長生きしないことは、コンパイラによって証明されています。`lent T`型や`var T`型の式には，デストラクタ呼び出しは注入されません．

```nim
type
  Tree = object
    kids: seq[Tree]

proc construct(kids: sink seq[Tree]): Tree =
  result = Tree(kids: kids)
  # 以下のように変換されます
  `=sink`(result.kids, kids); wasMoved(kids)
  `=destroy`(kids)

proc `[]`*(x: Tree; i: int): lent Tree =
  result = x.kids[i]
  # 'x'からの借用は以下のように変換されます
  result = addr x.kids[i]
  # これは'lent'(借用)を意味し、その正体は'var T'のように隠されたポインタです。
  # 'var'と異なるのは、これはオブジェクトを書き換えるためには使えないということです。

iterator children*(t: Tree): lent Tree =
  for x in t.kids: yield x

proc main =
  # 全てはムーブに変換されます
  let t = construct(@[construct(@[]), construct(@[])])
  echo t[0] # アクセサはリソースのコピーは作成しない
```

## `.cursor`アノテーション

`--mm:arc|orc`モードではNimの`ref`型は同じランタイムの「フック」によって実装され、参照カウントを行ないます。このため、周期的な構造はすぐに解放することができません(`--mm:orc`には サイクルコレクタが付属しています)。`.cursor`アノテーションを使えば、宣言的にサイクルを分割することができます。

```nim
type
  Node = ref object
    left: Node # 所有権を表すref型
    right {.cursor.}: Node # 所有権を表さないref型
```

しかし、これは単なるC++の`weak_ptr`ではないことに注意してください。rightのフィールドは参照カウントに関与しない、実行時チェックのない生のポインタであることを意味します。

自動参照カウントには、リンクされた構造体を反復処理するときにオーバーヘッドが発生するという欠点もあります。このオーバーヘッドを回避するために、.cursorアノテーションを使用することもできます。

```nim
var it {.cursor.} = listRoot
while it != nil:
  use(it)
  it = it.next
```

実際、`.cursor`はより一般的にオブジェクトの構築/破壊のペアを防ぐので、他の文脈でも有用です。代替の解決策は生のポインタ（ptr）を使うことですが、これはより面倒で、また、Nimの進化にとってより危険です。後で、コンパイラは`.cursor`アノテーションが安全であることを証明しますが、`ptr`については、コンパイラは起こりうる問題について何もできません。

## Cursor推論 / [コピーの省略](https://ja.wikipedia.org/wiki/%E3%82%B3%E3%83%94%E3%83%BC%E3%81%AE%E7%9C%81%E7%95%A5)
現在の実装では、`.cursor`推論も実行されます。カーソル推論はコピーの省略の一種です。

どのように、そして、いつ、それを行うことができるかを知るために、この質問について考えてみましょう。`dest = src`において、本当に完全なコピーを"実体化"しなければならないのはどのような場合でしょうか？それは`dest`や`src`がその後に変更される場合のみです。`dest`がローカル変数であれば、解析は簡単です。また、`src`が形式パラメータに由来する位置であれば、それが変更されることはないでしょう。言い換えれば、コンパイル時に[コピーオンライト](https://ja.wikipedia.org/wiki/%E3%82%B3%E3%83%94%E3%83%BC%E3%82%AA%E3%83%B3%E3%83%A9%E3%82%A4%E3%83%88)の解析を行うのです。

つまり、「借用」ビューは、明示的なポインタ間接参照なしに自然に書くことができるのです。

```nim
proc main(tab: Table[string, string]) =
  let v = tab["key"] # 'tab'がその後変更されないので、カーソルと推論される
  # 'v'へのコピーも'v'の破棄も行わない(=借用)
  use(v)
  useItAgain(v)
```

## フックリフティング
`タプル型(A, B, ...)`のフックは、関係する型`A`, `B`, ...のフックをタプル型にリフティングすることで生成されます。すなわち、コピー`x = y`は`x[0] = y[0]; x[1] = y[1]; ...`のように実装され、同様に`=sink`と`=destroy`も実装されます。

オブジェクトや配列のような他の値ベースの複合型も同様に処理されます。しかし、objectについては、コンパイラが生成したフックをオーバーライドすることができます。これは、より効率的なデータ構造の探索を行うため、あるいは深い再帰を避けるために重要です。

## フックの生成
フックを上書きする機能は、phase ordering problemにつながります。

```nim
type
  Foo[T] = object

proc main =
  var f: Foo[int]
  # エラー: 'f'のデストラクタはこのスコープでアクセスされる前に呼び出されてしまう

proc `=destroy`[T](f: var Foo[T]) =
  discard
```

その解決策は、使用する前に`proc =destroy`Tを定義することです。コンパイラはすべての型に対して、戦略的な場所に暗黙のフックを生成し、明示的に提供されたフックが「遅すぎた」場合に、確実に検出できるようにします。これらの戦略的な場所は、書き換えルールから導き出されたもので、以下の通りです。

`let/var x = ...`(var/letバインディング)では、`typeof(x)`のためのフックが生成され る。
`x = ... `(代入) では，`typeof(x)`のためにフックが生成される．
`f(...)`(関数呼び出し) では、`typeof(f(...))`のためにフックが生成される。
すべてのsinkパラメータ`x: sink T`に対して、`typeof(x)`のためのフックが生成される。

## nodestroyプラグマ
実験的な `nodestroy`プラグマはフックの挿入を抑制します。これは深い再帰を避けるために、オブジェクトの探索を特殊化するために使用することができます。

```nim
type Node = ref object
  x, y: int32
  left, right: Node

type Tree = object
  root: Node

proc `=destroy`(t: var Tree) {.nodestroy.} =
  # スタックオーバーフローを起こさないように明示的なスタックを使用する:
  var s: seq[Node] = @[t.root]
  while s.len > 0:
    let x = s.pop
    if x.left != nil: s.add(x.left)
    if x.right != nil: s.add(x.right)
    # 明示的にメモリを開放する:
    dispose(x)
  # .nodestroyのおかげで's'のデストラクタも暗黙的に呼ばれなくなったので、
  # 自分自身で'=destroy'を呼び出さなければならないことに注意してください。
  `=destroy`(s)
```
この例からわかるように、この解決策では十分とは言えず、最終的にはより良い解決策に置き換える必要があります。

## [コピーオンライト](https://ja.wikipedia.org/wiki/%E3%82%B3%E3%83%94%E3%83%BC%E3%82%AA%E3%83%B3%E3%83%A9%E3%82%A4%E3%83%88)

文字列リテラルは「コピーオンライト」として実装されています。文字列リテラルを変数に代入しても、そのリテラルのコピーは作成されません。その代わり、変数は単にそのリテラルを指すようになります。リテラルは、それを指している異なる変数間で共有されます。コピー操作は、最初の書き込みが行われるまで延期されます。

```nim
var x = "abc"  # コピーしない
var y = x      # コピーしない
y[0] = 'h'     # コピーする
```

アドレスが変更可能な変数にに使用されるかどうかはわからないため、`addr x`に対する抽象化は失敗します。`prepareMutation`は"address of"操作の前に呼び出される必要があります。

```nim
var x = "abc"
var y = x

prepareMutation(y)
moveMem(addr y[0], addr x[0], 3)
assert y == "abc"
```
