import
  std/httpcore


type Route* = ref object
  path*:string
  httpMethod*:HttpMethod

template serveWithoutPlugin*(routes:untyped):untyped =
  proc threadProc(params:(seq[(Route, Controller)])) {.thread.} =
    proc asyncProc(params:(seq[(Route, Controller)])) {.async.} =
      var server = newAsyncHttpServer(true, true)
      proc cb(req: Request) {.async, gcsafe.} =
        let headers = {"Content-type": "text/plain; charset=utf-8"}
        # let routes = params
        for route in params:
          if req.url.path == route[0].path and req.reqMethod == route[0].httpMethod:
            let resp = route[1].action().await
            await req.respond(Http200, resp, headers.newHttpHeaders())
            break
        await req.respond(Http404, "", headers.newHttpHeaders())

      server.listen(Port(5000))
      while true:
        if server.shouldAcceptRequest():
          await server.acceptRequest(cb)
        else:
          await sleepAsync(500)

    while true:
      try:
        asyncCheck asyncProc(params)
        runForever()
      except:
        echo repr(getCurrentException())

  proc serve(routes:seq[(Route, Controller)]) =
    let countThreads = countProcessors()
    var params:seq[(seq[(Route, Controller)])]
    for i in 1..countThreads:
      params.add(routes)
    when compileOption("threads"):
      echo("Starting ", countThreads, " threads")
      var thr = newSeq[Thread[(seq[(Route, Controller)])]](countThreads)
      for i in 0..countThreads-1:
        createThread(thr[i], threadProc, params[i])
      joinThreads(thr)
    else:
      threadProc(params[0])

  serve(`routes`)
