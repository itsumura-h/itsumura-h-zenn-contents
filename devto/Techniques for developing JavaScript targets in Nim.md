---
title: Techniques for developing JavaScript targets in Nim
published: false
description: 
tags: #nim #javascript #webdev #frontend
cover_image: https://dev-to-uploads.s3.amazonaws.com/uploads/articles/89br4ludq878y7f6lt5o.jpeg
# Use a ratio of 100:42 for best results.
# published_at: 2023-03-06 23:03 +0000
---


In addition to transporting to C and creating executable binaries, Nim can also output JavaScript.
However, this requires a great deal of technique, so I would like to explain it comprehensively and exhaustively in this article.

## Basics of JS Targets
### Compiling
https://nim-lang.org/docs/backends.html#backends-the-javascript-target

js_sample.nim
```nim
echo "hoge"
```

```sh
nim js js_sample.nim
```

The `nim js` command will output `js_sample.js`.
If you have NodeJS in your runtime environment, you can run it as is.

```sh
nim js -r js_sample.nim
```

outputs
```sh
hoge
```

### libraries
There is a standard library for JavaScript that can be used conveniently.

|lib|description|
|---|---|
|[asyncjs](https://nim-lang.org/docs/asyncjs.html)|You can use async/await for asynchronous processing in JS, where `Future[T]` in Nim becomes `Promise<T>` in JS.|
|[dom](https://nim-lang.org/docs/dom.html)|A library for manipulating the DOM, including the `document` and `window` that the browser has.|
|[jsbigints ](https://nim-lang.org/docs/jsbigints.html)|Handles JS BitInt types.|
|[jsconsole](https://nim-lang.org/docs/jsconsole.html)|You can call `conoel.log()` and others.|
|[jscore](https://nim-lang.org/docs/jscore.html)|JS `Math`, `JSON`, `Date` and other libraries are provided, but it is safer to use the Nim standard libraries.|
|[jsffi](https://nim-lang.org/docs/jsffi.html)|This library converts types between Nim and JS mutually.|
|[jsfetch](https://nim-lang.org/docs/jsfetch.html)|HTTP client for API access from JS.|
|[jsheaders](https://nim-lang.org/docs/jsheaders.html)|A library for handling HTTP headers to be used with jsfetch.|
|[jsformdata](https://nim-lang.org/docs/jsformdata.html)|A library for handling HTTP form data for use with jsfetch.|
|[jsre](https://nim-lang.org/docs/jsre.html)|A library for regular expressions in JS.|
|[jsutils](https://nim-lang.org/docs/jsutils.html)|This library provides convenience functions for handling types in JS.|

Another 3rd party library is a wrapper library called [`nodejs`](https://github.com/juancarlospaco/nodejs). It is quite huge.

### How to handle types
Let's see what happens when Nim types are output to JS.

app.nim
```nim
import std/jsffi
import std/times

let i = 0
let j = 0.0
let str = "string"
let cstr:cstring = "cstring"
let date = now()
```

This is converted as follows.

app.js
```js
function makeNimstrLit(c_33556801) {
      var result = [];
  for (var i = 0; i < c_33556801.length; ++i) {
    result[i] = c_33556801.charCodeAt(i);
  }
  return result;
}

function getTime_922747872() {
  var result_922747873 = ({seconds: 0, nanosecond: 0});

    var millis_922747874 = new Date().getTime();
    var seconds_922747880 = convert_922747358(2, 3, millis_922747874);
    var nanos_922747891 = convert_922747358(2, 0, modInt(millis_922747874, convert_922747358(3, 2, 1)));
    result_922747873 = nimCopy(result_922747873, initTime_922747806(seconds_922747880, chckRange(nanos_922747891, 0, 999999999)), NTI922746910);

  return result_922747873;

}

function now_922748331() {
  var result_922748332 = ({m_type: NTI922746911, nanosecond: 0, second: 0, minute: 0, hour: 0, monthdayZero: 0, monthZero: 0, year: 0, weekday: 0, yearday: 0, isDst: false, timezone: null, utcOffset: 0});

    result_922748332 = nimCopy(result_922748332, local_922748328(getTime_922747872()), NTI922746911);

  return result_922748332;

}
var i_469762051 = 0;
var f_469762052 = 0.0;
var str_469762053 = makeNimstrLit("string");
var cstr_469762054 = "cstring";
var date_469762055 = now_922748331();
```

To treat it as a bare string in the JS world, you need to use `cstring`.

### How to handle arrays
The JsObject type is provided to handle dynamic arrays in the JS world.

https://nim-lang.org/docs/jsffi.html#JsObject

```nim
JsObject = ref object of JsRoot
  Dynamically typed wrapper around a JavaScript object.
```

app.nim
```nim
import std/jsconsole
import std/jsffi

proc func1()  =
  let dyArr = newJsObject()
  dyArr["id"] = 1
  dyArr["name"] = "Alice".cstring
  dyArr["status"] = true

  console.log(dyArr)
  console.log(jsTypeOf(dyArr))

func1()
```

Result
```sh
{ id: 1, name: 'Alice', status: true }
object
```

When you define a Nim struct, it is treated as an object in the JS world.
You can use the `to` and `toJs` functions to interconvert between JsObjects and structs.
Since JsObjects do not perform static type checking at compile time, it is better to use structs and their methods for logic as much as possible.

```nim
proc to(x: JsObject; T: typedesc): T:type {.importjs: "(#)"}
  Converts a JsObject x to type T.

proc toJs[T](val: T): JsObject {.importjs: "(#)"}
  Converts a value of any type to type JsObject.
```

app.nim
```nim
type Person = object
  id:int
  name:cstring
  status:bool

proc new(_:type Person, id:int, name:string, status:bool):Person =
  return Person(id:id, name:name.cstring, status:status)

proc func1()  =
  let dyArr = newJsObject()
  dyArr["id"] = 1
  dyArr["name"] = "Alice".cstring
  dyArr["status"] = true

  console.log(dyArr)
  console.log(jsTypeOf(dyArr))

  let person = dyArr.to(Person)
  console.log(person)

  let person2 = Person.new(2, "Bob", false)
  console.log(person2)


func1()
```

Result
```sh
{ id: 1, name: 'Alice', status: true }
object
{ id: 1, name: 'Alice', status: true }
{ id: 2, name: 'Bob', status: false }
```

### Dom manipulation
Let's display the text entered from the HTML input tag on the p tag in real time.

index.html
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <script defer type="module" src="app.js"></script>
  <title>Document</title>
</head>
<body>
  <input type="text" id="input">
  <p id="content"></p>
</body>
</html>
```

app.nim
```nim
import dom

proc onInput(e:Event) =
  let content = document.getElementById("content")
  content.innerText = e.target.value

let input = document.getElementById("input")
input.addEventListener("input", onInput)
```

The following JS file is output.

app.js
```js
function onInput_469762050(e_469762051) {
    var content_469762052 = document.getElementById("content");
    content_469762052.innerText = e_469762051.target.value;


}
var input_469762062 = document.getElementById("input");
input_469762062.addEventListener("input", onInput_469762050, false);
```

The [dom library](https://nim-lang.org/docs/dom.html) allows you to use `Event`, `document`, `getElementById`, etc. from Nim.

### API access
API access is essential for front-end development.
Nim provides the [`jsfetch`](https://nim-lang.org/docs/jsfetch.html) library for API access with JS targets.

app.nim
```nim
import std/asyncjs
import std/jsfetch
import std/jsconsole

proc apiAccess() {.async.} =
  let url:cstring = "https://api.coindesk.com/v1/bpi/currentprice.json"
  let resp = await fetch(url)
  let json = await resp.json()
  console.log(json)

discard apiAccess()
```

The following JS file is output.

app.js
```js
async function apiAccess_469762071() {
  var result_469762073 = null;

  BeforeRet: do {
    var url_469762079 = "https://api.coindesk.com/v1/bpi/currentprice.json";
    var resp_469762087 = (await fetch(url_469762079));
    var json_469762092 = (await resp_469762087.json());
    console.log(json_469762092);
    result_469762073 = undefined;
    break BeforeRet;
  } while (false);

  return result_469762073;

}
var _ = apiAccess_469762071();
```

## Pragmas
Nim requires frequent use of pragmas when developing JS targets.
Pragmas are like annotations in other languages, which allow you to give compile-time instructions to the compiler.

### exportc
The output JS files we have seen so far have suffixes in variable and function names. By using `exportc`, you can prohibit suffixes from being added.

app.nim
```nim
import std/jsconsole
import std/jsffi

proc hello(arg: cstring){.exportc.} =
  let arg {.exportc.} = arg
  console.log("hello " & arg)

let name {.exportc.}: cstring = "Alice"
hello(name)
```

app.js
```js
function hello(arg_469762052) {
    var arg = arg_469762052;
    console.log(("hello " + arg));
}
var name = "Alice";
hello(name);
```

### emit
With emit, the processing you write in is put directly into the output JS file.
When developing a JS target, you can define the bare JavaScript it.

app.nim
```nim
{.emit:"""
function hello(arg){
  console.log("hello " + arg)
}
""".}
```

app.js
```js
function hello(arg){
  console.log("hello " + arg)
}
```

### importjs
It is used to map JS functions to Nim functions so that you can call JS functions from the Nim world.
Using `#` inserts the arguments in order from the front, while using `@` inserts everything after in that position.

app.nim
```nim
import std/jsffi

{.emit:"""
function add(a, b){
  console.log(a + b)
}
""".}

proc add(a, b:int) {.importjs:"add(#, #)".}

add(2, 3)
```

app.js
```js
function add(a, b){
  console.log(a + b)
}

add(2, 3);
```

## Doing Practical Development
Now, based on what we have seen so far, let's call Preact, a lightweight React-like library, from Nim and use it.

https://preactjs.com/

The HTML file used here should look like this.

index.html
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <script defer type="module" src="app.js"></script>
  <title>Document</title>
</head>
<body>
  <div id="app"></div>
</body>
</html>
```

### Call Preact function from Nim.

Import libraries from CDN using `emit` and map library functions to Nim functions using `importjs`.

lib.nim
```nim
import std/dom
import std/jsffi

# ==================== Definition of Preact ====================

{.emit: """
import { h, render } from 'https://cdn.jsdelivr.net/npm/preact@10.11.3/+esm';
import htm from 'https://cdn.jsdelivr.net/npm/htm@3.1.1/+esm';

const html = htm.bind(h);
""".}


type Component* = JsObject

proc html*(arg:cstring):Component {.importjs:"eval('html`' + # + '`')".}
template html*(arg:string):Component = html(arg.cstring)


{.emit: """
function renderApp(component, dom){
  render(html``<${component} />``, dom)
}
""".}
proc renderApp*(component: proc():Component, dom: Element) {.importjs: "renderApp(#, #)".}

# ================== hooks ==================

{.emit:"""
import { useState, useEffect } from 'https://cdn.jsdelivr.net/npm/preact@10.11.3/hooks/+esm';
""".}

type IntStateSetter = proc(arg: int)

proc intUseState(arg: int): JsObject {.importjs: "useState(#)".}
proc useState*(arg: int): (int, IntStateSetter) =
  let state = intUseState(arg)
  let value = to(state[0], int)
  let setter = to(state[1], IntStateSetter)
  return (value, setter)


type StrStateSetter = proc(arg: cstring)

proc strUseState(arg: cstring): JsObject {.importjs: "useState(#)".}
proc useState*(arg: cstring): (cstring, StrStateSetter) =
  let state = strUseState(arg)
  let value = to(state[0], cstring)
  let setter = to(state[1], StrStateSetter)
  return (value, setter)


type States* = cstring|int|float|bool

proc useEffect*(cb: proc(), dependency: array) {.importjs: "useEffect(#, [])".}
proc useEffect*(cb: proc(), dependency: seq[States]) {.importjs: "useEffect(#, #)".}
```

The caller of the library does this.
The JSX part is a string that JS interprets, and the variable or function you want to call on it is expected to be called with the variable name as written there, so use `{.exportc.}` to avoid suffixes.

app.nim
```nim
import std/jsffi
import std/dom
import ./lib

proc App():Component {.exportc.} =
  let (message {.exportc.}, setMessage) = useState("")
  let (msgLen {.exportc.}, setMsgLen) = useState(0)

  proc setMsg(e:Event) {.exportc.} =
    setMessage(e.target.value)

  useEffect(proc() =
    setMsgLen(message.len)
  , @[message])

  return html("""
    <input type="text" oninput=${setMsg} />
    <p>${message}</p>
    <p>message length...${msgLen}</p>
  """)

renderApp(App, document.getElementById("app"))
```

It works like this.
![It works like this.](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/wuz5srd2rhr68qvryk9j.jpg)

### Nim as a static typing in JavaScript
```nim
let (message {.exportc.}, setMessage) = useState("")
```

The `setMessage` here is `StrStateSetter`, a function that only accepts cstring types as arguments.
This is because `lib.nim` defines it as bellow.

```nim
type StrStateSetter = proc(arg: cstring)

proc strUseState(arg: cstring): JsObject {.importjs: "useState(#)".}
proc useState*(arg: cstring): (cstring, StrStateSetter) =
  let state = strUseState(arg)
  let value = to(state[0], cstring)
  let setter = to(state[1], StrStateSetter)
  return (value, setter)
```

What if we try to put an int variable here?

```nim
proc setMsg(e:Event) {.exportc.} =
  # setMessage(e.target.value)
  setMessage(1)
```

Of course compile time error raised.

```sh
/projects/nimjs/app.nim(11, 15) Error: type mismatch: got <int literal(1)>
but expected one of:
StrStateSetter = proc (arg: cstring){.closure.}
```

## Conclusion
I introduced a technique for developing JavaScript targets in Nim.
As you can see, we found that we can very easily create a React-like SPA in Nim using JS assets in a static type-safe manner without using the NodeJS environment.
I will continue to develop a front-end framework made by Nim based on what I have introduced here. I would appreciate your support.
I also hope to see more Nim library assets that wrap JavaScript.

https://github.com/itsumura-h/nim-palladian

https://itsumura-h.github.io/nim-palladian/
