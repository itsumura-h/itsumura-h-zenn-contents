---
title: The way integrate Rust into Nim
published: true
description: Let's make use of Rust's assets in Nim!
tags: #nim #rust
cover_image: https://dev-to-uploads.s3.amazonaws.com/uploads/articles/eywyhqmplz8t6izrwtqv.jpg
# Use a ratio of 100:42 for best results.
# published_at: 2023-01-22 15:50 +0900
---

This is the English version of this article.
https://zenn.dev/dumblepy/articles/3db2134ff88763

## Motivation
Nim is a programming language with a simple Python-like syntax that can be transpiled to C and compiled to binary, combining low learning cost, high development productivity, and fast execution speed.
The compiler automatically performs safe scope-based memory management based on ownership and borrowing, and since there is no need to think about references and pointers, "code for coding's sake" can be reduced, especially in application development, and the description can focus solely on the business logic.
However, it is not yet widely used, and when we ask those who do not use it, we often hear that the reason is that "there are not enough libraries.
Nim can easily incorporate assets that already exist in C, because it converts to C once at compile time, and it can work very seamlessly with both dynamic linking and static archives.

Rust, on the other hand, is a thoroughly memory-safe language at the lowest levels, preventing segfaults and memory leaks and running very fast.
However, variable ownership and borrowing must be considered during development, and it is very expensive to learn. It is not a language that is easy to learn, at least not by a second year PHPer with a liberal arts background.

I think it would be a good idea to use Rust for libraries, such as implementing math-based algorithms, and Nim for applications.

Since both Nim and Rust have a mechanism for FFI via the C language, we will use it to experiment with calling libraries created in Rust from Nim applications.

>I am just a beginner with 1 week experience of Rust, I have touched Nim for a long time, but I come from a PHPer background with no C experience and have only done LL languages.
>It is possible that I am writing incorrectly about Rust usage and memory management.
>If you find any, please feel free to comment.

## Build an environment
Create a Docker container with both Nim and Rust environments.

```dockerfile
FROM ubuntu:22.04

# prevent timezone dialogue
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update --fix-missing && \
    apt upgrade -y
RUN apt install -y --fix-missing \
        gcc \
        xz-utils \
        ca-certificates \
        curl \
        pkg-config

WORKDIR /root
# ==================== Nim ====================
RUN curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y
ENV PATH $PATH:/root/.nimble/bin

# ==================== Rust ====================
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

WORKDIR /application
```

## Create a project
Create a `src` directory under `/application` and work from there.

Create a project with Nim
```sh
cd /application/src
nimble init nimapp
```

You will be asked interactively, so use Tab to cycle through the choices and Enter to select one.
For `Package type?`, choose `Binary`.

```sh
  Info: Package initialisation requires info which could not be inferred.
    ... Default values are shown in square brackets, press
    ... enter to use them.
  Using "nimapp" for new package name
Prompt: Your name? [Anonymous]

Answer:       Using "src" for new package source directory
Prompt: Package type?
    ... Library - provides functionality for other packages.
    ... Binary  - produces an executable for the end-user.
    ... Hybrid  - combination of library and binary
    ... For more information see https://goo.gl/cm2RX5
  Select Cycle with 'Tab', 'Enter' when done
Answer: binary
Prompt: Initial version of package? [0.1.0]

Answer:     Prompt: Package description? [A new awesome nimble package]

Answer:     Prompt: Package License?
    ... This should ideally be a valid SPDX identifier. See https://spdx.org/licenses/.
  Select Cycle with 'Tab', 'Enter' when done
Answer: MIT
Prompt: Lowest supported Nim version? [1.6.10]

Answer:    Success: Package nimapp created successfully
```

## Creating a project in Rust
```sh
cd /application/src
cargo new rustlib --lib
```

The directory structure will look like this

```
/application
`-- src
    |-- nimapp
    |   |-- nimapp.nimble
    |   |-- src
    |   |   `-- nimapp.nim
    |   `-- tests
    |       |-- config.nims
    |       `-- test1.nim
    `-- rustlib
        |-- Cargo.toml
        `-- src
            `-- lib.rs
```

## Calling a function
Let's start with a simple add function that adds ints.

### Rust side

```rust
// lib.rs

