# Move semantics for Nim

Hello, I’m Andreas Rumpf, the original inventor and still the lead developer of Nim. Today, I’m going to talk about move semantics, which is the new feature coming to Nim, inspired by Rust and C++. However, we’ve tweaked it, so let’s get started.

The unofficial motto of Nim is actually, “Copying bad design is not good design.” This motto is useful because it tells us what not to do. We shouldn’t copy bad designs. More useful than knowing what not to do is knowing what to do. So, paraphrasing this into “recombine good bits from several sources,” and that’s what we did. We looked at Rust, C++, and Swift to see how they handle memory management and whether these concepts apply to Nim. It turns out the answer is yes.

```nim
var someNumbers = @[1, 2]
someNumbers.add 3
```

Here’s an example: I have an array with two elements inside, and then I append the number three to it. This is a growing array. In C++, it’s called a vector; in Nim, it’s called a sequence.

```
someNumbers

Length: 2     ┌──> 1
Capacity: 2   │    2
Data──────────┘
```

Here’s what happens in memory: we have this global array, which actually has a length, a capacity, and a single pointer to a block of memory that can grow.

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

When we append a number and the capacity is already full—like we had capacity for two elements—we need to create a new block of memory that is big enough to contain all three numbers. We also need to do something with the old memory block. Usually, you would say it’s a realloc in C, which would free the old block immediately. Now, this is the most effective way of doing things.

```nim
var someNumbers = @[1, 2]
var other = someNumbers
someNumbers.add 3 # other contains dangling pointer
```

However, it causes a problem. If I have other aliases to this pointer, I must ensure that it doesn’t cause a dangling pointer. For example, in line two, I have this other variable that should have the same contents as “someNumbers.” If I do a shallow copy and just copy all the bits, then I would copy the pointer, which is invalidated in line three by the append, causing this to contain a dangling pointer. This would be very unsafe and a very bad idea.

```nim
var someNumbers = @[1, 2]
var other = someNumbers
someNumbers.add 3 # other has dangling pointer
```
- Solution: Create a new sequence with the same elements. ("Deep" copy: C++98, Nim)
- Solution: Use a pointer to a pointer (Slower. many allocations)
- Solution: Disallow the assignment
- Solution: Use a GC mechanism to free the old block
- Solition: "Steal" the memory. **Move** the block


To solve this problem, there are a couple of solutions. One is to deep copy the elements in the container, which is what C++ does and also what Nim’s move semantics do. You could also say, “Okay, let’s have a pointer to a pointer, so everybody gets the new update.” This is done in Java and C#, but it’s slightly less efficient because then you have another indirection. You could also say, “Well, this is an assignment, but it’s a bad assignment, so let’s just forbid it.” This would be a terrible solution. Another solution, as I mentioned, is to have a garbage collector clean up this bad pointer for you, but only if no other variable refers to it. Finally, we could move it, which is the fifth point here. We could steal the block of memory and perform a move, and that’s also available in C++. So, this would be an explicit move in Nim.

```nim
var someNumbers = @[1, 2]
var other = move(someNumbers)
# someNumber is empty now
someNumbers.add 3

assert someNumbers == @[3]
```

If you can do this, you can say, “I’m going to move these numbers over to ‘other,’” and then afterward, the source is invalidated, so it becomes an empty sequence. If you then append the number three, that’s the only thing left inside. As you can see in line six, after that, “someNumbers” only has the three inside.

This is the explicit move. You can try to program in this style, and it’s not really pleasant. However, if it’s explicit, it’s okay because you are aware that “someNumbers” is empty afterward. But there are plenty of cases where you can move implicitly.

```nim
var a = f()
 # can move f's result into a
```

The first famous example is if you have a result of a function call, and you know it’s not going to be used afterward, so you can move it directly into the variable. Then, you could also say that if you know it’s not used afterward, you can move it.

```nim
var namedValue = g()
var a = f(namedValue) # can move namedValue into 'f'
# can move f's result into a
```

One design goal was to make this work so that function calls can be moved, but I want to be able to name my results for readability without a performance overhead. As long as the named value is a local variable, the Nim compiler can see that the named value is used for the function call and not afterward, so it would move the named value into the function, and then it would move the function’s result into “a.”

```nim
var x = @[1, 2, 3]
var y = x # is last read of 'x', can move into 'y'
var z = y # is last read of 'y', can move into 'z'
```

