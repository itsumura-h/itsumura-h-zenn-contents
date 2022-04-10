---
title: "Nimのメモリ管理を理解する② ― Nimのムーブセマンティクス"
emoji: "👑"
type: "idea" # tech: 技術記事 / idea: アイデア
topics: ["nim"]
published: false
---

Nimのメモリ管理について理解していこう、そしてその内容を日本語でちゃんと公開されている状態にしようということで、昔書いた記事からシリーズ化させた続編として今回は作者の講演の全訳をしてみたいと思います。

https://www.youtube.com/watch?v=yA32Wxl59wo

---

〜Nimのメモリ管理を理解するシリーズ〜
- [Nimのメモリ管理を理解する① ― Nimの新しいGC、ARCについて](https://qiita.com/dumblepy/items/be660c17556d73aa3570)

---

## はじめに
"悪いデザインを真似することは良いデザインではない" -- Nim非公式モットー
- "悪い設計をコピーしてはいけない！"
- "いくつものソースからの良い設計を組み合わせよう！"

私はAndreas Rumpfで、Nimの最初の発明者であり、現在も開発リーダーを務めています。
RustとC++に触発されてNimに導入された新機能であるムーブセマンティクスについてお話します。
では、はじめましょう。

Nimの非公式なモットーは、悪いデザインを真似することは良いデザインではない、ということです。
これはすでに有用なモットーで、何をすべきでないかを教えてくれています。
そうです、私たちは悪いデザインを真似るべきではありません。
また、何をすべきでないかを知ることよりも、何をすべきかを知ることの方が有用です。
これを言い換えると、いくつかのソースから良い部分を組み合わせるべきだということです。
そこで私たちは、RustやC++やSwiftがどのようにメモリ管理をしているのか、これらのコンセプトがNimにも適用できるのかどうかを調べました。
その結果、答えは「イエス」でした。

## モチベーション
```nim
var someNumbers = @[1, 2]
someNumbers.add 3
```
ここの例では2つの要素を持つ配列があり、そこに数字の3を追加しています。
これは可変長の配列です。C++ではvectorと呼ばれていますがNimではシーケンスと呼びます。

## メモリ上で起きていること
```
someNumbers

Length: 2     ┌──> 1
Capacity: 2   │    2
Data──────────┘
```
このグローバル配列は、長さと容量、そして可変長のメモリブロックへのシングルポインタを持っています。
数字を追加するときには、すでに容量が一杯になっているので、2つの要素の容量を持つようにする必要があります。

## メモリ上で起きていること（2）
```
someNumbers

Length: 3     ┌─/─> 1
Capacity: 4   │     2
Data──────────┤
              │
              └────>1
                    2
                    3
```

3つの数字を格納するのに十分な大きさの新しいメモリブロックを作成する必要があります。
そして、古いメモリブロックをどうにかする必要があります。
通常は再割り当て(realloc)のように、古いブロックをすぐに解放することになります。
これは最も効果的な方法です。


## 浅いコピー、コピー、ムーブ
```nim
var someNumbers = @[1, 2]
var other = someNumbers
someNumbers.add 3 # otherがダングリングポインタを持っている
```

しかし、これには問題があります。問題は、他の変数がこの変数への参照を持っている場合、ダングリングポインタにならないようにしなければいけないことです。
2行目で `other`という変数があり、その中身は`someNumbers`と同じであるべきだと言っています。
もし、浅いコピーですべてのビットをコピーしてしまうと、3行目の追加で無効になったポインタをコピーすることになり、ダングリングポインタを含んでしまうので、非常に危険で悪い実装です。

## 浅いコピー、コピー、ムーブ（2）
```nim
var someNumbers = @[1, 2]
var other = someNumbers
someNumbers.add 3 # otherがダングリングポインタを持っている
```

- 解決策1: 全く同じ内容の新しい配列を作る ("Deep" copy: C++98, これまでのNim)
- 解決策2: ポインタへの参照を持つポインタを作る (多くallocが発生し、遅い)
- 解決策3: 代入を禁止する
- 解決策4: GCによって古いポインタを掃除してもらう
- 解決策5: メモリを"盗み"、ブロック（の所有権）を**移動**させる

この問題を解決するためには、いくつかの解決策があります。
1つめはコンテナ内の要素をディープコピーすることで、これはC++がやっていることであり、通常のNimのセマンティクスでもあります。
2つめはポインタへのポインタを用意して新しい更新を受け取れるようにすることで、これはJavaやC#で行われています。しかしこれはかなり効率が悪く、別の間接処理が発生するからです。
3つめはこれは代入なんだけど、悪い代入だから禁止してしまおう、ということも可能です。
4つめの解決策は、先ほど言ったように、ガベージコレクタにこの悪いポインタを掃除してもらうか、他の変数がそれを参照していない場合のみ、そのポインタを掃除してもらうことです。
最後は、メモリブロックを盗んで移動させることができますし、これはC++でも可能です。（訳者注：C++でのムーブのこと。std::move）

## 明示的なムーブ
```nim
var someNumbers = @[1, 2]
var other = move(someNumbers)
# someNumbersは空になった
someNumbers.add 3

assert someNumbers == @[3]
```
これは明確な移動です。これにより「この数字を他の数字に移動させる」ということができ、その後"someNumbers"は無効になります。空の配列になります。
"someNumbers"に3を追加すると、その中に残っているのは6行目でわかるように、"3"が入っているだけです。
これが明示的な"ムーブ"です。このようなスタイルでプログラミングをすることができるのです。
あまり気持ちのいいものではありませんが、明示的であれば、"someNumbers "が空であることを意識できるので大丈夫です。
でも、暗黙的な"ムーブ"が使われる場合もたくさんあります。

## 暗黙的なムーブ
```nim
var a = f()
# 関数fの結果をaに"移動"させる
```
最初の例です。関数呼び出しの結果があれば、それがその後に使われることはないとわかっているので、変数aに直接移動させることができます。

## 暗黙的なムーブ（2）
```nim
var namedValue = g()
var a = f(namedValue) # namedValueをfに移動できる
# fの結果をaに移動できる
```

また、その後に使わないことが分かっている場合も、移動させることもできます。
設計上の目標のひとつは、関数呼び出しの結果が移動できることが分かっている場合に、それを実現することでした。
ただしその結果をNimで読みやすく、かつオーバーヘッドがないようにしたいのです。
"namedValue"がローカル変数である限り、Nimコンパイラは"namedValue"がf関数の呼び出しに使われたものであり、それ以降に使われたものではないことを認識することができます。
ということは、"namedValue "の値を"f"に移し、"f"の結果を "a "に移せばいいわけです。

## 暗黙的なムーブ（3）
```nim
var x = @[1, 2, 3]
var y = x # は'x'の最後の呼び出しなので、'y'に代入することができる
var z = y # は'y'の最後の呼び出しなので、'z'に代入することができる
```

もうひとつの例です。
3つの整数が入った配列があり、yがxだとすると、xはもう使われていないので、ムーブすることができます。
同様に、zに代入されるyもムーブできます。
これはローカル変数の場合に使えます。

## Sink引数
```nim
func put(t: var Table; key: string; value: seq[string]) =
  var h = hash(key)
  t.slots[h] = value # コピーを行っている (´･ω･`)