#[no_mangle]
pub extern "C" fn add(a: i64, b: i64) -> i64 {
    return a + b;
}
```

```rust
#[no_mangle]
```
By attaching this to a function, it can be called from C/Nim with a function name of `add` as defined in Rust.

```rust
pub extern "C"
```
By attaching this to a function, it becomes a function that can be called from C/Nim.

```toml
# Cargo.toml

[package]
name = "rustlib"
version = "0.1.0"
edition = "2021"

# See more keys and their definitions at https://doc.rust-lang.org/cargo/reference/manifest.html

[lib]
name         = "rustlib"
crate-type   = ["cdylib"]
# crate-type   = ["staticlib"]
```

Set `crate-type` when building libraries.
`cdylib` if you are compiling into a dynamic library, or `staticlib` for a static archive.

https://doc.rust-lang.org/nomicon/ffi.html#rust-side

Compile.

```sh
cd /application/src/rustlib
cargo build --release
```

A Shard Object file has been output to `/application/src/rustlib/target/release/librustlib.so`. This is used by calling it from Nim.

### Nim side
Create a file `/application/src/nimapp/src/rustlib.nim` and define the glue functions so that the functions in the shard object can be called from Nim.

```nim
# rustlib.nim

const libpath = "/application/src/rustlib/target/release/librustlib.so"

proc add*(a, b:int64):int64 {.dynlib:libpath, importc: "add".}
```

This is how when you call a static archive.
```nim
const libpath = "/application/src/rustlib/target/release/librustlib.a"

{.passL:libpath.}
proc add*(a, b:int64):int64 {.cdecl, importc: "add".}
```

All that is left is to call this `add` function from within `nimapp.nim`.

```nim
# nimapp.nim

import std/unittest
import ./rustlib

suite "test":
  test "add":
    echo add(1, 2)
    check add(1, 2) == 3
```

Let's execute it.

```sh
cd /application/src/nimapp
nim c -r -f --mm:orc src/nimapp
```
```sh
# output

[Suite] test
3
  [OK] add
```

I was able to call it up.

## Working with dynamic arrays
How can we handle Rust's Vector with Nim?
Here is an explanation using a function that returns a Fibonacci sequence.

### Rust side
Define a function that returns a Fibonacci number, and a function that calls it internally to return the Fibonacci sequence.

```rust
// lib.rs

fn fib(n: u64) -> u64 {
    match n {
        0 => 0,
        1 => 1,
        _ => fib(n - 2) + fib(n - 1),
    }
}

#[no_mangle]
pub extern "C" fn fib_array(n: u64) -> *mut Vec<u64> {
    let mut vector = Vec::with_capacity(n.try_into().unwrap());
    for i in 0..n {
        vector.push(fib(i));
    }
    Box::into_raw(Box::new(vector))
}

#[no_mangle]
pub extern "C" fn get_fib_len(v: &mut Vec<u64>) -> usize {
    v.len()
}

#[no_mangle]
pub extern "C" fn get_fib_item(v: &mut Vec<u64>, offset: usize) -> u64 {
    v[offset]
}
```

The return type of fib_array should be `*mut Vec<u64>` and at the end of the function, call `Box::into_raw(Box::new(vector))` to return a raw pointer to the heap.
We also implement a function that returns the length and offset position values from the vector.

### Nim side

```nim
# rustlib.nim

type FibPtr = ptr object

proc fibArrayLib(n:uint64):FibPtr {.dynlib:libpath, importc: "fib_array".}
proc len(self:FibPtr):int {.dynlib:libpath, importc: "get_fib_len".}
proc `[]`(self:FibPtr, offset:int):int {.dynlib:libpath, importc: "get_fib_item".}
proc fibArray*(n:int):seq[int] =
  let v = fibArrayLib(n.uint64)
  defer: v.dealloc()
  var s = newSeq[int](n)
  for i in 0..<v.len:
    s[i] = v[i]
  return s