Here’s another example: I have a list with three integers inside, and if I say “y = x,” then, since “x” isn’t used anymore, we can move. Likewise for “z = y.” So this works for local variables.

```nim
func put(t: var Table; key: string; value: seq[string]) =
  var h = hash(key)
  t.slots[h] = value # copy here :-(

var values = @["a", "b", "c"]
tab.put("key", values)
```

Let’s think about parameters, though, which can cause problems because we don’t know if the value that has been passed to the function is used afterward. In this example, I’m showing pseudocode for a hash table implementation. Usually, it would be more than two lines, but this is a simple example. We hash the value and want to move this key-value pair into the table. Given the current semantics, this would mean making an expensive copy operation here.

```nim
func put(t: var Table; key: string; value: sink seq[string]) =
  var h = hash(key)
  t.slots[h] = value # move here :-)

var values = @["a", "b", "c"]
tab.put("key", values) # last use of 'values', can move
```

However, you can annotate this parameter value to use the `sink` keyword, which ensures that it won’t be used afterward, allowing us to perform the move inside the function.

```nim
func put(t: var Table; key: string; value: sink seq[string]) =
  var h = hash(key)
  t.slots[h] = value # move here :-)

var values = @["a", "b", "c"]
tab.put("key", values) # not last use of 'values', can't move
echo values

>> Warning: Passing a copy to a sink paramater.
```

Again, if I have values like a list with three strings inside, and I don’t use them afterward, I can move them. Now, what happens if I do use the values afterward? Since we want to take ownership of this object’s contents, the compiler produces a warning, telling us that we are about to sink something that is used afterward. It will make a copy to ensure safety. So, if you get it wrong, the performance suffers, but there are no weird crashes. The compiler also warns about the performance aspect. Currently, this warning is overly aggressive, so I need to make it a bit better.

```nim
func put(t: var Table; key: string; value: sink seq[string]) =
  var h = hash(key)
  t.slots[h] = value # move here :-)

var values = @["a", "b", "c"]
echo values
tab.put("key", values)

>> Solution: Move code around.
```

One solution would be to move it around. If you echo the values before embedding them into the hash table, it would work because the compiler knows that `echo` doesn’t want to take ownership of the values, but `tablePut` does because of the `sink` annotation. Of course, if you are just adding code for debugging purposes, you don’t care if it causes more copies because this code will be removed soon afterward.

- A `sink` parameter is an optimization.
- If you get it wrong, only performance is affected.

```nim
func `[]=`[K, V](t: var Table[K, V]; k: K, v: V)
func `==`[T](a, b: T):bool
func `+`[T](a, b: T): T
func add[T](s: var seq[T]; v: T)
```

As I said, the `sink` parameter is an optimization. You don’t have to use it. If you get it wrong, performance is worse than before; if you get it right, you get better performance. We are also working on inferring this property so that you don’t have to annotate it at all. I went through the standard library trying to add these `sink` annotations everywhere, and I said, “Yeah, no, I’m not going to do that. I’ll let the compiler figure this out.”

Here are a couple of favorite examples: we have a hash table, and this is the “put” function (or whatever you want to call it, like insert or update). Then we have equality on some generic type `T`, or `plus` on `T`, and finally, `append` or `add` on a global sequence. The question is, where do we put the `sink` annotation? You don’t have to guess; I'm telling you.

```nim
func `[]=`[K, V](t: var Table[K, V]; k: sink K, v: sink V)
func `==`[T](a, b: T):bool
func `+`[T](a, b: T): T
func add[T](s: var seq[T]; v: sink T)
```

For embedding stuff into a hash table, the `sink` annotation is used. The `append` function for sequences also takes the `sink` annotation. Now, consider the first line as an insert or an update. If I insert into the hash table, I also want to take ownership of the key. But if it’s just an update on the table, I already have the key, so what happens? Should it be `sink` or not? Well, I don’t know. But the thing is, if you do this with `sink`, the compiler will ensure that the value is consumed in all cases, so you don’t have to worry about that.

```nim
func get[K, V](t:Table[K, V]; key: K): V =
  var h = hash(key)
  result = t.slots[h] # copy here?
```

