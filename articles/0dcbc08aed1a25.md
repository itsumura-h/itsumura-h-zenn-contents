---
title: "Nimのメモリ管理を理解する③ ― GCなしのNim"
emoji: "👑"
type: "idea" # tech: 技術記事 / idea: アイデア
topics: ["nim", "GC", "メモリ管理"]
published: true
---

この記事はNimのメモリ管理を理解するシリーズの3作目になります。今回は2020年8月30日に公開された、[Nim without GC](https://nim-lang.org/araq/destructors.html)という記事を翻訳して、Nimのメモリ管理について更に理解を進めていこうと思います。
ただしこの記事が書かれたのは1系がリリースされる前で古いため、現在では更により良いアプローチが取られている可能性があります。この記事は初期の思想を理解するために留め、より続編の記事を参照してください。

---

〜Nimのメモリ管理を理解するシリーズ〜
- [Nimのメモリ管理を理解する① ― Nimの新しいGC、ARCについて](https://qiita.com/dumblepy/items/be660c17556d73aa3570)
- [Nimのメモリ管理を理解する② ― Nimのムーブセマンティクス](https://zenn.dev/dumblepy/articles/af2b2b9f8fd890)
- [Nimのメモリ管理を理解する③ ― GCなしのNim](https://zenn.dev/dumblepy/articles/0dcbc08aed1a25)

---

## GCなしのNim
ParaSail、"モダン"C++、Rustの共通点は何でしょうか？これらは「ポインタフリープログラミング」に焦点を当てています（Rustはそうではないかもしれませんが、似たようなメカニズムを使っています）。この記事では、Nimをこの方向に持っていくにはどうしたらいいかを考えてます。私の目標は以下の通りです。

- GCを使わないメモリ安全性
- スレッド間のデータの受け渡しをより効率的にする
- 優れた性能を持つコードをより自然に書けるようにする
- よりシンプルなプログラミングモデル：ポインタはエイリアシングを引き起こすので、プログラムを推論するのが難しく、プログラマだけでなくオプティマイザも影響を受ける

## NimのGCは何が悪いのか？
それ自体は大したことではありませんが (ただし私がここで検討している代替案よりは速いでしょう)、Nimのエコシステムの外にあるほとんどのものとの相互運用性を難しくしています。

- Pythonは独自のGCを持っています。PythonがロードできるNim DLLを作るのはうまくいきますが、GCの保守的なスタックスキャンを保証する特別なコードがDLLに必要なければ、さらに簡単にできるでしょう。
- C++のゲームエンジンはRAIIに基づいており、GCファイナライザでC++のデストラクタを呼び出すNim refオブジェクトでC++オブジェクトを包むとオーバーヘッドが増えます。これはほとんどすべての大規模なCまたはC++プロジェクトに当てはまります。
- 保守的なスタックスキャンはEmscriptenのようなあまり一般的でないターゲット向けコンパイルでは失敗することがあります。(回避策はありますが)。

私はメモリリークや破損の調査よりも、GC関連のバグの修正やGCの最適化に、はるかに多くの時間を費やしてきました。メモリ安全性は交渉の余地がありませんが、私達はますます複雑になるランタイムを使わずに安全性を確保するよう努力していかなければなりません。

## コンテナ

> ※コンピュータプログラミングにおいて、コンテナとはオブジェクトの集まりを表現するデータ構造、抽象データ型またはクラスの総称である。
> よく知られたものには、配列、テーブル、連想配列、集合などがある
> [コンテナ (データ型)](https://ja.wikipedia.org/wiki/%E3%82%B3%E3%83%B3%E3%83%86%E3%83%8A_(%E3%83%87%E3%83%BC%E3%82%BF%E5%9E%8B))

Nim のコンテナは値型であるべきです。明示的なムーブセマンティクスと特別なオプティマイザにより、ほとんどのコピーを排除することができます。

ほとんどすべてのコンテナは、保持している要素の数を保持するため、`nil`の代わりに`len == 0`という、`nil`よりクラッシュしにくい、より良い状態を持つことができます。コンテナがムーブされると、その長さは0になります。

## 配列
文字列とseqは`O(1)`の計算量で実行できる配列をサポートし、他のコンテナもその内部への「ビュー」を生成することができるかもしれません。配列は、私たちが求める明確な所有権のセマンティクスを壊すので、おそらくopenArrayのような引数に制限されるでしょう。

## Opt
木構造を構築するのに必ずしもポインタを使う必要はありません。`seq`でも同じことができます。

```nim
type
  Node = object  ## 'ref'を使わないことに注意
    children: seq[Node]
    payload: string
```

しかしながら、大抵の場合は1個か0個からのエントリしか入らないため、 `seq`を用いるのは過剰です。`opt`は他の言語でも用いられるOption型と同じように、中身が入っているか空かに用いることができるコンテナです。

```nim
type
  Node = object  ## 'ref'を使わないことに注意
    left, right: opt[Node]
    payload: string
```

裏側では、`opt[Note]`はポインタを使用しています。そうしないと、上記のような構成は無限のメモリを消費してしまうからです（あるノードがノードを含み、そのノードがまたノードを含む…）。
しかしこのポインタは公開されないので、値のセマンティクスを破棄することはありません。`opt[T]`はコピーと移動の区別に従った非常にユニークなポインタであると言えるでしょう。

## デストラクタ、代入、ムーブ
既存のNimはshallowCopyによるムーブをサポートしていますが、これはあまり美しくないので、これからはムーブは`<-`と書くことにします。なお、`<-`は新しい演算子ではないので、ムーブが発生する例で強調するために使っただけです。

値のセマンティクスは、オブジェクトの寿命を簡単に決定することができます。
オブジェクトがスコープ外に出たとき、その付属リソースは解放され、デストラクタが呼ばれます。代わりにムーブされた場合（エスケープされた場合）、オブジェクトやコンテナの何らかの内部状態が反映され、破棄を防ぐことができます。最適化パスではデストラクタの呼び出しを削除することができ、同様にコピーパスでは代入を削除することができます。

変数の破棄が発生する可能性のある場所は、実際には2つあります。スコープを抜けるときと代入されるときです。`x = y`は「xを破棄し、yをxにコピーする」ことを意味します。これはしばしば非効率的です。

```nim
proc put(t: var Table; key, val: string) =
  # ハッシュテーブルの実装例:
  let h = hash(key)
  # 破壊的な代入をしている:
  t.a[h].key = key
  t.a[h].val = val

proc main =
  let key <- stdin.readLine()
  let val <- stdin.readLine()
  var t = createTable()
  t.put(key, val)
```

mainのスコープ終了時に、元の文字列keyとvalが解放されます。
この単純なコードでは、2つのコピーと4つの破棄が行われています。[swap](https://nim-lang.org/docs/system.html#swap%2CT%2CT)を使えばもっとうまくいくでしょう。

```nim
proc put(t: var Table; key, val: var string) =
  # ハッシュテーブルの実装例:
  let h = hash(key)
  swap(t.a[h].key, key)
  swap(t.a[h].val, val)

proc main =
  var key <- stdin.readLine()
  var val <- stdin.readLine()
  var t = createTable()
  t.put key, val
```

このコードでは、必要最小限の2回の破棄しか行われなくなりました。しかしながら、`key`と`val`は強制的に`var`にされ、テーブル`t`に移動した後、それらにアクセスすることができ、古いテーブルエントリを含むという、非常に醜いものになっています。これは便利な場合もありますが、`let`を維持したい場合が多く、移動後の値へのアクセスはコンパイル時エラーになります。

これを可能にするのが`sink`引数です。`sink`引数は`var`引数に似ていますが、`let`変数を渡すことができ、その後、簡単な制御フロー分析により、その場所へのアクセスを禁止することができます。`sink`を使った例は次のようになります。

```nim
proc put(t: var Table; key, val: sink string) =
  # ハッシュテーブルの実装例:
  let h = hash(key)
  swap(t.a[h].key, key)
  swap(t.a[h].val, val)

proc main =
  let key <- stdin.readLine()
  let val <- stdin.readLine()
  var t = createTable()
  t.put(key, val)
```
他の方法としては、単純に`let`を`var`引数に渡すことを許可して、それがムーブしたことを意味するようにすることもできます。
一方で`let key = stdin.readLine()`は常に`let key <- stdin.readLine()`に変換されることになります。

## コピーをムーブにする最適化
次のような例を考えてみて下さい

```nim
let key = stdin.readLine()
var a: array[10, string]
a[0] = key
echo key
```
key は `a[0] = key` という代入の後にアクセスされるので、配列スロットにコピーされなければなりません。しかし、`echo key` という記述がなければ、値をムーブすることができます。それをコンパイラがやってくれるわけです。ムーブとコピーの区別をなくすことは、コードが「摩擦」なく発展することを意味します。

## デストラクタ
メモリリークを防ぐために、すべての変数の生成と破棄は対になっている必要があります。またプログラムの破壊を防ぐために、破棄は一度だけでなければなりません。このモデルからメモリ安全性を得る秘訣は、デストラクタの呼び出しが常にコンパイラによって挿入されることにあります。

しかし生成とは何でしょうか？Nimには伝統的なコンストラクタはありません。すべての`proc`の結果がコンストラクタとしてカウントされるからです。戻り値はハイパフォーマンスなコードには不向きな傾向がありますが、これは大きな損失ではありません。これについては後で詳しく説明します。

## デストラクタの自動生成
木構造に対するネイティブのデストラクタは再帰的です。これはスタックオーバーフローを引き起こし、リアルタイム環境での納期遅れにつながる可能性があることを意味します。したがってそれらのためのデフォルトのコード生成は、遅延解放を実装するために、メモリアロケータと対話する明示的なスタックを使用します。もしくは、戦略的な場所で使用されるべき lazyDestroy proc を導入することもできます。実装は次のようになります。

```nim
type Destructor = proc (data: pointer) {.nimcall.}

var toDestroy {.threadvar.}: seq[(Destructor, pointer)]

proc lazyDestroy(arg: pointer; destructor: Destructor) =
  if toDestroy.len >= 100:
    # デストラクタ呼び出しが多すぎるが、即座に実行される:
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
これは、まさに「オブジェクトプール」の発展系と言えるでしょう。


## ムーブのルール
これらの知見を得たことで、ようやくコピーやムーブ、破棄が起こるときの正確なルールを書き出すことができるようになりました。

|ルール|パターン|意味|
|---|---|---|
|1|var x; stmts|var x; try stmts finally: destroy(x)|
|2|x = f()|move(x, f())|
|3|x = lastReadOf z|move(x, z)|
|4|x = y|copy(x, y)|
|5|f(g())|f((move(tmp, g()); tmp)); destroy(tmp)|

`var x = y` は、`var x; x = y` として扱われ、これは任意の場所に置くことができ、`f`と`g`は任意の数の引数を取ることができる関数で、`z`はローカル変数です。

現在の実装では`lastReadOf z`は「zは一度だけ読み書きを行い、それは同じスコープ内で行われる」ことで見積もっています。Nimコンパイラの後のバージョンでは、このケースをより正確に検出する予定です。

ここで得られるの重要なインサイトは、代入は「正しいこと」を行ういくつかの異なるセマンティクスに分解されるということです。したがって、コンテナは組み込みの代入を活用するように書かれるべきです。

これが何を意味するか、例えばC++を見てみましょう。
C++では、ムーブとコピーは区別されており、この区別はAPIにも現れています。`std::vector`ではどうでしょうか。

```cpp
void push_back(const value_type& x); // 要素をコピーする
void push_back(value_type&& x); // 要素をムーブする
```

Nimでは、テンプレート機能（C++のテンプレートとは関係ありません）のおかげで、もっと良い方法を使えます。

```nim
proc reserveSlot(x: var seq[T]): ptr T =
  if x.len >= x.cap: resize(x)
  result = addr(x.data[x.len])
  inc x.len

template add*[T](x: var seq[T]; y: T) =
  reserveSlot(x)[] = y
```

`add`がテンプレートであるおかげで、最終的な代入はコンパイラから隠蔽されないので、最も効果的な記述で書くことが許されます。この実装では安全でない`ptr`と`addr`を使っていますが、現在では言語のコアとなるコンテナにはそれが許されるようになりました。
このようなコンテナの書き方は、より複雑なケースでも有効です。

```nim
template put(t: var Table; key, val: string) =
  # 'key'が一度しか使われないことを保証する:
  let k = key

  let h = hash(k)
  t.a[h].key = k    # ムーブ(ルール3)
  t.a[h].val = val  # ムーブ(ルール3)

proc main =
  var key = stdin.readLine() # ムーブ(ルール2)
  var val = stdin.readLine() # ムーブ(ルール2)
  var t = createTable()
  t.put key, val
```

ルール3では、その後kが二度と使われないので、`t.a[h].key = k`がムーブに変換されることを保証していることに注目してください。(一時的なkを完全に取り除く最適化についてはまた別の機会に)

これらの新しいインサイトから、私は `sink`パラメータはもはや全く必要ないのではないかと思います。言語をよりシンプルに保つことができます。

## ゲッター
テンプレートは、ゲッターによってもたらされるコピーを回避するのにも役立ちます。

```nim
template get(x: Container): T = x.field

echo get() # コピーでもムーブでもない
```

もし、`template get`を`proc get`に置き換えると、ルール5が適用され、以下のようになります。

```nim
proc get(x: Container): T =
  copy result, x.field

echo((var tmp; move(tmp, get()); tmp))
destroy(tmp)
```

## 文字列
この新しいスキームでNimの標準文字列がどのように実装されるのか、その概要を説明します。コードは合理的でわかりやすいのですが、常に二つのことを念頭に置いておく必要があります。

- 割り当てとコピーでは、古い変数を破棄する必要があります。
- 自己割り当てが機能する必要があります。

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
  # もう生きていないオブジェクトのために最適化されているべき:
  if a.data != nil and a.data != b.data: dealloc(a.data)
  a.len = b.len
  a.cap = b.cap
  a.data = b.data
  # デッドオブジェクトのために最適化されるべき:
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

残念ながら[シグネチャ](https://zenn.dev/t_kitamura/articles/90bc98a3787044)は一致しません。`=move`は2つの`var`引数を取りますが、変換規則によると`move(a, f())`または`move(a, lastRead b)`が生成され、これらはアドレス指定可能な位置ではありません。 そこで、代わりに`=sink`と呼ばれる別の型拘束演算子が必要になります。

```nim
proc `=sink`*(a: var string, b: string) =
  if a.data != nil and a.data != b.data: dealloc(a.data)
  a.len = b.len
  a.cap = b.cap
  a.data = b.data
```
コンパイラは`sink`を呼び出すだけで、`move`はプログラマが明示的に最適化します。通常swap操作と書くこともできます。

## 戻り値は有害
Nimの標準ライブラリには、`toString`のための`$`演算子として以下のようなコーディングパターンがあります。

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
(Node型の宣言は読者への課題として残しておきます。)このヘルパー関数で回避する理由は、`result: var string` という単一の文字列バッファを使用して、そこに追加し続けることができるようにするためです。素朴な実装では、より多くの割り当てとデータの結合が発生します。結果を直接最終的な場所に構築する（この場合は追加する）ことで、多くのメリットがあります。

さて、この文字列をHTMLページのような大きな文脈に埋め込むとしたら、実はhelperの方がはるかに高速に動作する便利なインターフェースなのです。これは、「関数はインプレースで操作するべきか、それとも新しい値を返すべきか」という古くからの疑問に答えるものです。

過剰なインプレース操作は、完全にステートメントベースのコーディングスタイルにつながり、データフローはより関数型プログラミング的な式ベースのスタイルよりもはるかに見づらくなります。Nimに必要なのは、式ベースのスタイルから文ベースのスタイルへの変換です。この変換は実に簡単で、次のような関数で可能です。

```nim
proc p(args; result: var T): void
```
最後の引数がない場合の`p(args)` の呼び出しは、`(var tmp: T; p(args, tmp); tmp)`と書き直されます。
理想的には、コンパイラはネストした呼び出しに必要最小限の一時変数を導入すべきですが、そのような最適化は難しいので、より効率的に直接書くことを常に選択することができます。

## 具体化
2級型や、varやimagined sinkのようなパラメータ受け渡しモードは、オブジェクトに入れられないという問題があります。スレッドやタスクのシステムでは、引数リストをタスクオブジェクトに「再定義」して、それをキューやスレッドに送信する必要があるからです。実際、現在のNimでは`await`も`spawn`も`var`引数を持つ関数の呼び出しをサポートしていませんし、クロージャでパラメータを捕捉することさえうまくいきません。[^1]
現在の回避策は、これらのために`ptr`を使うことです。多分、誰かがもっと良い解決策を思いつくでしょう。

[^1]: これは現在では全てサポートされています。
