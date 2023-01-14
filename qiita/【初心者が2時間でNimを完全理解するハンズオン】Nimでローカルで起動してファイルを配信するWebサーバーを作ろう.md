2022年11月11日、東京都中野区にある[Jamstack推しで有名なchot.inc](https://chot-inc.com/)でNimのハンズオンを行いました。

https://twitter.com/shinoyu/status/1591042860790743041

今回のこの時の教材に加筆・修正して、一般公開します！

---
---

## はじめに
Pythonでは `python3 -m http.server 8000` とすると、現在のディレクトリにあるファイルを配信するサーバーをローカルで起動することができます。
このコマンドをNimで実装することで、Nimの基本的な機能について学びましょう。

## 今回学べること
- NimでWebサーバーを建てられること
- NimでOSのファイルシステムを扱えること
- Nimの標準ライブラリのドキュメントの読み方
- Nimの3rdパーティのライブラリの使い方
- ソースコードからドキュメントを自動生成する方法
- ドキュメントの書き方

## 環境構築
Nimでは`choosenim`というツールを使うと、PCに複数のバージョンをインストールして、パスが通るバージョンをコマンドから切り替えたり、最新バージョンをコマンドからインストールできるのでこれを使うのが便利です。

https://qiita.com/honeytrap15/items/2c7ebe20cb69df8c53c9

### Windowsの人
- [ChoosenimのGithub](https://github.com/dom96/choosenim/releases)から最新のバージョンのものを選び、Windows用の `choosenim-0.8.4_windows_amd64.exe` をダウンロードします。
- `choosenim-0.8.4_windows_amd64.exe` を `choosenim.exe` にリネームします。
- コマンドプロンプトやPowerShellから`choosenim.exe`をコマンドとして使えるので、これを使って次のコマンドを実行して最新版のインストールをします。

```sh
choosenim.exe stable
```

### Linux / Intel Macの人
次のコマンドを実行します。
```sh
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
 or
wget -qO - https://nim-lang.org/choosenim/init.sh | sh
```

### M1 Macの人
M1Macではchoosenimを使えないので、Homebrewからインストールします。
```sh
brew install nim
```

## プロジェクト作成
`localserver`というディレクトリを作って、その中で作業することにします。
ディレクトリを作ったら**その配下で**次のコマンドを実行してください。

```sh
nimble init
```

対話型で聞かれるので、質問に答えていきます。
`Package type?` では `binary`を選択してください。
後はほとんどEnterでOK。

するとこのようなディレクトリ構造が自動生成されたと思います。
```
.
├── localserver.nimble
└── src
    └── localserver.nim
```

## Hello World
`src/localserver.nim`の中身はこのようになっていると思います。

```nim:src/localserver.nim
# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.

when isMainModule:
  echo("Hello, World!")
```

このファイルを実行してみましょう

```sh
nim c -r src/localserver.nim
```

するとターミナルに `Hello, World!` が表示されたと思います。このようなコマンドでNimはファイルを実行することができます。

## httpserverを作る
標準ライブラリの`asynchttpserver`に書いてる内容を元にサーバーを起動するプログラムを書きます。
https://nim-lang.org/docs/asynchttpserver.html

`src/lib/server.nim`というファイルを作りましょう。

```diff_shell
.
├── localserver.nimble
└── src
+   ├── lib
+   │   └── server.nim
    ├── localserver
    └── localserver.nim
```

```src/lib/server.nim
import std/asynchttpserver
import std/asyncdispatch

proc main() {.async.} =
  var server = newAsyncHttpServer()
  proc cb(req: Request) {.async.} =
    echo (req.reqMethod, req.url, req.headers)
    let headers = {"Content-type": "text/plain; charset=utf-8"}
    await req.respond(Http200, "Hello World", headers.newHttpHeaders())

  server.listen(Port(8000)) # or Port(8080) to hardcode the standard HTTP port.
  let port = server.getPort
  echo "test this with: curl localhost:" & $port.uint16 & "/"
  while true:
    if server.shouldAcceptRequest():
      await server.acceptRequest(cb)
    else:
      await sleepAsync(500)

waitFor main()
```

そしてこのファイルを単体で実行すると、HTTPサーバーが起動します。
```sh
nim c -r src/lib/server.nim
```
ブラウザから http://localhost:8000 へアクセスすると、画面に「Hello World」が表示されます。


## CLIアプリを作る
ではCLIコマンドの引数から起動するサーバーのポート番号を渡せるようにします。

NimではCLIアプリを作るのに非常に便利な[cligen](https://github.com/c-blake/cligen)という3rdパーティライブラリがあるのでこれを使います。

https://qiita.com/jiro4989/items/d5476b3dce3c4b3d6523

nimbleコマンドでcligenをインストールします。
```sh
nimble install cligen -y
```

nimbleファイルに依存関係を追記します。
```diff_nim:localserver.nimble
# Package

version       = "0.1.0"
author        = "Anonymous"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src"
bin           = @["localserver"]


# Dependencies

requires "nim >= 1.6.10"
+ requires "cligen"
```

`localserver.nim`の中身を以下のように書き換えます。

```localserver.nim
proc localserver() =
  discard

when isMainModule:
  import cligen
  dispatch(localserver)
```

`localserver.nim`に`-h`を付けて起動してみましょう。

```sh
nim c -r src/localserver -h
```

すると以下のようなメッセージングが画面に表示されると思います。これはCLIコマンドとしての説明です。

```sh
Usage:
  localserver [optional-params] 
Options:
  -h, --help         print this cligen-erated help
  --help-syntax      advanced: prepend,plurals,..
```

では`localserver`関数の引数にポート番号をデフォルト値と共に書いて、更に与えられたポート番号をターミナルに表示させましょう。

```src/localserver.nim
proc localserver(port=8000) =
  echo port

when isMainModule:
  import cligen
  dispatch(localserver)
```

この状態で`-h`を付けて起動します。
```sh
nim c -r src/localserver -h
```

```sh
Usage:
  localserver [optional-params] 
Options:
  -h, --help                print this cligen-erated help
  --help-syntax             advanced: prepend,plurals,..
  -p=, --port=   int  8000  set port
```

表示されるメッセージが変わりました。`port`についての説明が追加されています。

### ヘルプの内容を編集する
以下のようにするとヘルプの内容を編集することができます。

```src/localserver.nim
import std/tables

proc localserver(port=8080) =
  ## ローカルでサーバーを起動するコマンドです
  echo port

const HELP = {"port": "ここに指定したポート番号でサーバーが起動します"}.toTable()

when isMainModule:
  import cligen
  dispatch(localserver, help=HELP)
```

起動するとメッセージの内容が変わっていることがわかります。

```sh
nim c -r src/localserver -h
```

```sh
Usage:
  localserver [optional-params] 
ローカルでサーバーを起動するコマンドです
Options:
  -h, --help                print this cligen-erated help
  --help-syntax             advanced: prepend,plurals,..
  -p=, --port=   int  8000  ここに指定したポート番号でサーバーが起動します
```


### コマンドライン引数からポート番号を渡す
ではコマンドライン引数からポート番号を渡してみましょう。
何も渡さず起動するとデフォルト値の8000が、数値を渡すとその数値がターミナルに表示され、数字以外を渡すとエラーが発生します。

```sh
nim c -r src/localserver

>> 8000
```

```sh
nim c -r src/localserver -p 7000

>> 7000
```

```sh
nim c -r src/localserver -p aaa

>> Bad value: "aaa" for option "p"; expecting int
Usage:
  localserver [optional-params] 
Options:
  -h, --help                print this cligen-erated help
  --help-syntax             advanced: prepend,plurals,..
  -p=, --port=   int  8000  set port
```

### 指定したポート番号でサーバーを起動する
コマンドライン引数からポート番号を渡せることはわかったので、HTTPサーバーに引数を渡せるようにします。

```diff_nim:src/localserver.nim
  import std/tables
+ import std/asyncdispatch
+ import ./lib/server

  proc localserver(port=8000) =
    ## ローカルでサーバーを起動するコマンドです
+   waitFor main(port)

  const HELP = {"port": "ここに指定したポート番号でサーバーが起動します"}.toTable()

  when isMainModule:
    import cligen
    dispatch(localserver, help=HELP)
```

```diff_nim:src/lib/server.nim
  import std/asynchttpserver
  import std/asyncdispatch

+ proc main*(port:int) {.async.} =
    var server = newAsyncHttpServer()
    proc cb(req: Request) {.async.} =
      echo (req.reqMethod, req.url, req.headers)
      let headers = {"Content-type": "text/plain; charset=utf-8"}
      await req.respond(Http200, "Hello World", headers.newHttpHeaders())

+   server.listen(Port(port)) # or Port(8080) to hardcode the standard HTTP port.
    let port = server.getPort
    echo "test this with: curl localhost:" & $port.uint16 & "/"
    while true:
      if server.shouldAcceptRequest():
        await server.acceptRequest(cb)
      else:
        await sleepAsync(500)

- waitFor main()
```

実行するとそれぞれのポート番号でサーバーが起動することがわかります。

```sh
nim c -r src/localserver.nim -p 7000
nim c -r src/localserver.nim -p 8000
nim c -r src/localserver.nim -p 9000
```

## ファイルの中身を読む

「ファイルの中身を読む」という処理はIOの処理です。
ここでは非同期でファイルの読み書きをするasyncfileライブラリを使います。

https://nim-lang.org/docs/asyncfile.html

### 読み込まれるファイルのサンプルを作る

exampleディレクトリを作り、その中に以下のようなHTMLとCSSを作ります。

```diff_shell
  .
+ ├── example
+ │   ├── index.html
+ │   └── style.css
  ├── localserver.nimble
  └── src
      ├── lib
      │   ├── server
      │   └── server.nim
      ├── localserver
      └── localserver.nim
```

```example/index.html
<!DOCTYPE html>
<html lang="en">

<head>
  <meta charset="UTF-8">
  <meta http-equiv="X-UA-Compatible" content="IE=edge">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link href="./style.css" rel="stylesheet">
  <title>Document</title>
</head>

<body>
  <main>
    <div class="box1"></div>
    <div class="box2"></div>
    <div class="box3"></div>
  </main>
</body>

</html>
```

```example/style.css
.box1 {
  height: 200px;
  width: 200px;
  margin: auto;
  background-color: red;
}

.box1:hover {
  background-color: blue;
}

.box2 {
  height: 200px;
  width: 200px;
  margin: auto;
  background-color: yellow;
}

.box2:hover {
  background-color: red;
}


.box3 {
  height: 200px;
  width: 200px;
  margin: auto;
  background-color: blue;
}

.box3:hover {
  background-color: green;
}
```

### 読み込んだファイルを画面に返す
では`server.nim`の中にファイルを読み込み、画面に返して表示する処理を書いていきます。

```diff_nim:src/lib/server.nim
  import std/asynchttpserver
  import std/asyncdispatch
+ import std/os
+ import std/asyncfile

  proc main*(port:int) {.async.} =
    var server = newAsyncHttpServer()
    proc cb(req: Request) {.async.} =
+     let filepath = getCurrentDir() / "example/index.html"
+     let file = openAsync(filepath, fmRead)
+     defer: file.close()
+     let data = file.readAll().await

      echo (req.reqMethod, req.url, req.headers)
      let headers = {"Content-type": "text/plain; charset=utf-8"}
+     await req.respond(Http200, data, headers.newHttpHeaders())

    server.listen(Port(port)) # or Port(8080) to hardcode the standard HTTP port.
    let port = server.getPort
    echo "test this with: curl localhost:" & $port.uint16 & "/"
    while true:
      if server.shouldAcceptRequest():
        await server.acceptRequest(cb)
      else:
        await sleepAsync(500)
```

起動して確認してみましょう。
```sh
nim c -r src/localserver
```
画面にHTMLファイルの中身が表示されました。

### ファイルパスをURLパラメータから受け取る
ソースコードの中に文字列として固定値を入れていた `example/index.html` をURLパラメータから受け取れるようにします。
また存在しないファイルパスが渡された時には404を返すようにします。
標準ライブラリ`asynchttpserver`の`Request`構造体や`URI`構造体から値を取りだすことができます。

https://nim-lang.org/docs/asynchttpserver.html#Request

![スクリーンショット 2022-12-04 12-49-09.jpg](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/295826/b677a899-bff0-e1af-8059-5f57d4ad8dba.jpeg)


https://nim-lang.org/docs/uri.html#Uri

![スクリーンショット 2022-12-04 12-49-28.jpg](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/295826/4b0b31ef-3fd7-4bc4-ebe8-f6eef3c09373.jpeg)


```diff_nim:src/lib/server.nim
  import std/asynchttpserver
  import std/asyncdispatch
  import std/os
  import std/asyncfile

  proc main*(port:int) {.async.} =
    var server = newAsyncHttpServer()
    proc cb(req: Request) {.async.} =
+     let filepath = getCurrentDir() / req.url.path
+     if fileExists(filepath):
        let file = openAsync(filepath, fmRead)
        defer: file.close()
        let data = file.readAll().await

        echo (req.reqMethod, req.url, req.headers)
        let headers = {"Content-type": "text/plain; charset=utf-8"}
        await req.respond(Http200, data, headers.newHttpHeaders())
+     else:
+       let headers = {"Content-type": "text/plain; charset=utf-8"}
+       await req.respond(Http404, "", headers.newHttpHeaders())

    server.listen(Port(port)) # or Port(8080) to hardcode the standard HTTP port.
    let port = server.getPort
    echo "test this with: curl localhost:" & $port.uint16 & "/"
    while true:
      if server.shouldAcceptRequest():
        await server.acceptRequest(cb)
      else:
        await sleepAsync(500)
```

起動して、`http://localhost:8000/example/index.html`にアクセスしてHTMLファイルの中身が表示されることを確認します。
また存在しないファイルパスにアクセスした時に`404`になることを確認します。

### MIMEタイプを判別してHTMLページとして表示する
ここまでは読み込んだファイルの中身がそのまま文字列として表示されていました。HTMLページとしてブラウザ上で描画できるようにします。
ブラウザはHTTPヘッダーの`Content-Type`にあるMIMEタイプからファイルの種類を特定して描画します。
URLパラメータの拡張子からMIMEタイプを特定できるようにしましょう。

まずURLから拡張子を取り出します。

```nim
let path = req.url.path
echo path
# > /examples/index.html

#ドットで分割して配列にする
let pathArr = path.split(".")
echo pathArr
# > @["/example/index", "html"]

# 配列の一番最後を取りだす
let ext = pathArr[^1]
echo ext
# > "html"
```

標準ライブラリの `mimetypes` ライブラリを使うと拡張子からMIMEタイプを得られます。
https://nim-lang.org/docs/mimetypes.html

```nim
import std/mimetypes

let ext = req.url.path.split(".")[^1]
let contentType = newMimetypes().getMimetype(ext)
echo contentType
```

最後にレスポンスヘッダーに `Content-Type`をセットします。
```nim
let headers = newHttpHeaders()
headers["Content-Type"] = contentType
```

全体像としてこのようになります。
```diff_nim:src/lib/server.nim
  import std/asynchttpserver
  import std/asyncdispatch
  import std/os
  import std/asyncfile
+ import std/mimetypes
+ import std/strutils

  proc main*(port:int) {.async.} =
    var server = newAsyncHttpServer()
    proc cb(req: Request) {.async.} =
      let filepath = getCurrentDir() / req.url.path
      if fileExists(filepath):
        let file = openAsync(filepath, fmRead)
        defer: file.close()
        let data = file.readAll().await

        echo (req.reqMethod, req.url, req.headers)
+       let ext = req.url.path.split(".")[^1]
+       let contentType = newMimetypes().getMimetype(ext)
-       let headers = {"Content-type": "text/plain; charset=utf-8"}
+       let headers = newHttpHeaders()
+       headers["Content-Type"] = contentType
+       await req.respond(Http200, data, headers)
      else:
        let headers = {"Content-type": "text/plain; charset=utf-8"}
        await req.respond(Http404, "", headers.newHttpHeaders())

    server.listen(Port(port)) # or Port(8080) to hardcode the standard HTTP port.
    let port = server.getPort
    echo "test this with: curl localhost:" & $port.uint16 & "/"
    while true:
      if server.shouldAcceptRequest():
        await server.acceptRequest(cb)
      else:
        await sleepAsync(500)
```

起動するとHTMLとして描画されました。色の付いた正方形が3つ表示されています。これはCSSファイルについてもMIMEタイプの特定が正しく行われ、描画されていることを示しています。

## ファイル一覧を表示する
ファイル単体での表示はできたので、ディレクトリへアクセスするとファイル一覧を表示できるようにしましょう。
ディレクトリかファイルかどうかはURLでの拡張子の有無で判別します。

### 現在のフォルダのファイル一覧を返す関数を作る
標準ライブラリのこの辺りの関数を使います。

os.walkDir…ファイル一覧をイテレーターで回す
https://nim-lang.org/docs/os.html#walkDir.i%2Cstring

os.PathComponent…ディレクトリにあるオブジェクトのタイプ
https://nim-lang.org/docs/os.html#PathComponent

strutils.contains…ある文字列にある文字列が含まれるかどうか
https://nim-lang.org/docs/strutils.html#contains%2Cstring%2Cstring

seq[T]…配列
https://nim-lang.org/docs/system.html#system-module-seqs

`lib`ディレクトリの下に`file.nim`というファイルを新規作成しましょう。

```diff_shell
  .
  ├── example
  │   ├── index.html
  │   └── style.css
  ├── localserver.nimble
  └── src
      ├── lib
+     │   ├── file.nim
      │   ├── server
      │   └── server.nim
      ├── localserver
      └── localserver.nim
```

```src/lib/file.nim
import std/os
import std/strutils

proc getFiles*(path:string):seq[string] =
  let currentPath = getCurrentDir() / path
  var files = newSeq[string]()
  for row in walkDir(currentPath, relative=true):
    # ディレクトリにあるものがディレクトリもしくは拡張子があるものの絶対パスを配列に追加していく
    # →バイナリは含めない
    if row.kind == pcDir or row.path.contains("."):
      files.add(row.path)
  return files
```

これを`server.nim`から呼び出します。

```diff_nim:src/lib/server.nim
    import std/asynchttpserver
    import std/asyncdispatch
    import std/os
    import std/asyncfile
    import std/mimetypes
    import std/strutils
+   import ./file

    proc main*(port:int) {.async.} =
    var server = newAsyncHttpServer()
    proc cb(req: Request) {.async.} =
      let filepath = getCurrentDir() / req.url.path
      if fileExists(filepath):
        let file = openAsync(filepath, fmRead)
        defer: file.close()
        let data = file.readAll().await

        echo (req.reqMethod, req.url, req.headers)
        let ext = req.url.path.split(".")[^1]
        let contentType = newMimetypes().getMimetype(ext)
        let headers = newHttpHeaders()
        headers["Content-Type"] = contentType
        await req.respond(Http200, data, headers)
      else:
-       let headers = {"Content-type": "text/plain; charset=utf-8"}
-       await req.respond(Http404, "", headers.newHttpHeaders())
+       let files = getFiles(req.url.path)
+       let headers = newHttpHeaders()
+       await req.respond(Http200, $files, headers)

+     await req.respond(Http404, "")

    server.listen(Port(port)) # or Port(8080) to hardcode the standard HTTP port.
    let port = server.getPort
    echo "test this with: curl localhost:" & $port.uint16 & "/"
    while true:
      if server.shouldAcceptRequest():
        await server.acceptRequest(cb)
      else:
        await sleepAsync(500)
```

起動して `http://localhost8080/example` にアクセスしてみましょう。
画面に `@["index.html", "style.css"]` が表示されていると思います。


### テンプレートエンジンを使って綺麗に表示する
Nimには`Source Code Filters` という機能があり、これを使ってHTMLの中に変数を入れたりif文やfor文が使えます。
テンプレートエンジンとして使うことができます。

https://nim-lang.org/docs/filters.html

`lib`ディレクトリの下に`view.nim`というファイルを新規作成しましょう。

```src/lib/view.nim
#? stdtmpl | standard
#proc displayView*(path:string, files:seq[string]): string =
<!DOCTYPE html>
<html lang="en">
  <head>
    <title>Current Directory Files</title>
  </head>
  <body>
    # let urlPath = if path == "/": "" else: path
    <h1>Directory listing for ${path}</h1>
    <hr>
    #if files.len > 0:
      <ul>
        #for file in files:
          <li><a href="${urlPath}/${file}">${file}</a></li>
        #end for
      </ul>
    #end if
    <hr>
  </body>
</html>
```

これを`server.nim`から呼び出します。

```diff_nim:src/lib/server.nim
  import std/asynchttpserver
  import std/asyncdispatch
  import std/os
  import std/asyncfile
  import std/mimetypes
  import std/strutils
  import ./file
+ import ./view

  proc main*(port:int) {.async.} =
    var server = newAsyncHttpServer()
    proc cb(req: Request) {.async.} =
      let filepath = getCurrentDir() / req.url.path
      if fileExists(filepath):
        let file = openAsync(filepath, fmRead)
        defer: file.close()
        let data = file.readAll().await

        echo (req.reqMethod, req.url, req.headers)
        let ext = req.url.path.split(".")[^1]
        let contentType = newMimetypes().getMimetype(ext)
        let headers = newHttpHeaders()
        headers["Content-Type"] = contentType
        await req.respond(Http200, data, headers)
      else:
        let files = getFiles(req.url.path)
+       let body = displayView(req.url.path, files)
        let headers = newHttpHeaders()
        await req.respond(Http200, body, headers)

    server.listen(Port(port)) # or Port(8080) to hardcode the standard HTTP port.
    let port = server.getPort
    echo "test this with: curl localhost:" & $port.uint16 & "/"
    while true:
      if server.shouldAcceptRequest():
        await server.acceptRequest(cb)
      else:
        await sleepAsync(500)
```

起動するとこのように表示されます。
![スクリーンショット 2022-12-04 13-24-05.jpg](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/295826/3563fbe1-d88a-6a7e-c6c1-15ebf3d551da.jpeg)

## 作ったコマンドをPCにインストールする
これで全ての処理が完成しました！PCにインストールして、ファイル単体で動かせるようにしましょう。

```sh
nimble install
localserver -h
localserver -p 8080
```

実行バイナリは `~/.nimble/bin/` にあります。

# おまけ

## Nimのソースコードからドキュメントを自動生成する

https://nim-lang.org/docs/docgen.html

Nimではコマンド1発でソースコードからドキュメントを自動生成することができます。
今回作ったコマンドを使ってブラウザから見てみましょう。


:::note warn
M1 Macを使っている人は、インストール時にドキュメント生成する辺りのプログラムが正しくインストールできていない可能性があります。
エラー文で表示されている欠けているファイルをGithubから直接持ってくるか、Dockerを使ってください。

https://github.com/nim-lang/Nim
:::


```sh
nim doc --project --index:on --outdir:docs src/localserver.nim
cd docs
localserver
```

http://localhost:8000/theindex.html にアクセス

このように表示されます。
![スクリーンショット 2022-12-04 13-40-49.jpg](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/295826/17b435a9-7aa9-3016-1708-b0e84d9d599e.jpeg)

![スクリーンショット 2022-12-04 13-41-54.jpg](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/295826/b280b2af-3183-70aa-8f6a-286146808304.jpeg)

今まで見てきたNimの標準ライブラリの公式ドキュメントもこの機能を使って作られています。

## 関数にコメントを書く
`localserver/file.nim`の`getFile`関数にコメントを書いてみましょう。

- シャープ２つ「##」で始めた行がドキュメントコメントとして解釈されます。
- マークダウン記法で書けます。
- runnableExamplesの中のネストでサンプルのコードを書くことができます。
- runnableExamplesも引数の型の不一致、未定義変数の呼び出しなどでコンパイルエラーになります。

```src/lib/file.nim
import std/os
import std/strutils

proc getFiles*(path:string):seq[string] =
  ## pathのディレクトリのファイル一覧を表示します
  ## 
  ## バイナリは除外します
  runnableExamples:
    let files = getFiles("/path/to/dir")
    echo files
    # > @["subdir", "aaa.nim", "bbb.nim"]

  let currentPath = getCurrentDir() / path
  var files = newSeq[string]()
  for row in walkDir(currentPath, relative=true):
    # ディレクトリにあるものがディレクトリもしくは拡張子があるものの絶対パスを配列に追加していく
    # →バイナリは含めない
    if row.kind == pcDir or row.path.contains("."):
      files.add(row.path)
  return files
```

再度ドキュメント生成してブラウザから確認すると、コメントが反映されていることがわかります。

```sh
nim doc --project --index:on --outdir:docs src/localserver.nim
```
![スクリーンショット 2022-12-04 13-47-46.jpg](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/295826/0c8a4f5f-ba03-0915-cb23-49bc5987f759.jpeg)

## 複雑なコマンドのショートカットを作る
```sh
nim doc --project --index:on --outdir:docs src/localserver.nim
```

これを何度も入力するのは大変です。nimbleファイルにはコマンドのショートカットをタスクとして登録することができます。NodeJSの`package.json`の`scripts`のところのようなものです。

```diff_nim:localserver.nimble
  # Package

  version       = "0.1.0"
  author        = "Anonymous"
  description   = "A new awesome nimble package"
  license       = "MIT"
  srcDir        = "src"
  bin           = @["localserver"]


  # Dependencies

  requires "nim >= 1.6.8"
  requires "cligen"

+ task docs, "generate html documents":
+   let cmd = "nim doc --project --index:on --outdir:docs src/localserver.nim"
+   exec(cmd)
```

するとnimbleコマンドから呼び出すことができます。
```sh
nimble docs
```

登録したタスクはnimbleコマンドから確認することもできます。
```sh
nimble tasks
> docs        generate html documents
```

## ファイル自体にコメントを書く
ではドキュメントの整備に戻りまして、ファイル自体にコメントを書いていきます。

`src/localserver.nim` の一番上に追記していきます。

```src/localserver.nim
## # local server
## 現在のディレクトリのファイルを返すサーバーです。
## ```sh
## localserver -p:8080
## > start server on http://localhost:8080
## ```
## 
## このように`マークダウン`を書くことができます
## - aaa
## - bbb
##   - ccc

import std/tables
import std/asyncdispatch
import ./lib/server

proc localserver(port=8000) =
　...
```

このように表示されます。
![スクリーンショット 2022-12-04 14-15-40.jpg](https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/295826/2af57c96-065b-8e40-bdcb-48f23a23aaa8.jpeg)


---
---

## おわり

このハンズオンではNimの基本的な文法、標準ライブラリの使い方、公式ドキュメントの読み方、3rdパーティライブラリの使い方、インストールの仕方、テンプレートエンジンからドキュメント生成まで触れました。
公式から提供されているエコシステムの充実さについて理解できたと思います。
このハンズオンをやった方はNimのエコシステムについて全部経験したので、「**Nim完全に理解した！**」と言っても大丈夫です。
これからもNimを使い続けてくれたら嬉しい限りです。

ありがとうございました。