```

The return value of Rust's `get_fib_len` is a raw pointer to the heap, so we define our own object as `FibPtr` to map to it.
All Nim functions work with static type checking and overloading, so any functions defined here will only work on objects of type `FibPtr`.
The `fibArray` function calls the functions defined on the Rust side to get the vector length and offset position values from the raw pointer, fill it into Seq(Sequence), Nim's dynamic array, and return it.
In Nim, the raw pointer is outside the scope of Nim's memory management. There is a `dealloc` function to free memory for pointers, and you can use `defer` to make sure that memory is freed when you leave scope.
This `defer` is the same as in the Go language.

Now let's call it in `nimapp`.

```nim
# nimapp.nim

import std/unittest
import ./rustlib


suite "test":
  test "add":
    echo add(1, 2)
    check add(1, 2) == 3

  test "fib array":
    let res = fibArray(10)
    echo res
    check res == @[0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
```

```sh
cd /application/src/nimapp
nim c -r -f --mm:orc src/nimapp
```
```sh
# output

[Suite] test
3
  [OK] add
@[0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
  [OK] fib array
```

I was able to call it up.


## Move processing to a submodule
We have written the add function and the Fibonacci sequence output function in `lib.rs`, but you can move them to a submodule.
You can also move them to a submodule, as this makes the code more readable.

Let's make the Rust directory structure look like this.

```
.
|-- Cargo.lock
|-- Cargo.toml
`-- src
    |-- lib.rs
    `-- submods
        `-- fib.rs
```

Move the process to the fib.rs file.
```rust
// submods/fib.rs

fn fib(n: u64) -> u64 {
    match n {
        0 => 0,
        1 => 1,
        _ => fib(n - 2) + fib(n - 1),
    }
}

#[no_mangle]
pub extern "C" fn fib_array(n: u64) -> *mut Vec<u64> {
    let mut vector = Vec::with_capacity(n.try_into().unwrap());
    for i in 0..n {
        vector.push(fib(i));
    }
    Box::into_raw(Box::new(vector))
}

#[no_mangle]
pub extern "C" fn get_vector_len(v: &Vec<u64>) -> usize {
    v.len()
}

#[no_mangle]
pub extern "C" fn get_vector_item(v: &Vec<u64>, offset: usize) -> u64 {
    v[offset]
}
```

lib.rs should look like this.
```rust
// lib.rs

mod submods {
    pub mod fib;
}

#[no_mangle]
pub extern "C" fn add(a: i64, b: i64) -> i64 {
    return a + b;
}
```

## Handle custom types (proprietary types, structs)
Allows Nim to handle instances of structs defined in Rust.

### Rust side
Create a `submods/person.rs` file.
Define a type `person` with numeric and string fields, its constructor and getter methods.
The function names to be output to FFI should be named so as not to cover as much as possible. For this reason, the name of the method that returns the id is not `id` but `get_person_id`.

```diff
  // lib.rs

  mod submods {
      pub mod fib;
+     pub mod c_ffi;
+     pub mod person;
  }

+ use crate::submods::c_ffi;

  #[no_mangle]
  pub extern "C" fn add(a: i64, b: i64) -> i64 {
      return a + b;
  }
```

```rust
// submods/person.rs

use std::ffi::c_char;
use crate::c_ffi;


pub struct Person {
    id: i64,
    name: String,
}

impl Person {
    pub fn new(id: i64, name: String) -> Box<Person> {
        let person = Box::new(Person { id, name });
        person
    }

    pub fn id(&self) -> i64 {
        self.id
    }

    pub fn name(&self) -> String {
        self.name.to_string()
    }
}

// ==================== FFI ====================
#[no_mangle]
pub extern "C" fn new_person(id: i64, _name: *const c_char) -> *mut Person {
    let name = c_ffi::cstirng_to_string(_name);
    let person = Person::new(id, name);
    Box::into_raw(person)
}

#[no_mangle]
pub extern "C" fn get_person_id(person: &Person) -> i64 {
    person.id()
}

#[no_mangle]
pub extern "C" fn get_person_name(person: &Person) -> *mut c_char {
    c_ffi::string_to_cstring(person.name())
}

// ==================== test ====================
#[cfg(test)]
mod person_tests {
    use super::*;

    #[test]
    fn person_test() {
        let person = Person::new(1, "John".to_string());
        assert_eq!(person.id(), 1);
        assert_eq!(person.name(), "John");
    }
}
```

The type of the `name` argument of the `new_person` function is `*const c_char`. This type is used to handle C strings in Rust.
Conversely, to return a string from Rust to C, use `*mut c_char`.

The return type of the `new_person` function is `*mut person`. This is a raw heap pointer, like the Fibonacci sequence described above.

Both Nim strings and Rust strings are unique types that only work within the execution environment of each language.
Therefore, in order to exchange strings from Nim to Rust via C, they must be converted to each other.
Here, we first created a function on the Rust side to convert C strings to each other's strings.

```rust
// submods/c_ffi.rs

use std::ffi::c_char;
use std::ffi::CStr;
use std::ffi::CString;

pub fn cstirng_to_string(_arg: *const c_char) -> String {
    let arg = unsafe {
        assert!(!_arg.is_null());
        let c_str = CStr::from_ptr(_arg);
        let str_slice = c_str.to_str().unwrap();
        drop(c_str);
        str_slice.to_owned()
    };
    arg
}

pub fn string_to_cstring(_arg: String) -> *mut c_char {
    CString::new(_arg).unwrap().into_raw()
}
```

In `person.rs` this is called.

### Nim side

```nim
# rustlib.nim

type
  PersonObj {.pure, final.} = object
    id:int
    name:cstring

  PersonPtr = ptr PersonObj

  Person* = ref object
    rawPtr: PersonPtr


proc newPerson(id:int, name:cstring):PersonPtr {.dynlib:libpath, importc:"new_person".}
proc new*(_:type Person, id:int, name:string):Person = Person(rawPtr:newPerson(id, name.cstring))

proc getPersonId(self:PersonPtr):int64 {.dynlib:libpath, importc:"get_person_id".}
proc id*(self:Person):int = self.rawPtr.getPersonId().int

proc getPersonName(self:PersonPtr):cstring {.dynlib:libpath, importc:"get_person_name".}
proc name*(self:Person):string = $self.rawPtr.getPersonName()
```

Define the same structure in Nim's object as in Rust's structure definition.

Since it is the raw pointer of the heap that actually interacts with Rust functions, we define a pointer object `PersonPtr` to map to it.
Pointers are outside of Nim's memory management jurisdiction, but `ref` objects with a pointer type field are automatically managed, so you can define `Person* = ref object` to handle them from Nim. This eliminates the need to deallocate memory explicitly.

The type of the `name` argument of `newPerson` is `cstring`. This corresponds to a C string in Nim, and can be type-converted as `"string".cstring`.

In the `name` function we call `getPersonName`, but the return type of `getPersonName` is `cstring`, so we add `$` to convert it to `string`. `$` is a magic method in the Nim world that converts any type to a string. (In fact, it is implemented to convert all types to string with the same function name `$`)

```nim
proc new*(_:type Person, id:int, name:string):Person = Person(rawPtr:newPerson(id, name.cstring))
proc id*(self:Person):int = self.rawPtr.getPersonId().int
proc name*(self:Person):string = $self.rawPtr.getPersonName()
```
These three functions are glue code that is called by the Nim application to call functions like `newPerson` that are mapped to Rust functions and do type conversion.

Let's call them.

```nim
# nimapp.nim

import std/unittest
import ./rustlib


suite "object":
  test "person":
    let person = Person.new(1, "John")
    echo person.repr
    echo person.id()
    echo person.name()
    check:
      person.id() == 1
      person.name() == "John"
```
```sh
# output

[Suite] object
Person(rawPtr: PersonPtr(id: 1, name: "John"))
1
John
  [OK] person
```
Both mapping values to fields in the `PersonPtr' object and calling functions are working well.

## Handling proprietary types with setters
So far we have only dealt with instance creation and getter methods, but does it work with setter methods?
We will illustrate this using the `UpdatablePerson' type, which can update fields.

### Rust side
```diff
  // lib.rs

  mod submods {
      pub mod fib;
      pub mod c_ffi;
      pub mod person;
+     pub mod updatable_person;
  }

  use crate::submods::c_ffi;

  #[no_mangle]
  pub extern "C" fn add(a: i64, b: i64) -> i64 {
      return a + b;
  }
```

```rust
// submods/update_person.rs

use std::ffi::c_char;
use crate::submods::c_ffi;

pub struct UpdatablePerson {
    id: i64,
    name: String,
}

impl UpdatablePerson {
    pub fn new(id: i64, name: String) -> Box<UpdatablePerson> {
        let person = Box::new(UpdatablePerson { id, name });
        person
    }

    pub fn id(&self) -> i64 {
        self.id
    }

    pub fn set_id(&mut self, id: i64) {
        self.id = id
    }

    pub fn name(&self) -> String {
        self.name.to_string()
    }

    pub fn set_name(&mut self, name: String) {
        self.name = name
    }
}


#[no_mangle]
pub extern "C" fn new_updatable_person(id: i64, _name: *const c_char) -> *mut UpdatablePerson {
    let name = c_ffi::cstirng_to_string(_name);
    let person = UpdatablePerson::new(id, name);
    Box::into_raw(person)
}

#[no_mangle]
pub extern "C" fn get_updatable_person_id(person: &UpdatablePerson) -> i64 {
    person.id()
}

#[no_mangle]
pub extern "C" fn set_updatable_person_id(person: &mut UpdatablePerson, id: i64) {
    person.set_id(id)
}

#[no_mangle]
pub extern "C" fn get_updatable_person_name(person: &UpdatablePerson) -> *mut c_char {
    c_ffi::string_to_cstring(person.name())
}

#[no_mangle]
pub extern "C" fn set_updatable_person_name(person: &mut UpdatablePerson, _name: *const c_char) {
    let name = c_ffi::cstirng_to_string(_name);
    person.set_name(name)
}


#[cfg(test)]
mod updatable_person_test {
    use super::*;

    #[test]
    fn test1() {
        let mut person = UpdatablePerson::new(1, "John".to_string());
        assert_eq!(person.id(), 1);
        assert_eq!(person.name(), "John");
        person.set_id(2);
        person.set_name("Paul".to_string());
        assert_eq!(person.id(), 2);
        assert_eq!(person.name(), "Paul");
    }
}
```

### Nim side
```nim
# rustlib.nim

type
  UpdatablePersonObj {.pure, final.} = object
    id:int
    name:cstring

  UpdatablePersonPtr = ptr UpdatablePersonObj

  UpdatablePerson* = ref object
    rawPtr: UpdatablePersonPtr


proc newUpdatablePerson(id:int, name:cstring):UpdatablePersonPtr {.dynlib:libpath, importc:"new_updatable_person".}
proc new*(_:type UpdatablePerson, id:int, name:string):UpdatablePerson = UpdatablePerson(rawPtr:newUpdatablePerson(id, name.cstring))

proc getUpdatablePersonId(self:UpdatablePersonPtr):int64 {.dynlib:libpath, importc:"get_updatable_person_id".}
proc id*(self:UpdatablePerson):int = self.rawPtr.getUpdatablePersonId().int

proc setUpdatablePersonId(self:UpdatablePersonPtr, id:int) {.dynlib:libpath, importc:"set_updatable_person_id".}
proc setId*(self:UpdatablePerson, id:int) = self.rawPtr.setUpdatablePersonId(id)

proc getUpdatablePersonName(self:UpdatablePersonPtr):cstring {.dynlib:libpath, importc:"get_updatable_person_name".}
proc name*(self:UpdatablePerson):string = $self.rawPtr.getUpdatablePersonName()

proc setUpdatablePersonName(self:UpdatablePersonPtr, name:cstring) {.dynlib:libpath, importc:"set_updatable_person_name".}
proc setName*(self:UpdatablePerson, name:string) = self.rawPtr.setUpdatablePersonName(name.cstring)
```

Call.

```nim
# nimapp.nim

import std/unittest
import ./rustlib


suite "object":
  test "updatable person":
    let person = UpdatablePerson.new(1, "John")
    echo person.repr
    echo person.id()
    echo person.name()
    check:
      person.id() == 1
      person.name() == "John"

    person.setId(2)
    person.setName("Paul")
    echo person.repr
    echo person.id()
    echo person.name()
    check:
      person.id() == 2
      person.name() == "Paul"
```
```sh
# output

[Suite] object
UpdatablePerson(rawPtr: UpdatablePersonPtr(id: 1, name: "John"))
1
John
UpdatablePerson(rawPtr: UpdatablePersonPtr(id: 2, name: "Paul"))
2
Paul
  [OK] updatable person
```

Using a setter, it was successfully invoked.

## Using Rust's libraries
So far we have been calling our own implementation of the process, but what we really want to do is use Rust's rich library assets from Nim.
Let's call a library from Nim that implements the elliptic curve cryptography used in the blockchain domain.

https://docs.rs/p256/latest/p256/

### Creating a private key
The private key used in Ethereum is a 256-bit (32-byte) random number consisting of 32 numbers (8 bits) ranging from 0 to 255.

#### Rust side
```sh
cargo add p256 rand_core hex
```

```rust
// submods/crypto.rs

use hex::decode as hex_decode;
use hex::encode as hex_encode;
use p256::ecdsa::signature::{Signer, Verifier};
use p256::ecdsa::{Signature, SigningKey, VerifyingKey};
use rand_core::OsRng;
use std::ffi::c_char;

use crate::submods::c_ffi::{cstirng_to_string, string_to_cstring};

#[no_mangle]
pub extern "C" fn create_secret_key() -> *mut Vec<u8> {
    let secret_key: SigningKey<NistP256> = SigningKey::random(&mut OsRng);
    let v: Vec<u8> = secret_key.to_bytes().to_vec();
    Box::into_raw(Box::new(v))
}

#[no_mangle]
pub extern "C" fn get_secret_key_len(v: &mut Vec<u8>) -> usize {
    v.len()
}

#[no_mangle]
pub extern "C" fn get_secret_key_item(v: &mut Vec<u8>, offset: usize) -> u8 {
    v[offset]
}
```

The secret key is an array of 32 8-bit numbers. As in the Fibonacci sequence example, it is passed to Nim as a pointer to a `vector', and the length and offset are used to extract a single value and return it as a `seq' on the Nim side.

#### Nim side
```nim
# rustlib.nim

type SecretKey = ptr object

proc createSecretKeyLib():SecretKey {.dynlib:libpath, importc:"create_secret_key".}
proc len(self:SecretKey):int {.dynlib:libpath, importc:"get_secret_key_len".}
proc `[]`(self:SecretKey, offset:int):uint8 {.dynlib:libpath, importc:"get_secret_key_item".}
proc createSecretKey*():seq[uint8] =
  let secretKey = createSecretKeyLib()
  defer: secretKey.dealloc()
  var s = newSeq[uint8](secretKey.len())
  for i in 0..<secretKey.len().int:
    s[i] = secretKey[i]
  return s
```

```nim
# nimapp.nim

import std/unittest
import ./rustlib


suite "crypto":
  test "secret key":
    let secretKey = createSecretKey()
    echo secretKey
```

```sh
# output

[Suite] crypto
@[39, 234, 215, 165, 187, 41, 126, 106, 147, 128, 126, 120, 235, 187, 243, 63, 97, 84, 236, 27, 126, 195, 100, 93, 40, 90, 142, 186, 63, 11, 152, 44]
  [OK] secret key
```

### create private key 2
Private keys are usually treated as a hexadecimal string starting with `0x`, so they should be output in that form.

```rust
// submods/crypto.rs

#[no_mangle]
pub extern "C" fn create_secret_key_hex() -> *mut c_char {
    let secret_key: SigningKey<NistP256> = SigningKey::random(&mut OsRng);
    let bytes: GenericArray<u8, {unknown}.> = secret_key.to_bytes();
    let slices: &[u8] = bytes.as_slice();
    let hex_str: String = hex_encode(&slices);
    string_to_cstring(hex_str)
}
```

#### Nim側
```nim
# rustlib.nim

proc createSecretKeyHexLib():cstring {.dynlib:libpath, importc:"create_secret_key_hex".}
proc createSecretKeyHex*():string = "0x" & $createSecretKeyHexLib()
```
0x is prepended in the `createSecretKeyHex` function.

```nim
# nimapp.nim

import std/unittest
import ./rustlib


suite "crypto":
  test "hex key":
    let key = createSecretKeyHex()
    echo key
```

```sh
# output

0xa44401854dad16e2f56bd8e637a550f6c0904393ac6cb4286e4e3dc5ebf4f3ed
  [OK] hex key
```

Output successfully.


### Signing and Verifying Signatures
Signing is the process of verifying that a certain text has been encrypted with a certain private key.
A sentence encrypted with a private key can only be signed with a public key generated from the same private key.
Verifying that a sentence was actually encrypted by someone using that private key is called verification.

#### Rust side
Create three functions: a function to create a public key from a private key, a function to sign a document, and a function to verify a document.
1. sign a text with the private key
2. generate a public key from the private key
3. Verify the signature using the hash generated from the public key, the original text and the signature.
The process is as follows.

```rust
// submods/crypto.rs

#[no_mangle]
pub extern "C" fn create_verifying_key(_secret_key: &mut c_char) -> *mut c_char {
    let str_secret_key: String = cstirng_to_string(_secret_key);
    let b_key: &Vec<u8> = &(hex_decode(str_secret_key).unwrap());
    let signing_key: SigningKey<NistP256> = SigningKey::from_bytes(b_key).unwrap();
    let verifying_key: VerifyingKey<NistP256> = signing_key.verifying_key();
    let encoded_point: EncodedPoint<{unknown}> = verifying_key.to_encoded_point(true);
    let str_signature: Stirng = encoded_point.to_string();
    string_to_cstring(str_signature)
}

#[no_mangle]
pub extern "C" fn sign_message(_secret_key: &mut c_char, _msg: &mut c_char) -> *mut c_char {
    let str_secret_key: String = cstirng_to_string(_secret_key);
    let b_key: &Vec<u8> = &(hex_decode(str_secret_key).unwrap());
    let signing_key: SigningKey<NistP256> = SigningKey::from_bytes(b_key).unwrap();

    let msg: String = cstirng_to_string(_msg);
    let b_msg: &[u8] = msg.as_bytes();

    let verifying_key: Signature<NistP256> = signing_key.sign(b_msg);
    let str_signature: String = verifying_key.to_string().to_lowercase();
    string_to_cstring(str_signature)
}

#[no_mangle]
pub extern "C" fn verify_sign(
    _verifying_key: &mut c_char,
    _msg: &mut c_char,
    _signature: &mut c_char,
) -> bool {
    let str_verifying_key: String = cstirng_to_string(_verifying_key);
    let b_key: &Vec<u8> = &(hex_decode(str_verifying_key).unwrap());
    let slice_b_key: &[u8] = b_key.as_slice();
    let verifying_key: VerifyingKey<Nist256> = match VerifyingKey::from_sec1_bytes(slice_b_key) {
        Ok(verifying_key: VerifyingKey<Nist256>) => verifying_key,
        Err(_e: Error) => return false,
    };

    let msg: String = cstirng_to_string(_msg);
    let b_msg: &[u8] = msg.as_bytes();

    let str_signature: String = cstirng_to_string(_signature);
    let vec_signature: Vec<u8> = hex_decode(str_signature).unwrap();
    let b_signature: &[u8] = vec_signature.as_slice();
    let signature: Signature<Nist256> = match Signature::try_from(b_signature) {
        Ok(signature: Signature<Nist256>) => signature,
        Err(_e: Error) => return false,
    };

    verifying_key.verify(b_msg, &signature).is_ok()
}
```

#### Nim side
```nim
# rustlib.nim

proc createVerifyingKeyLib(secret:cstring):cstring {.dynlib:libpath, importc:"create_verifying_key".}
proc createVerifyingKey*(secret:string):string =
  let secret = secret[2..^1] # 先頭の0xを削除
  return "0x" & $createVerifyingKeyLib(secret.cstring)

proc signMessageLib(key, msg:cstring):cstring {.dynlib:libpath, importc:"sign_message".}
proc signMessage*(key, msg:string):string =
  let key = key[2..^1] # 先頭の0xを削除
  return "0x" & $signMessageLib(key.cstring, msg.cstring)

proc verifySignLib(verifyKey, msg, signature:cstring):bool {.dynlib: libpath, importc:"verify_sign".}
proc verifySign*(verifyKey, msg, signature:string):bool =
  let verifyKey = verifyKey[2..^1 ]# 先頭の0xを削除
  let signature = signature[2..^1] # 先頭の0xを削除
  return verifySignLib(verifyKey.cstring, msg.cstring, signature.cstring)
```

```nim
# nimapp.nim

import std/unittest
import ./rustlib


suite "crypto":
  test "verifying key":
    let secret = createSecretKeyHex()
    echo "=== secret key"
    echo secret
    echo "=== verify key"
    echo createVerifyingKey(secret)

  test "sign message":
    let msg = "Hello World"
    let secretKey = createSecretKeyHex()
    let signature = signMessage(secretKey, msg)
    echo "=== signature"
    echo signature
    let verifyKey = createVerifyingKey(secretKey)
    echo "=== verify key"
    echo verifyKey
    let isValid = verifySign(verifyKey, msg, signature)
    echo "=== expect true"
    echo isValid
    check isValid

  test "wrong message":
    let msg = "Hello World"
    let secret = createSecretKeyHex()
    let signature = signMessage(secret, msg)
    echo "=== signature"
    echo signature
    let verifyKey = createVerifyingKey(secret)
    echo "=== verify key"
    echo verifyKey
    let res = verifySign(verifyKey, "wrong hello", signature)
    echo "=== expect false"
    echo res
    check res == false

  test "wrong signature":
    let msg = "Hello World"
    let secret = createSecretKeyHex()
    let signature = signMessage(secret, msg)
    echo "=== signature"
    echo signature
    var expectWrong = verifySign("0x012345abcdef", msg, signature)
    echo "=== expect false"
    echo expectWrong
    check expectWrong == false
```

```sh
# output

=== secret key
0x61ee88fb30fe88e1bd0bafae57f78811c678b58a55401c5e64c714f8907da3a6
=== verify key
0x035C687146BF98F3935AA4E0B267522765ED7C15B17FC08372E115869D92922615
  [OK] verifying key

=== signature
0xf1f6bbe1345faaa3c3514b6ca01324602d9ab0344b38439574fda2b70a3c092462ffef099a068126aa8764637f9efce89554a94018f7c56d2f26210b120da33d
=== verify key
0x03EB937AF6C821116418A7BEF874974BED79ED43AC39B2D5CE28802C1971AC3BBC
=== expect true
true
  [OK] sign message

=== signature
0x606bb9b3b9094057aadc2f4563923fdfc6d4a73f6991e530e3e60fc346c2d4245c2544be8dabb0535fe8cab0b8119b8920cf89a44e5f518bbe4f5c86b435be5a
=== verify key
0x0253FF110C708A36E15F18B4784E48473B3EC74485CD1E6D0AA989580CEF4F65CF
=== expect false
false
  [OK] wrong message

=== signature
0xb83a17ac892234b3b840c8d45cd2a8e1d4b68601d2a3dc52cad4fa86c13116150cc8288b0ffed750e0af45cd8d600875b06b1db0c4f7077828927b3d34155433
=== expect false
false
  [OK] wrong signature
```

The signature has been verified correctly.

## Conclusion
We now know that we can use the FFI feature of Nim and Rust to exchange values with each other.
Now we can use Rust's resources in Nim! **Let's build a library that wraps Rust in Nim and build applications in Nim!!!**

I thought it was a bit difficult to do type puzzles on the Rust side for FFI, and that pointers had to be explicitly opened on the Nim side.
The numeric side and bool are almost fine as is, but strings, arrays, and unique types that are stacked on the heap can be handled by doing the following.

|type|Nim's argument|Nim's return value|Rust's argument|Rust's return value|
|---|---|---|---|---|---|
|String|cstring|cstring|&mut c_char|*mut c_char / *const c_char|
|Array|type T = ptr object|type T = ptr object|&mut Vec<T>|*mut Vec<T>|
|unique type|type T = ptr object|type T = ptr object|&T / &mut T|*mut T|

Rust also has a library called [`safer_ffi`](https://github.com/getditto/safer_ffi) that makes FFI easier, and I tried to use that, but the library seems to be immature, and I could not get arguments in Rust functions.
If this library can be used properly, it will be possible to output C header files from Rust functions and automatically generate Nim interface functions from C header files using [c2nim](https://github.com/nim-lang/c2nim). We look forward to further development of this feature.
