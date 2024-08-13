---
title: "Nimのメモリ管理を理解する③ ― GCなしのNim"
emoji: "👑"
type: "idea" # tech: 技術記事 / idea: アイデア
topics: ["nim", "GC", "メモリ管理"]
published: true
---

この記事はNimのメモリ管理を理解するシリーズの3作目になります。今回は2020年8月30日に公開された、[Nim without GC](https://nim-lang.org/araq/destructors.html)という記事を翻訳して、Nimのメモリ管理について更に理解を進めていこうと思います。
ただしこの記事が書かれたのは1系がリリースされる前の2020年時点での内容で古いため、現在では更により良いアプローチが取られている可能性があります。この記事は初期の思想を理解するために留め、より続編の記事を参照してください。

---

〜Nimのメモリ管理を理解するシリーズ〜
- [Nimのメモリ管理を理解する① ― Nimの新しいGC、ARCについて](https://qiita.com/dumblepy/items/be660c17556d73aa3570)
- [Nimのメモリ管理を理解する② ― Nimのムーブセマンティクス](https://zenn.dev/dumblepy/articles/af2b2b9f8fd890)
- [Nimのメモリ管理を理解する③ ― GCなしのNim](https://zenn.dev/dumblepy/articles/0dcbc08aed1a25)
- [Nimのメモリ管理を理解する④ ― ORC - アルゴリズムによるアドバンテージ](https://zenn.dev/dumblepy/articles/efffa86d9177b1)
- [Nimのメモリ管理を理解する⑤ ― ムーブセマンティクスとデストラクタ](https://zenn.dev/dumblepy/articles/92bdd7afe1fc29)

---

## NimのGCなしでの開発

ParaSail、最新のC++、そしてRustには共通点があります。それは、「ポインタなしのプログラミング」に焦点を当てていることです（まあ、Rustはちょっと違うかもしれませんが、似たような仕組みを使っています）。今回の記事では、Nimをこの方向に進める方法を探っていきます。目標は以下の通りです：

- GC（ガベージコレクション）なしでメモリの安全性を確保する。
- スレッド間でデータをやり取りする際の効率を向上させる。
- 優れたパフォーマンスを持つコードを書きやすくする。
- よりシンプルなプログラミングモデルを提供する：ポインタは別名参照を導入し、プログラムを理解しにくくし、最適化を困難にします。これを解消します。

タイトルが示している通り、今回はポインタを排除することで、この理想のプログラミングの世界に到達します。もちろん、低レベルのプログラミングではNimの`ptr`型が必要ですが、標準ライブラリでは`ref`を可能な限り使わないようにします（`ref`は将来的にはアトミックな参照カウントポインタになるかもしれません）。この結果、`nil`の問題も解消されます。`ref object`の代わりに`object`をより多く使い、これにより`var`と「varなし」の区別がより頻繁に使われることになります。これもまた利点です。

## NimのGCの問題点とは？
基本的に問題はないのですが（GCに関して、ここで探っている代替手段よりも高速である可能性が高いです）、Nimのエコシステム外のものとの互換性を難しくしているという点が問題です。

- Pythonには独自のGCがあり、NimのDLLをPythonに読み込ませることは可能ですが、GCの保守的なスタックスキャンが動作するように特別なコードを追加しなければならないのは面倒です。
- C++のゲームエンジンはRAII（Resource Acquisition Is Initialization）に基づいており、Nimの`ref object`でC++のデストラクタをGCのファイナライザで呼び出すとオーバーヘッドが発生します。これはほぼすべての大規模なCやC++プロジェクトに当てはまります。
- Emscriptenのような珍しいターゲットでは保守的なスタックスキャンが失敗することがあります（ただし、回避策は存在します）。
- 私はこれまでにGC関連のバグを修正したり、GCを最適化したりするために多くの時間を費やしましたが、メモリリークや破損を追いかけるよりも遥かに多かったです。メモリの安全性は譲れませんが、ますます複雑になるランタイムを使用せずにそれを達成する方法を模索すべきです。

## コンテナ
> ※コンピュータプログラミングにおいて、コンテナとはオブジェクトの集まりを表現するデータ構造、抽象データ型またはクラスの総称である。
> よく知られたものには、配列、テーブル、連想配列、集合などがある
> [コンテナ (データ型)](https://ja.wikipedia.org/wiki/%E3%82%B3%E3%83%B3%E3%83%86%E3%83%8A_(%E3%83%87%E3%83%BC%E3%82%BF%E5%9E%8B))

Nimのコンテナは値型（Value Type）にすべきです。明示的なムーブセマンティクスと特別な最適化により、コピーの大部分を排除します。

ほぼすべてのコンテナは、保持している要素の数を管理します。`nil`の代わりに`len == 0`という状態を持つことで、クラッシュしにくくなります。また、コンテナがムーブされると、その長さは0になります。

## スライシング
文字列やシーケンスはO(1)でスライスをサポートし、他のコンテナも内部を「ビュー」として扱うことができます。スライスは所有権の明確なセマンティクスを崩すため、`openArray`のようにパラメータに限定される可能性があります。

## Opt
木構造を構築するためにポインタは必要ありません。`seq`で同じことができます：

```nim
type
  Node = object  ## ここで``ref``がないことに注目してください
    children: seq[Node]
    payload: string
```

ただし、1つまたは0のエントリしか必要ない場合、`seq`は過剰になります。`opt`は、満杯か空かの状態を持つコンテナで、他の言語でよく知られているOption型に似ています。

```nim
type
  Node = object  ## ここで``ref``がないことに注目してください
    left, right: opt[Node]
    payload: string
```

`opt[Note]`は内部でポインタを使用していますが、これは非公開なので、値のセマンティクスは破壊されません。`opt[T]`はコピーとムーブの区別を遵守するユニークポインタと言えます。

## デストラクタ、代入、ムーブ
現在のNimでは、`shallowCopy`を使用してムーブをサポートしていますが、これは少し醜いので、今後はムーブを<-と記述します。ただし、<-は実際には新しい演算子ではなく、例の中でムーブが発生する場所を強調するために使用しています。

値セマンティクスにより、オブジェクトのライフタイムを容易に判断できるようになります。スコープを出ると、そのオブジェクトに関連するリソースが解放され、デストラクタが呼び出されます。もしムーブされた場合（エスケープした場合）、オブジェクトやコンテナの内部状態がこれを反映し、破棄が防止されます。最適化パスはデストラクタ呼び出しを削除することが許可され、同様にコピー伝播パスは代入を削除することが許可されます。

破棄はスコープ終了時と代入時の2か所で発生する可能性があります。`x = y`は「xを破棄してからyをxにコピーする」ことを意味しますが、これはしばしば非効率です：

```nim
proc put(t: var Table; key, val: string) =
  # ハッシュテーブル実装の概要：
  let h = hash(key)
  # これらは破壊的代入です：
  t.a[h].key = key
  t.a[h].val = val

proc main =
  let key <- stdin.readLine()
  let val <- stdin.readLine()
  var t = createTable()
  t.put key, val
```

このコードでは、`readLine`呼び出しによって2つの文字列が構築され、それがテーブル`t`にコピーされます。`main`のスコープが終了すると、元の文字列`key`と`val`は解放されます。

このナイーブなコードでは、2回のコピーと4回の破棄が発生します。`swap`を使用することで、これを大幅に改善できます。

```nim
proc put(t: var Table; key, val: var string) =
  # ハッシュテーブル実装の概要：
  let h = hash(key)
  swap t.a[h].key, key
  swap t.a[h].val, val

proc main =
  var key <- stdin.readLine()
  var val <- stdin.readLine()
  var t = createTable()
  t.put key, val
```

このコードは、必要最小限の2回の破棄しか行いません。しかし、この方法は少し醜く、`key`と`val`を`var`にすることを強制され、テーブル`t`にムーブされた後もアクセスでき、古いテーブルのエントリを含んでいます。これは時折便利ですが、より頻繁には`let`を保持し、ムーブされた後に値にアクセスするとコンパイル時エラーを発生させたいと考えるでしょう。

これを可能にするのがsinkパラメータです。sinkパラメータはvarパラメータに似ていますが、`let`変数を渡すことができ、その後、単純な制御フロー分析によってその場所へのアクセスが禁止されます。sinkを使うと、以下のようになります。

```nim
proc put(t: var Table; key, val: sink string) =
  # ハッシュテーブル実装の概要：
  let h = hash(key)
  swap t.a[h].key, key
  swap t.a[h].val, val

proc main =
  let key

 <- stdin.readLine()
  let val <- stdin.readLine()
  var t = createTable()
  t.put key, val
```

あるいは、`let`を`var`パラメータに渡すことを許可し、それがムーブを意味するようにしてもよいでしょう。

ちなみに`let key = stdin.readLine()`は常に`let key <- stdin.readLine()`に変換されます。

## コピーをムーブに最適化する
この例を考えてみましょう：

```nim
let key = stdin.readLine()
var a: array[10, string]
a[0] = key
echo key
```

`key`が代入`a[0] = key`の後にアクセスされるため、それは配列スロットにコピーされなければなりません。しかし、`echo key`文がなければ、その値はムーブされます。そして、これがコンパイラによって行われます。ムーブとコピーの区別を曖昧にすることで、コードは「摩擦」なく進化できます。

## 破棄
すべての構築には破棄がペアになっている必要があり、メモリリークを防ぎます。また、破棄は一度だけ行われる必要があり、これにより破損を防ぎます。このモデルからメモリ安全性を得る秘訣は、破棄の呼び出しが常にコンパイラによって挿入されることにあります。

しかし、構築とは何でしょうか？Nimには従来のコンストラクタはありません。その答えは、すべてのプロックの結果が構築とみなされることです。これは大きな損失ではありません。なぜなら、戻り値は高性能コードにはあまり適していないからです。この点については後ほど詳しく説明します。

## 破棄のコード生成
ナイーブな破棄（単純に設計された破棄処理）は、再帰的に動作することがあります。これが原因で、処理が繰り返されてスタックが溢れてしまう「スタックオーバーフロー」が発生することがあります。特に、リアルタイムシステムでは、こうしたスタックオーバーフローによって、処理が遅れて予定された時間内に完了できない可能性があります。したがって、デフォルトのコード生成では、メモリアロケータと連携する明示的なスタックを使用して遅延解放を実装します。あるいは、`lazyDestroy`プロックを導入し、戦略的な場所で使用することもできます。実装は以下のようになります：

```nim
type Destructor = proc (data: pointer) {.nimcall.}

var toDestroy {.threadvar.}: seq[(Destructor, pointer)]

proc lazyDestroy(arg: pointer; destructor: Destructor) =
  if toDestroy.len >= 100:
    # 破棄待ちのデストラクタ呼び出しが多すぎる場合、即時実行：
    destructor(arg)
  else:
    toDestroy.add((destructor, arg))

proc `=destroy`(x: var T) =
  lazyDestroy cast[pointer](x), proc (p: pointer) =
    let x = cast[var T](p)
    `=destroy`(x.le)
    `=destroy`(x.ri)
    dealloc(p)

proc constructT(): T =
  if toDestroy.len > 0:
    let (d, p) = toDestroy.pop()
    d(p)
```

これは実際には「オブジェクトプーリング」の一種です。

## ムーブのルール
これらの洞察を得たので、コピー、ムーブ、および破棄が発生する正確なルールを記述できます。

|ルール|パターン|意味|
|---|-------|-------|
|1|var x; stmts|var x; try stmts finally: destroy(x)|
|2|x = f()|move(x, f())|
|3|x = lastReadOf z|move(x, z)|
|4|x = y|copy(x, y)|
|5|f(g())|f((move(tmp, g()); tmp)); destroy(tmp)|

`var x = y`は`var x; x = y`として扱われます。`x`、`y`は任意の位置、`f`および`g`は任意の数の引数を取るルーチン、`z`はローカル変数です。

現在の実装では、`lastReadOf z`は「zが一度だけ読み書きされ、それが同じ基本ブロック内で行われる」として近似されています。後のバージョンのNimコンパイラは、このケースをより正確に検出します。

ここでの重要な洞察は、代入が「正しいことをする」いくつかの異なるセマンティクスに分解されるということです。したがって、コンテナは組み込みの代入を活用するように書かれるべきです！

これが何を意味するかを理解するために、C++を見てみましょう。C++では、ムーブとコピーが区別されており、この区別はAPIに反映されています。例えば、`std::vector`には次のようなメソッドがあります。

```cpp
void push_back(const value_type& x); // 要素をコピーする
void push_back(value_type&& x); // 要素をムーブする
```

Nimでは、`template`機能のおかげでこれよりも優れた方法が可能です（これはC++のテンプレートとは無関係です）。

```nim
proc reserveSlot(x: var seq[T]): ptr T =
  if x.len >= x.cap: resize(x)
  result = addr(x.data[x.len])
  inc x.len

template add*[T](x: var seq[T]; y: T) =
  reserveSlot(x)[] = y
```

`add`がテンプレートであるおかげで、最終的な代入はコンパイラから隠されず、最も効果的な形式が使用されます。実装では安全でない`ptr`および`addr`構文を使用していますが、言語のコアコンテナがこれを行うことは一般に受け入れられています。

このコンテナの書き方は、より複雑なケースでも機能します。

```nim
template put(t: var Table; key, val: string) =
  # 'key'を一度だけ評価することを保証：
  let k = key
  
  let h = hash(k)
  t.a[h].key = k    # ムーブ（ルール3）
  t.a[h].val = val  # ムーブ（ルール3）

proc main =
  var key = stdin.readLine() # ムーブ（ルール2）
  var val = stdin.readLine() # ムーブ（ルール2）
  var t = createTable()
  t.put key, val
```

ルール3のおかげで、`t.a[h].key = k`がムーブに変換されます。`k`はその後再利用されないためです。（一時変数`k`を完全に最適化する話はまた別の機会にします。）

これらの新しい洞察を踏まえると、sinkパラメータはまったく不要であると仮定します。これにより、言語がシンプルになります。

## ゲッター
テンプレートは、ゲッターによって導入されるコピーを避けるのにも役立ちます。

```nim
template get(x: Container): T = x.field

echo get() # コピーなし、ムーブなし
```

ここで`template get`を`proc get`に置き換えると、ルール5が適用され、次のようになります。

```nim
proc get(x: Container): T =
  copy result, x.field

echo((var tmp; move(tmp, get()); tmp))
destroy(tmp)
```

## 文字列
以下に、新しいスキームを使用してNimの標準文字列を実装する方法の概要を示します。コードは非常に直感的ですが、常に2つのことを念頭に置く必要があります：

- 代入やコピーは、古い代入先を破棄する必要があります。
- 自己代入は正しく動作する必要があります。

```nim
type
  string = object
    len, cap: int
    data: ptr UncheckedArray[char]

proc add*(s: var string; c: char) =
  if s.len >= s.cap: resize(s)
  s.data[s.len] = c

proc `=destroy`*(s: var string) =
  if s.data != nil:
    dealloc(s.data)
    s.data = nil
    s.len = 0
    s.cap = 0

proc `=move`*(a, b: var string) =
  # もう生存していないオブジェクトに対しては最適化されることを期待します：
  if a.data != nil and a.data != b.data: dealloc

(a.data)
  a.len = b.len
  a.cap = b.cap
  a.data = b.data
  # すでに破棄されたオブジェクトに対してはこれらが最適化されることを期待します：
  b.len = 0
  b.cap = 0
  b.data = nil

proc `=`*(a: var string; b: string) =
  if a.data != nil and a.data != b.data:
    dealloc(a.data)
    a.data = nil
  a.len = b.len
  a.cap = b.cap
  if b.data != nil:
    a.data = alloc(a.cap)
    copyMem(a.data, b.data, a.cap)
```

残念ながら、シグネチャが一致しません。`=move`は2つのvarパラメータを取りますが、変換ルールによれば`move(a, f())`や`move(a, lastRead b)`が生成され、これらはアドレス指定可能な位置ではありません！そのため、異なる型にバインドされた演算子`=sink`が必要であり、代わりに使用されます。

```nim
proc `=sink`*(a: var string, b: string) =
  if a.data != nil and a.data != b.data: dealloc(a.data)
  a.len = b.len
  a.cap = b.cap
  a.data = b.data
```

コンパイラは`sink`のみを呼び出します。`move`はプログラマーの明示的な最適化です。通常は`swap`操作としても記述できます。

## 戻り値は有害である
Nimの標準ライブラリには、`toString $`演算子のための以下のようなコーディングパターンが含まれています：

```nim
proc helper(x: Node; result: var string) =
  case x.kind
  of strLit: result.add x.strVal
  of intLit: result.add $x.intVal
  of arrayLit:
    result.add "["
    for i in 0 ..< x.len:
      if i > 0: result.add ", "
      helper(x[i], result)
    result.add "]"

proc `$`(x: Node): string =
  result = ""
  helper(x, result)
```

（Node型の宣言は読者の練習問題として残します。）この`helper`プロックを使った回避策の理由は、`result: var string`、つまり一つの文字列バッファに追加し続けることができるからです。ナイーブな実装では、それぞれが多くの割り当てと連結を生み出します。結果を直接（またはこの場合は追加して）構築することで、はるかに効率的になります。

今、この文字列をHTMLページのような大きな文脈に埋め込みたいとします。実際には`helper`が速度の点でより有用なインターフェースです。これは、プロックがインプレースで動作するべきか、新しい値を返すべきかという古い質問に対する答えです。

過剰なインプレース操作は、完全にステートメントベースのコードスタイルに導き、データフローをより難しくします。それに対し、より関数型プログラミング的な表現ベースのスタイルはそうではありません。Nimが必要とするのは、表現ベースのスタイルからステートメントスタイルへの変換です。この変換は非常に簡単で、次のようなプロックがあったとします：

```nim
proc p(args; result: var T): void
```

この最終パラメータを省略して呼び出すと、`p(args)`は`(var tmp: T; p(args, tmp); tmp)`に書き換えられます。理想的には、ネストされた呼び出しにおいて最小限の必要な一時変数を導入しますが、そのような最適化はまだ先の話であり、より効率的なバージョンを直接記述することが常に選択可能です。

## 実体化（Reification）
セカンドクラス型や`var`、あるいは仮想的な`sink`のようなパラメータ渡しのモードには、オブジェクトに入れることができないという問題があります。これは、スレッドやタスキングシステムの「実体化」が必要なため、タスクオブジェクトに引数リストを変換し、それをキューやスレッドに送信する必要があるため、当初は考えていたよりも深刻な問題です。実際、現在のNimでは、`await`や`spawn`は`var`パラメータを持つプロックの呼び出しをサポートしておらず[^1]、そのようなパラメータをクロージャにキャプチャすることすらできません！現在の回避策は、これに`ptr`を使用することです。おそらく誰かがより良い解決策を考えるでしょう。

[^1]: これは現在では全てサポートされています。