var values = @["a", "b", "c"]
tab.put("key", values)
```

ここで、put関数に渡された引数がその後で使われるかどうかわからないという問題を引き起こす場合について考えてみましょう。
この例は、ハッシュテーブルの実装の疑似コードのようなものです。
普通は2行以上になります。
このキーと値のペアを`t`に移動させたい場合は、その値をハッシュ化します。
そして、現在のセマンティクスを考えると、これはハイコストなコピー操作を行っています。

## Sink引数（2）
```nim
func put(t: var Table; key: string; value: sink seq[string]) =
  var h = hash(key)
  t.slots[h] = value # ムーブする (´∀｀*)

var values = @["a", "b", "c"]
tab.put("key", values) # valueの最後の使用箇所なので、ムーブができる
```
しかし、この引数にsinkキーワードのアノテーションを付けると、その後にもう使ってはいけないという制約ができ、呼び出し元にも強制させることができます。
このように、同じ引数を使用することで、その後に使用されないことがわかり、3行目のインラインの内部でムーブを実行することができるのです。
つまり、3つの文字列を内部に持つリストのような値を持っていて、その後にそれらを使用しない場合ムーブすることができます。

## Sink引数（3）
```nim
func put(t: var Table; key: string; value: sink seq[string]) =
  var h = hash(key)
  t.slots[h] = value # ムーブする (´∀｀*)

var values = @["a", "b", "c"]
tab.put("key", values) # 最後の呼び出しではないので、ムーブできない
echo values