There is also some notion of what it means to consume something. We are going to discuss destructors soon. Anyhow, there’s a different problem. Now, I can put stuff into a hash table very efficiently, which is good. But how do I get values out of it? Again, we face the same problem: the “result = something” line is essentially a return statement in Nim, but I wrote it as an assignment to make it more obvious that this is an expensive copy.

```nim
func get[K, V](t:Table[K, V]; key: K): V =
  var h = hash(key)
  result = move(t.slots[h]) # does not compile
```

So, okay, we can try to move this, but then the compiler will complain that `T` is not mutable; you cannot move out of it because a move mutates the source.

```nim
func get[K, V](t:var Table[K, V]; key: K): V =
  var h = hash(key)
  result = move(t.slots[h]) # does compile, but it's a bit dangerous
```

So, let’s make it mutable. This works, but now you need to think: what happens? You move the value out of this table, so you can access it exactly once, and then it’s gone afterward. This is pretty bad unless you have a pop operation for your stack—that’s exactly what you want—but for a hash table, it’s pretty bad.

```nim
func get[K, V](t: Table[K, V]; key: K): lent V =
  var h = hash(key)
  result = t.slots[h] # "borrow", no copy, no move.
```

Here, we need another annotation, which is “lending” a value, or `lent v`. This is a borrowing operation. In Rust, this would be a borrowed pointer; in C++, it’s a reference. It’s the same thing. You need to ensure that once you borrow, this doesn’t outlive the collection’s lifetime, but yeah, it’s the same concept.
The point is, in Rust, this would be checked, and in C++, it wouldn’t. In Nim, it is checked, but we need to improve it. So now that we understand how to optimize complex assignments like deep copies, we can apply this knowledge to something else, like reference counting.

- We have seen how to optimize away sequence copies.
- The same principales apply to reference counting (=RC).
- "Copy reference" - incRc(src); decRc(src); dest = src
- "Move reference" - dest = src
- Led to the development of the --gc:arc mode.

Reference counting is basically the pointer assignment, just gotten way more expensive than it used to be because if I copy a pointer around, I need to increment the reference count of the source, decrement the reference count of the destination, and then I can do the pointer copy.
But **if I am able to move the pointer**, then that could just be a bitwise copy, and maybe I can nullify the source afterward if required.
This insight led us to the development of a new garbage collector mode. It’s called GC, but GC is actually Nim’s name for any kind of memory management that you want to use.

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

Here, I have a benchmark. This is the binary tree—a standard benchmark for the throughput of a garbage collector. I don’t expect you to understand all of this, but the point is, now, **all the annotations like `sink` and `lend` are not there**, but even so, they work under the hood for us.
So, if you create binary trees and trillions of them to some depth.

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

This is the main part. As I said, it’s a standard benchmark, and the results are really nice.

|Memory management strategy|Time|Peak Memory|
|---|---|---|
|mark&sweep GC|17s|588.047MiB|
|deferred refcounting GC|16s|304.074MiB|
|Boehm GC|12s|N/A|
|ARC|**6.75s**|472.098MiB|

We have a couple of garbage collectors to compare, and the new one is the fastest by a lot—a factor of two or three, depending on what you compare it with. Memory consumption is about the same as before. I haven’t been able to figure out the memory consumption precisely, so that’s not available yet. This is better than before.

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

Now, the question is, how does it compare to manual memory management? In Nim, you can do both, so you can use your own pointers. Previously, this was a reference in line four. Now, it’s a pointer. To make a tree, we have this nasty allocation with a cast in line twelve. Of course, we need to free the tree manually. This is the recursive free: first free the left, then the right, and then deallocate this node. Again, this is the process.

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

Now, in the main part, we have to free these trees manually, which is very annoying. For instance, in line 18, you can see this, or in line 15, where we had to introduce a new temp variable just to be able to free it later on.

|Memory management strategy|Time|Peak Memory|
|---|---|---|
|mark&sweep GC|17s|588.047MiB|
|deferred refcounting GC|16s|304.074MiB|
|Boehm GC|12s|N/A|
|ARC|**6.75s**|472.098MiB(379.074MiB)|
|manual|5.23s|244.563MiB|
|manual(with RC)|6.244s|379.074MiB|

