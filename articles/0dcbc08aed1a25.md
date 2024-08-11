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

# GCなしのNim
ParaSail、"モダン" C++、Rustの共通点は何でしょうか？これらは「ポインタフリーのプログラミング」に焦点を当てています（まあ、Rustは少し違いますが、似たようなメカニズムを使用しています）。このブログ記事では、Nimをこの方向に進める方法を探ります。私の目標は次の通りです：

- GCなしでメモリの安全性を確保すること。
- スレッド間でのデータのやり取りをより効率的にすること。
- 優れたパフォーマンスを持つコードを書くのをより自然にすること。
- より簡単なプログラミングモデル：ポインタはエイリアシングを導入し、これによりプログラムの理解が難しくなり、最適化ツールやプログラマーに影響を与えます。

タイトルから分かるように、ポインタを排除することでこのプログラミングの「Valhalla」にたどり着くつもりです。もちろん、低レベルプログラミングにはNimの`ptr`型は残りますが、標準ライブラリでは`ref`をできるだけ避けることを目指します。（`ref`はアトミックRCポインタになるかもしれません。）副次的な効果として、`nil`も問題にならなくなります。`ref object`の代わりに`object`を多用し、これにより`var`と「no var」の区別がより頻繁に使用されることになります。これは私にとっても利点です。

## NimのGCの問題点とは？
それ自体に大きな問題はありません（実際、ここで探っている代替案よりも高速である可能性が高いです）が、Nimのエコシステム外のほとんどのものとの相互運用性を困難にしています：

- Pythonには独自のGCがあり、Nim DLLをPythonが読み込めるように構築することは可能ですが、DLLがGCの保守的なスタックスキャンを確実に動作させる特別なコードを必要としない方が簡単です。
- C++のゲームエンジンはRAIIに基づいており、Nimの`ref`オブジェクトでC++のデストラクタをGCファイナライザで呼び出すことはオーバーヘッドを追加します。これはほぼすべての大規模なCやC++プロジェクトに当てはまります。
- 保守的なスタックスキャンは、Emscriptenのようなより特殊なターゲットに対して失敗することがあります。（ただし、回避策は存在します。）
- 私は今やGC関連のバグを修正したりGCを最適化したりすることに、メモリリークや破損を追い詰めるよりもはるかに多くの時間を費やしています。メモリの安全性は妥協できませんが、ますます複雑化するランタイムを避けるために、別の方法でそれを達成すべきです。

## コンテナ