>> Warning: Passing a copy to a sink paramater.
```
もし、その後に値を使ったらどうなるかというと、私達はこのオブジェクトの所有権を取得したいので、コンパイラは警告を発し、「このオブジェクトは後で使用されるので、安全のためにコピーを作成します」と伝えます。
これは設計基準にもなっていて、もし間違えるとパフォーマンスが落ちますが、変なクラッシュはせず、コンパイラは性能面について警告を出します。
ただ、この警告はちょっと強引すぎるような気もするので、もう少し改善する必要があります。

## Sink引数（4）
```nim
func put(t: var Table; key: string; value: sink seq[string]) =
  var h = hash(key)
  t.slots[h] = value # ムーブする (´∀｀*)

var values = @["a", "b", "c"]
echo values
tab.put("key", values)

>> Solution: Move code around.
```
ここで1つの解決策は、それを移動させることです。
このハッシュテーブルに埋め込む前に値をechoしておけば、コンパイラはechoが値の所有権を持ちたくないと知っているので、うまくいくはずです。
tab.putはsinkアノテーションのおかげで、valuesがその後で呼び出されないことがわかっています。
もちろん、これは一つの解決策で、デバッグのためにコードを追加するだけなら、コピーが増えようが増えまいが気にする必要はないでしょう。なぜなら、このコードはその後すぐに削除されるからです。

## Sinkのその他の例
- sink引数は最適化のためのものです
- 間違えた呼び出し方をすると、パフォーマンスに影響が出ます。
```nim
func `[]=`[K, V](t: var Table[K, V]; k: K, v: V)
func `==`[T](a, b: T):bool
func `+`[T](a, b: T): T
func add[T](s: var seq[T]; v: T)
```

sink引数は最適化のためのものであり、無理に使用する必要はありません。
もし間違えると、以前より性能が悪くなりますが、正しく使えば、より良いパフォーマンスが得られます。
また、プロパティにアノテーションを付ける必要がないように、慎重に取り組んでいます。
というのも、実際に標準ライブラリのあちこちにシンクのアノテーションを追加しようとすると、「そんなことはしない、コンパイラが解決してくれる」と言われてしまうからです。
というわけで、いくつか好きな例を挙げてみましょう。
ハッシュテーブルがあり、挿入や更新のためのセッター、あるジェネリクス型Tを比較するイコール、Tの加算、最後に、グローバルなシーケンスへの追加です。
問題はsinkのアノテーションをどこに置くかということなんですが、これは推測するまでもなく、私が教えてあげます。

## Sinkのその他の例（2）
```nim
func `[]=`[K, V](t: var Table[K, V]; k: sink K, v: sink V)
func `==`[T](a, b: T):bool
func `+`[T](a, b: T): T
func add[T](s: var seq[T]; v: sink T)
```

ハッシュテーブルに値を埋め込むにはsinkアノテーションが必要で、配列への追加もsinkアノテーションが必要です。
これらは、最初の行への挿入か更新かのソートです。
ハッシュテーブルに挿入する場合は、キーの所有権を取得したいのですが、テーブルの更新だけであれば、キーはすでに持っています。
その結果どうなるかというと、sinkを付けるべきかどうか、それはわかりません。
しかしsinkを付けると、コンパイラはすべてのケースでこの値が消費されることを保証するようになりますが、そこまでする必要はありません。
そして、何かを消費するというのはどういうことなのかという概念があるので、いずれにせよデストラクタについて説明しないといけません。

## ゲッター：値の借用
```nim
func get[K, V](t:Table[K, V]; key: K): V =
  var h = hash(key)
  result = t.slots[h] # コピーしている？
```
ここでは別の問題があります。ハッシュテーブルにいろいろなものを入れるのは非常に効果的でいいのですが、そこから値を取り出すのはどうしたらいいでしょうか。
この例もまた同じ問題です。この場合のresultはNimではreturn文と同じですが、これはハイコストなコピーであることがより明白になるように、私はそれを代入として書きました。

## ゲッター：値の借用（2）
```nim
func get[K, V](t:Table[K, V]; key: K): V =
  var h = hash(key)
  result = move(t.slots[h]) # コンパイルエラー