The result is that it’s still slower. I’m sorry, but here’s the thing: what ARC actually does is optimize reference counting. The manual version, on the other hand, essentially doesn’t have a reference count because I know these are unique pointers. If you add just the machine word for this reference count back to this manual version, it’s back to almost the same performance, at around 26.2 seconds, whereas ARC is at 27 seconds. The memory consumption is identical under the assumption that I fixed this one bug that’s left. We are getting close to manual memory management in this particular benchmark. I think we can get the difference down to the noise level, but we’re not there yet. I’ll keep working on that.

|Memory management strategy|Latency|Total Time|Peak Memory|
|---|---|---|---|
|defferd refcountng GC|0.0356ms|0.314s|300MiB|
|ARC|0.0106ms|0.254s|271MiB|

There’s a different benchmark for latency, but I don’t have the source code for this one. Previously, we had a soft real-time garbage collector, and the latency was 0.03 milliseconds for this benchmark. Now, with ARC, it’s better by a factor of three. The total runtime has also been reduced, and peak memory consumption is better. So, not only is throughput better, but also latency.

- Custom destructors. assignments and move optimization.
- Files/sockets etc can be closed automatically.
- Enable composition between specialized memory management solutions.

I’ve already outlined what’s going on under the hood: we have destructors, move operators, and assignments, and you can exploit them for other things. They are exposed to you, as we will see in a minute. Now, you can make your files close automatically after use, which is very nice. There’s better composition between these custom containers. Previously, we had manual memory management and GC memory management, and you had to be careful not to mix them because it didn’t really work well. But with these extension points, the interoperability between these two worlds is much better than before.

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

Here’s another thing we can do: again, the same benchmark, but now we want to have some object pool, or better called an arena. We have an arena allocator, still dealing with these silly nodes that only have two pointers inside.

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

To allocate a new node, we basically check if there’s capacity left, kind of like for a sequence, and then we—but the node itself is an unchecked pointer. So, we take the address of the element in the array, which is the backup storage for our node.

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

Now, we can say, “Look, if you want to copy a pool, it’s not supported because I couldn’t be bothered to implement it.” If you try to copy the pool around accidentally, the compiler will complain and tell you, “No, you can’t.” If the pool goes out of scope, the destructor is called in line 93. What do you do in a destructor? Well, you free the blocks of memory that have been chained in a linked list with this `next` pointer. 

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

Then you need to change the program, unfortunately. If you want to make a tree, you need to be aware of this pool, where to get the new nodes from, so this becomes a parameter of this makeTree function. Recursively, you need to pass it on, as you can see in lines 11 and 12.

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

Now, the benchmark—it’s a bit easier to use because these pools are freed for us automatically afterward. In this case, I had to make two pools: one for long-lived data and one for short-lived data. You can see this in lines 5 and 14.

|Memory management strategy|Time|Peak Memory|
|---|---|---|
|mark&sweep GC|17s|588.047MiB|
|deferred refcounting GC|16s|304.074MiB|
|Boehm GC|12s|N/A|
|ARC|6.75s|472.098MiB(379.074MiB)|
|manual|5.23s|244.563MiB|
|manual(with RC)|6.244s|379.074MiB|
|object pooling|**2.4s**|251.504MiB|


The question is, how does it perform? The result is that it’s still much faster—a factor of two improvement in performance, and memory consumption is roughly the same.

- Move semantics mostly work under the hood.
- `sink` and `lent` anotations are optional.
- Leads the incredible speedups and algorithm improvements.
- Make Nim faster and "deterministic"
- New strategies improves:
  - throughput
  - latency
  - memory consumption
  - threading
  - ease of programming
  - flexibility composition

In summary, move semantics mostly work under the hood for us. They give us really good optimizations—five minutes left, okay. We’ve seen the speedups, and they make memory management deterministic. What’s actually the case here? If you use a reference counting scheme and optimize it, you can attach a cost model to your programming language. Once you do that, you get into the realm of hard real-time systems. So, you can use Nim for hard real-time systems with this technology. We’ve seen that it improves throughput, latency, memory consumption, and threading. Well, I don’t have an example, but as you can imagine, if you can move data from one thread to another, and you’re guaranteed that this is the last user of this data, then you cannot have data races, which is a very nice feature.

It also improves the ease of programming. Just imagine: your files are closed automatically, your sockets are closed automatically, and you get better composition between these different container classes. You can play with these benchmarks. I’ve uploaded them to GitHub. If you don’t know already, there’s our website, the forum, and we are active on IRC as well. So, that’s my talk. Thank you for your attention.