> ※コンピュータプログラミングにおいて、コンテナとはオブジェクトの集まりを表現するデータ構造、抽象データ型またはクラスの総称である。
> よく知られたものには、配列、テーブル、連想配列、集合などがある
> [コンテナ (データ型)](https://ja.wikipedia.org/wiki/%E3%82%B3%E3%83%B3%E3%83%86%E3%83%8A_(%E3%83%87%E3%83%BC%E3%82%BF%E5%9E%8B))


Nimのコンテナは値タイプであるべきです。明示的なムーブセマンティクスおよび特別な最適化ツールにより、ほとんどのコピーを排除します。

ほとんどのコンテナは保持する要素の数を記録しており、そのため`nil`の代わりに、クラッシュしにくい`len == 0`という状態が得られます。コンテナがムーブされると、その長さは0になります。

### スライシング
文字列や`seq`は`O(1)`のスライシングをサポートし、他のコンテナも内部への「ビュー」を生成するかもしれません。スライスは所有権セマンティクスを破壊するため、`openArray`のようにパラメータに制限される可能性があります。

## Opt
ツリーの構築にはポインタが必要ではなく、`seq`で同様のことができます：

```nim
type
  Node = object  ## ここで`ref`がないことに注目
    children: seq[Node]
    payload: string
```

しかし、しばしば1つか0のエントリしか必要とされないため、`seq`は過剰です。`opt`は、いっぱいか空かの状態を持つコンテナで、他の言語で知られている`Option`型と似ています。

```nim
type
  Node = object  ## ここで`ref`がないことに注目
    left, right: opt[Node]
    payload: string
```

`opt[Node]`は内部でポインタを使用しますが、これは露出されないため、値セマンティクスを壊しません。`opt[T]`はコピーとムーブの区別を守るユニークポインタであると主張できます。

## デストラクタ、代入、ムーブ

現行のNimは`shallowCopy`を介してムーブをサポートしていますが、これは少し醜いので、今後はムーブを`<-`と書くことにします。`<-`は新しい演算子ではなく、例でムーブが発生する箇所を強調するために使用しました。

値セマンティクスにより、オブジェクトのライフタイムを簡単に決定でき、スコープが終了するとそのリソースが解放されます。これはデストラクタが呼び出されることを意味します。もしムーブされた場合（逃げた場合）、オブジェクトやコンテナ内のいくつかの内部状態がこれを反映し、破壊が防止されます。最適化パスはデストラクタの呼び出しを削除することが許されており、同様にコピー伝搬パスは代入を削除することが許されています。

実際、破壊は2つの場所で発生する可能性があります：スコープの終了時と代入時、`x = y`は「`x`を破壊し、`y`を`x`にコピーする」という意味です。これはしばしば非効率的です：

```nim
proc put(t: var Table; key, val: string) =
  # ハッシュテーブル実装の概要：
  let h = hash(key)
  # これらは破壊的な代入です：
  t.a[h].key = key
  t.a[h].val = val

proc main =
  let key <- stdin.readLine()
  let val <- stdin.readLine()
  var t = createTable()
  t.put key, val
```

このコードでは、`readLine`呼び出しを通じて2つの文字列が構築され、それがテーブル`t`にコピーされます。`main`のスコープ終了時には、元の文字列`key`と`val`が解放されます。

このナイーブなコードでは2つのコピーと4つの破壊が行われます。[`swap`](https://nim-lang.org/docs/system.html#swap%2CT%2CT)を使用することで、これを大幅に改善できます：

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

このコードでは、必要最小限の2つの破壊のみが行われます。また、このコードはかなり醜いです。`key`と`val`は`var`に強制され、テーブル`t`にムーブされた後でも、これらをアクセスして古いテーブルエントリを含むことができます。これは時折有用ですが、多くの場合、`let`を保持したいと考え、ムーブされた後に値をアクセスしようとするとコンパイル時エラーが発生することを望みます。

これは`sink`パラメータによって可能です。`sink`パラメータは`var`パラメータのようなもので、`let`変数をそれに渡すことができ、その後、単純な制御フロー解析が場所へのアクセスを禁止します。`sink`を使用した例は次の通りです：

```nim
proc put(t: var Table; key, val: sink string) =
  # ハッシュテーブル実装の概要：
  let h = hash(key)
  swap t.a[h].key, key
  swap t.a[h].val, val

proc main =
  let key <- stdin.readLine()
  let val <- stdin.readLine()
  var t = createTable()
  t.put key, val
```

あるいは、単に`let`を`var`パラメータに渡せるようにして、ムーブされた場合にはそれがムーブを意味するようにしてもよいです。

ちなみに、`let key = stdin.readLine()`は常に`let key <- stdin.readLine()`に変換されます。

## コピーをムーブに最適化する
次の例を考えてみましょう：

```nim
let key = stdin.readLine()
var a: array[10, string]
a[0] = key
echo key
```

この場合、`a[0] = key`の後に`key`がアクセスされるため、それが配列スロットにコピーされなければなりません。しかし、`echo key`文がない場合、値はムーブされることができます。そして、それがコンパイラによって行われます。ムーブとコピーの区別をぼかすことで、コードは「摩擦」なしに進化することができます。

## デストラクタ
すべての構築には、メモリリークを防ぐために破壊が必要です。また、破壊は1回だけ行われる必要があります。メモリの安全性をこのモデルから得る秘訣は、デストラクタの呼び出しが常にコンパイラによって挿入されることにあります。

しかし、構築とは何でしょうか？Nimには従来のコンストラクタはありません。その答えは、すべてのprocの結果が構築と見なされることです。これは大した損失ではありません。リターン値は高性能なコードにはあまり向いていないことが多いからです。このことについては後で詳しく説明します。

## デストラクタのコード生成
ツリーのナイーブなデストラクタは再帰的です。これにより、スタックオーバーフローが発生する可能性があり、リアルタイム環境での締め切りを逃す可能性があります。したがって、デフォルトのコード生成では、メモリアロケータと連携する明示的なスタックを使用して遅延解放を実装します。あるいは、戦略的な場所で使用される`lazyDestroy` procを導入することもできます。その実装は次のようになるかもしれません：

```nim
type Destructor = proc (data: pointer) {.nimcall.}

var toDestroy {.threadvar.}: seq[(Destructor, pointer)]

proc lazyDestroy(arg: pointer; destructor: Destructor) =
  if toDestroy.len >= 100:
    # 保留中のデストラクタ呼び出しが多すぎるため、即座に実行する：
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

これは「オブジェクトプーリング」のバリエーションに過ぎません。

## ムーブルール
これらの洞察を得た今、コピー、ムーブ、破壊が発生する正確なルールをようやく書き下すことができます：

|ルール|パターン|意味|
|---|---|---|
|1|var x; stmts|var x; try stmts finally: destroy(x)|
|2|x = f()|move(x, f())|
|3|x = lastReadOf z|move(x, z)|
|4|x = y|copy(x, y)|
|5|f(g())|f((move(tmp, g()); tmp)); destroy(tmp)|

`var x = y`はここで`var x; x = y`として扱われます。`x`、`y`は任意の場所であり、`f`と`g`は任意の数の引数を取るルーチン、`z`はローカル変数です。

現在の実装では、`lastReadOf z`は「`z`が1回だけ読み書きされ、それが同じ基本ブロック内で行われる」として近似されます。後のバージョンのNimコンパイラはこのケースをより正確に検出するでしょう。

ここでの重要な洞察は、代入が「適切なこと」を行ういくつかの異なるセマンティクスに解決されることです。したがって、コンテナは組み込みの代入を活用するように書かれるべきです！

これが意味することを見るために、C++を見てみましょう：C++ではムーブとコピーの区別があり、この区別がAPIに現れます。たとえば、`std::vector`には以下のようなものがあります：

```cpp
void push_back(const value_type& x); // 要素をコピーします
void push_back(value_type&& x); // 要素をムーブします
```

Nimでは、テンプレート機能（これはC++のテンプレートとは関係ありません）のおかげで、これをより良くすることができます：

```nim
proc reserveSlot(x: var seq[T]): ptr T =
  if x.len >= x.cap: resize(x)
  result = addr(x.data[x.len])
  inc x.len

template add*[T](x: var seq[T]; y: T) =
  reserveSlot(x)[] = y
```

`add`がテンプレートであるため、最終的な代入はコンパイラから隠されず、最も効果的な形式を使用することができます。この実装は安全でない`ptr`と`addr`の構造を使用していますが、言語のコアコンテナがこれを行うことは一般的に許容されています。

この方法で書かれたコンテナは、より複雑なケースでも機能します：

```nim
template put(t: var Table; key, val: string) =
  # 'key'が一度だけ評価されることを保証します：
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

ルール3のおかげで、`t.a[h].key = k`がムーブに変換されることが保証されます。`k`はその後再利用されないためです。（一時変数`k`を完全に最適化する話は別の機会にします。）

これらの新しい洞察を得た結果、`sink`パラメータはまったく必要ないと考えられます。言語がシンプルになります。

## ゲッター
テンプレートはゲッターによって導入されるコピーを避けるのにも役立ちます：

```nim
template get(x: Container): T = x.field

echo get() # コピーなし、ムーブなし
```

ここでテンプレートの`get`を`proc get`に置き換えると、ルール5が適用され、次のように生成されます：

```nim
proc get(x: Container): T =
  copy result, x.field

echo((var tmp; move(tmp, get()); tmp))
destroy(tmp)
```

## 文字列
Nimの標準文字列をこの新しいスキームでどのように実装できるかの概要を以下に示します。このコードは合理的に理解しやすいですが、常に2つのことを念頭に置く必要があります：

1. 代入とコピーは古い宛先を破壊する必要があります。
2. 自己代入が動作する必要があります。

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
  # オブジェクトaが既に見られていない場合は、そのメモリを解放する
  if a.data != nil and a.data != b.data: dealloc(a.data)
  a.len = b.len
  a.cap = b.cap
  a.data = b.data
  # オブジェクトbは移動後に無効な状態にする
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

残念ながら、シグネチャが一致しません。`=move`は2つの`var`パラメータを取りますが、変換ルールに従って`move(a, f())`や`move(a, lastRead b)`が生成され、これらはアドレス可能な場所ではありません！したがって、代わりに使用される`=sink`と呼ばれる異なる型バウンドオペレーターが必要です。

```nim
proc `=sink`*(a: var string, b: string) =
  if a.data != nil and a.data != b.data: dealloc(a.data)
  a.len = b.len
  a.cap = b.cap
  a.data = b.data
```

コンパイラは`sink`のみを呼び出します。`move`はプログラマーによる明示的な最適化です。通常、これは`swap`操作として書くことができます。

## リターン値は有害である
Nimの標準ライブラリには、`toString`（$オペレーター）用の次のコーディングパターンが含まれています：

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

（`Node`型の宣言は読者への課題として残されています。）この`helper` procを使用するための回避策の理由は、`result: var string`を使用できるようにすることです。これにより、連続して追加する単一の文字列バッファを保持できます。ナイーブな実装では、はるかに多くのメモリアロケーションと連結が発生します。結果を構築（この場合は追加）する際、最終的にその結果がどこに行き着くかを直接構築することで、得られる利益は大きいです。

さて、この文字列をHTMLページのような大きな文脈に埋め込む必要があると想像してください。`helper`は実際に高速性のために非常に役立つインターフェースです。これは、「プロシージャはインプレースで動作すべきか、新しい値を返すべきか」という古い質問に対する答えです。

過剰なインプレース操作は、完全にステートメントベースのコードスタイルをもたらし、データフローがFPスタイルの式ベースのスタイルよりもはるかに見づらくなります。Nimが必要とするのは、式ベースのスタイルからステートメントスタイルへの変換です。この変換は非常に簡単です。以下のようなprocがあるとしましょう：

```nim
proc p(args; result: var T): void
```

結果のパラメータ`p(args)`が欠落している呼び出しは、`(var tmp: T; p(args, tmp); tmp)`に書き換えられます。理想的には、コンパイラはネストされた呼び出しで必要な最小限の一時変数を導入するでしょうが、そのような最適化は遠い未来の話であり、誰でもより効率的なバージョンを直接書くことができます。

## 具象化
`var`や想定される`sink`のようなパラメータ渡しモードやセカンドクラス型には、オブジェクトに入れることができないという問題があります。これは、一見したところでは問題にならないように思えますが、スレッディングやタスクシステムのどのような種類でも、キューやスレッドに送られるタスクオブジェクトに引数リストを「具象化」する必要があるため、深刻な問題です。実際、現在のNimでは、`await`も`spawn`も`var`パラメータを持つprocの呼び出しをサポートしておらず[^1]、そのようなパラメータをクロージャでキャプチャすることすらできません！現在の回避策は、これらに`ptr`を使用することです。誰かがより良い解決策を考え出すかもしれません。

[^1]: これは現在では全てサポートされています。