```
このソースをムーブさせようとすると、コンパイラはTはミュータブルでなく、ムーブはこの大元(変数t)を変異させるから、ムーブできない、と文句を言うでしょう。

## ゲッター：値の借用（3）
```nim
func get[K, V](t:var Table[K, V]; key: K): V =
  var h = hash(key)
  result = move(t.slots[h]) # コンパイルされるが、かなり危険
```
ではそれをミュータブルにしてみましょう。
これはうまくいくのですが、今度はこのテーブルから値を移動させたときに何が起こるかを考える必要があります。
それは一度だけアクセスすることができ、その後は消えてしまいます。
これはかなりまずいですね。
スタックにポップオペレーションがあれば話は別ですが、ハッシュテーブルの場合はかなりまずいです。

## ゲッター：値の借用（4）
```nim
func get[K, V](t: Table[K, V]; key: K): lent V =
  var h = hash(key)
  result = t.slots[h] # コピーでもムーブでもなく、"借用"
```
私達には値や長さVを貸し出す別のアノテーションが必要で、これは借用です。
Rustでは、これは借用コピーポインタになります。C++ではrefですが実態は同じものです。
一旦借用したら、これがコレクションのライフタイムより長くならないことを確認する必要があります。
つまり、Rustではチェックされ、C++ではチェックされないということです。Nimではチェックされますが、もっとうまくやる必要があります。

## 参照カウント
- これまでどのように最適化が偽のコピーを取り除くかを見てきました
- 同じ原理が参照カウント(=RC)にも適用されます
- 参照のコピー → incRc(src); decRc(dest); dest = src
- 参照の移動 → dest = src
- これが`--gc:arc`モードの開発につながりました

ディープコピーなど複雑な代入を最適化する方法を理解した今、この知識を他のものに応用することができます。例えば参照カウントです。
参照カウントは基本的に、ポインタの割り当てが以前よりずっとハイコストになっただけです。なぜならポインタをコピーする場合、ソースの参照カウントをインクリメントしなければならず、そしてコピー先の参照カウントをデクリメントする必要があります。
ポインタのコピーもできますが、もしポインタをムーブさせることができれば、ビット単位のコピーで済みますし、必要であれば、その後ソースをnilにすることもできます。
これはつまりGCと呼ばれていますが、GCは実際にはあらゆる種類のメモリ管理のための名前なのです。

## ARC
```nim
include prelude

type
  Node = ref object
    le, ri: Node

proc checkTree(n: Node): int =
  if n.le == nil: 1
  else: 1 + checkTree(n.le) + checkTree(n.ri)

proc makeTree(depth: int): Node =
  if depth == 0: Node(le: nil, ri: nil)
  else: Node(le: makeTree(depth-1), ri: makeTree(depth-1))
```
ここにベンチマークがあります。
これはバイナリです。ガベージコレクタのスループットの標準的なベンチマークです。
このすべてを理解する必要はありません。
でも重要なのは、ここには`sink`や`lent`のようなアノテーションがないことです。
バイナリツリーを作って、それを何兆個も作っていけば、ある程度の深さまで到達します。

## ARC(2)
```nim
proc main =
  let maxDepth = parseInt(paramStr(1))
  const minDepth = 4
  let stretchDepth = maxDepth + 1
  echo("stretch tree of depth ", stretchDepth, "\t check: ", checkTree(makeTree(stretchDepth)))
  let longLivedTree = makeTree(maxDepth)
  var iterations = 1 shl maxDepth
  for depth in countup(minDepth, maxDepth, 2):
    var check = 0
    for i in 1..iterations:
      check += checkTree(makeTree(depth))
    echo iterations, "\t trees of depth ", depth
    iterations = iterations div 4

main()
```
これがメインとなる部分ですが、標準的なベンチマークで、結果は実に素晴らしいものです。

## ベンチマーク：処理能力
|Memory management strategy|Time|Peak Memory|
|---|---|---|
|mark&sweep GC|17s|588.047MiB|
|deferred refcounting GC|16s|304.074MiB|
|Boehm GC|12s|N/A|
|ARC|**6.75s**|472.098MiB|

ガベージコレクタがいくつかあるので、それらをすべて比較することができますし、新しいものは、3倍とか2倍とか、比較したいものによってかなり高速になります。
メモリ消費量もbohemのGCとほぼ同じですが、メモリ消費量を正確に把握できていないので、その点は不明です。
問題は、これが以前より非常に良くなったということですが、手動でのメモリ管理と比べてどうなのかです。

## 手動メモリ管理
```nim
include prelude

type
  Node = ptr object
    le, ri: Node

proc checkTree(n: Node): int =
  if n.le == nil: 1
  else: 1 + checkTree(n.le) + checkTree(n.ri)

proc makeTree(depth: int): Node =
  result = cast[Node](alloc(sizeof(result[]))) # 12行目
  if depth == 0:
    result.le = nil; result.ri = nil
  else:
    result.le = makeTree(depth-1)
    result.ri = makeTree(depth-1)

proc freeTree(n: Node) =
  if n != nil:
    freeTree(n.le); freeTree(n.ri); dealloc(n)
```

Nimは両方できるので、自分でポインタを管理することができます。以前はこれはインラインの参照でしたが、今はポインタになり、ツリーを作るために12行目でキャストを使った厄介な割り当てをしています。
もちろんツリーを手動で解放する必要があります。これは再帰的解放で、まず左を解放し、次に右を解放して、このノードを割り当てます。

## 手動メモリ管理（2）

```nim
proc main =
  let maxDepth = parseInt(paramStr(1))
  const minDepth = 4
  let stretchDepth = maxDepth + 1
  let stree = makeTree(stretchDepth)
  echo("stretch tree of depth ", stretchDepth, "\t check:",
    checkTree(stree))
  let longLivedTree = makeTree(maxDepth)
  var iterations = 1 shl maxDepth
  for depth in countup(minDepth, maxDepth, 2):
    var check = 0
    for i in 1..iterations:
      let tmp = makeTree(depth)
      check += checkTree(makeTree(tmp))
      freeTree(tmp) # 15行目
    echo iterations, "\t trees of depth ", depth
    iterations = iterations div 4
  freeTree(longLivedTree); freeTree(stree) # 18行目

main()
```
そしてメインパートでは、これらのツリーを手動で解放しなければなりません。例えば18行目では非常に厄介な処理を書いています。
更に15行目では、後で使えるようにするためにtmp変数を解放しなければなりませんでした。

## ベンチマーク：処理能力
|Memory management strategy|Time|Peak Memory|
|---|---|---|
|mark&sweep GC|17s|588.047MiB|
|deferred refcounting GC|16s|304.074MiB|
|Boehm GC|12s|N/A|
|ARC|**6.75s**|472.098MiB(379.074MiB)|
|manual|5.23s|244.563MiB|
|manual(with RC)|6.244s|379.074MiB|

これがその結果です。まだ遅いですね、残念です。
しかしARCが実際にやっていることは参照カウントを最適化することで、マニュアル版ではスマートポインタがあるので基本的に参照カウントはしていません。
この参照カウントのためにマシンワードを追加した場合、マニュアル版では6.2秒とほぼ同じになりますが、ARCは6.7秒になります。
メモリ消費量は、残っているこの1つを直したという前提で同じです。
手動でのメモリ管理のパフォーマンスに近づきつつあるので、これを入れています。
しかしこのベンチマークは、誤差レベルになるまでチューニングできると思います。

## ベンチマーク：レイテンシ
|Memory management strategy|Latency|Total Time|Peak Memory|
|---|---|---|---|
|defferd refcountng GC|0.0356ms|0.314s|300MiB|
|ARC|0.0106ms|0.254s|271MiB|

こちらはレイテンシのための別のベンチマークです。
ソースコードはありませんが、以前はソフトリアルタイムガベージコレクタを使っていて、このベンチマークでのレイテンシは0.03ミリ秒でした。
それがARCでは3倍以上改善され、総実行時間も短縮されました。
また、ピーク時のメモリ消費量も改善されています。
スループットだけでなく、レイテンシも向上しています。

## カスタムコンテナ
- カスタムデストラクタ、代入と移動の最適化
- ファイル/ソケットなどを自動的にクローズできる（C++やRustのように）
- 特殊なメモリ管理手法を合体できる

すでに概要を説明しましたが、ブラックボックスの中で何が行われているかというと、デストラクタやムーブの演算子、代入があります。
これらを他のところにも使うことができます。
すぐに思いつくように、例えばファイルを自動的に閉じるようにすることもできます。
以前は手動メモリ管理とGCメモリ管理がありましたが、混在させるとうまく機能しないので注意しなければなりませんでした。
しかしこの拡張ポイントによって、これら手動メモリ管理とGCの世界の間への割り込みが以前よりずっとよくなりました。

## オブジェクトプール
```nim
include prelude

type
  NodeObj = object
    le, ri: Node
  Node = ptr NodeObj

  PoolNode = object
    next: ptr PoolNode
    elems: UncheckedArray[NodeObj]

  Pool = object
    len: int
    last: ptr PoolNode
    lastCap: int
```

ここでもうひとつ、私達にはまだできることがあります。
同じベンチマークですが 今度はオブジェクトプールを用意します。アリーナと呼びましょう。
アリーナのアロケータは、内部に2つのポインタしか持たない3つのノードを扱っています。

※訳者注：
C++のメモリ管理手法に「Arena Allocation」というものがあり、これはNimでの実装である。

> Project Snowflake に代わって1つ有望視されているのは、 Arena Allocation という手法です。
> [Protocol Buffersの C++ 版](https://developers.google.com/protocol-buffers/docs/reference/arenas)がこの手法によるメモリ管理を提供しているんですが、それを .NET にも導入できないかという調査をしているみたいです。 まだあんまりドキュメントがなく、QConSFの登壇で軽く紹介された程度ですが。
> [CLR/CoreCLR: How We Got Here & Where We're Going](https://qconsf.com/sf2018/presentation/clrcoreclr-how-we-got-here-where-were-going)
> これも、「ある程度まとまった単位でごっそり処理する方が高効率」という原理に則ったものです。 以下のように、「ごっそり消す」タイミングを明示するような方式。 メモリ放棄のまとまった単位を指して arena (舞台、競技場、界)と呼んでいます。

引用元：https://ufcpp.net/blog/2018/12/futurememorymanagement/


## オブジェクトプール（2）
```nim
proc newNode(p: var Pool): Node =
  if p.len >= p.lastCap:
    if p.lastCap == 0: p.lastCap = 4
    elif p.lastCap < 65_000: p.lastCap *= 2
    var n = cast[ptr PoolNode](alloc(sizeof(PoolNode) *
      p.lastCap * sizeof(NodeObj)))
    n.next = nil
    n.next = p.last
    p.last = n
    p.len = 0
  result = addr(p.last.elems[p.len])
  p.len += 1
```

新しいノードを割り当てるには、基本的にシーケンスのように容量が残っているかどうかをチェックします。
そしてノード自体はチェックされていないポインタなので、ノードのバックアップストレージである配列の要素のアドレスを取得します。

## オブジェクトプール（3）
```nim
proc `=`(dest: var Pool; src: Pool) {.error.}

proc `=destroy`(p: var Pool) =
  var it = p.last
  while it != nil:
    let next  = it.next
    dealloc(it)
    it = next
  p.len = 0
  p.lastCap = 0
  p.last = nil
```

ここでもしプールをコピーしたいのであれば、それは実装されていないのでサポートされていないと言えるでしょう。
さらに、誤ってプールを丸ごとコピーしようとすると、コンパイラは文句を言って「できない」と言うでしょう。
そしてプールがスコープを抜けるとデストラクタが呼ばれるのですが、デストラクタで何をするかというとこれらのメモリブロックを解放します。しかしこれらはこの次のポインタがあるリンクリストに連結されています。

## オブジェクトプール（4）
```nim
proc checkTree(n: Node): int =
  if n.le == nil: 1
  else: 1 + checkTree(n.le) + checkTree(n.ri)

proc makeTree(p:var Pool; depth: int): Node =
  result = newNode(p)
  if depth == 0:
    result.le = nil
    result.ri = nil
  else:
    result.le = makeTree(p, depth-1) # 11行目
    result.ri = makeTree(p, depth-1) # 12行目
```

そうすると残念ながらプログラムを変更する必要があります。
ですからもしツリーを作りたいのであれば、このプールから新しいノードを取得することを意識しなければなりません。
これはツリーを作るときの引数になり、11行目、12行目にあるように、再帰的に渡す必要があります。

## オブジェクトプール（5）
```nim
proc main =
  let maxDepth = parseInt(paramStr(1))
  const minDepth = 4
  let stretchDepth = maxDepth + 1
  var longLived: Pool # 5行目
  let stree = makeTree(longLived, maxDepth)
  echo("stretch tree of depth ", stretchDepth, "\t check ",
    checkTree(stree))
  let longLivedTree = makeTree(longLived, maxDepth)
  var iterators = 1 shl maxDepth
  for depth in countup(minDepth, maxDepth, 2):
    var check = 0
    for i in 1..iterators:
      var shortLived: Pool # 14行目
      check += checkTree(makeTree(shortLived, depth))
    echo iterators, "\t trees of depth ", depth
    iterators = iterators div 4

main()
```

ベンチマークではこのプールは後から自動的に解放されるので、ちょっと使いやすくなりました。
この場合、5行目と14行目に書かれているように、長寿命データ用(longLived)と短寿命データ用（shortLived）の2つのプールを作る必要がありました。

## ベンチマーク：処理能力
|Memory management strategy|Time|Peak Memory|
|---|---|---|
|mark&sweep GC|17s|588.047MiB|
|deferred refcounting GC|16s|304.074MiB|
|Boehm GC|12s|N/A|
|ARC|6.75s|472.098MiB(379.074MiB)|
|manual|5.23s|244.563MiB|
|manual(with RC)|6.244s|379.074MiB|
|object pooling|**2.4s**|251.504MiB|

その性能はどうなったでしょうか。
その結果、2倍以上の性能向上で、メモリ消費量もほぼ同じでした。

## まとめ

- 所有権の移動は開発者には見えないところで動きます
- `sink` と `lent` のキーワードは任意です
- 信じられないほどのスピードアップとアルゴリズムの改良につながります
- Nim をより速く、"決定論的"にします
- 新しい戦略が以下を改善します
  - 処理速度
  - レイテンシ
  - メモリ消費
  - スレッド
  - コーディングの容易さ
  - 柔軟な構成

要約すると、ムーブセマンティクスは私たちには見えないとこで働いてくれているのです。
本当に良い最適化をしてくれます。
速度が向上し、メモリ管理を決定論的にすることができます。
実際これまでの例では、参照カウントを最適化すると、プログラミング言語にコストモデルを付加することができます。
一度この技術を使えば、Nimをハードなリアルタイムシステムに利用することができます。
この技術が、スループット、レイテンシ、メモリ消費量、スレッディングが改善されることを確認してきました。
また、具体的な例は今回はありませんが、例えばあるスレッドから別のスレッドにデータを移動させることができれば、Rustが実際にそうしているように、データ競合が起きないことが保証されることが想像できるかと思います。これはとても素晴らしいことです。
そして、ファイルが自動的に閉じられたり、ソケットが閉じられたりするのを考えれば、プログラミングがもっと簡単になることも想像できるでしょう。
つまり、私達は異なるクラスの間でより良い構成が得られるのです。

## Happy hacking!ーハックを楽しもう！
今回のベンチマーク測定に使ったソースコードはこちらから見ることができます。  
https://github.com/Araq/fosdem2020

|||
|---|---|
|Website|https://nim-lang.org/|
|Forum|https://forum.nim-lang.org/|
|Github|https://github.com/nim-lang/Nim|
|IRC|https://webchat.freenode.net/?channels=nim|

## 訳者あとがき
いかがでしたでしょうか。これがNim作者であるAraqが求めるNimでのメモリ管理です。
この講演が行われた2020年2月5日当時ではまだここで挙げられているARCのメモリ管理手法は使えませんでしたが、その後2020年4月3日のv1.2のリリースからサポートされ、2020年10月16日のv1.4のリリースからはARCを更に循環参照にも対応できるようにしたORCというメモリ管理手法が使えるようになりました。AraqはNimのデフォルトのメモリ管理手法を参照カウントからORCに切り替えられるように、日々研究を続けているようです。

NimではRustの所有権モデルやC++のスマートポインタを用いたムーブセマンティクスなど参考にして、高いパフォーマンスが発揮できるプログラミング言語となっています。
`sink`や`lent`と言ったアノテーションを引数に対して使い、Rustと同じモデルで所有権に基づくプログラミングをすれば、通常の参照カウントよりも大幅にパフォーマンスが向上することができました。
Nimではそれを更に進めて、ARCモードでコンパイルを実行すれば、所有権モデルについて開発者が気にして`sink`や`lent`のアノテーションを用いる必要がなく、同じだけのパフォーマンスを実現できるようになっています。

更にオブジェクトプールを使うことでARCから3倍の効率化ができます。こちらは明示的にオブジェクトプールを使ったプログラミングが必要ですが、特にハードなリアルタイムシステム向けのチューニングもできるようになっています。

これを読んだ読者の中から一人でも多くNimを使った開発を始めてくれることを心から願っています。
