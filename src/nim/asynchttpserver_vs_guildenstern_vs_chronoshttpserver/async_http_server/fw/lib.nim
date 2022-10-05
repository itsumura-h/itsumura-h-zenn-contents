import
  std/httpcore


template serveWithPlugin*(routes, createPlugin:untyped):untyped =
  proc threadProc(params:(Routes, Plugin)) {.thread.} =
    proc asyncProc(params:(Routes, Plugin)) {.async.} =
      var server = newAsyncHttpServer(true, true)
      proc cb(req: Request) {.async, gcsafe.} =
        let headers = {"Content-type": "text/plain; charset=utf-8"}
        let (routes, plugin) = params
        var hasRoute = false
        for route in routes:
          if req.url.path == route[0].path and req.reqMethod == route[0].httpMethod:
            let resp = route[1].action(plugin).await
            await req.respond(Http200, resp, headers.newHttpHeaders())
            hasRoute = true
            break
        if not hasRoute:
          await req.respond(Http404, "", headers.newHttpHeaders())

      server.listen(Port(5000))
      while true:
        if server.shouldAcceptRequest():
          await server.acceptRequest(cb)
        else:
          await sleepAsync(500)

    try:
      asyncCheck asyncProc(params)
      runForever()
    except:
      echo repr(getCurrentException())

  proc serve(routes:Routes, `createPlugin`:proc():Plugin) =
    when compileOption("threads"):
      let countThreads = countProcessors()
      var params:seq[(Routes, Plugin)]
      for i in 1..countThreads:
        params.add((routes, `createPlugin`()))
      var thr = newSeq[Thread[(Routes, Plugin)]](countThreads)
      for i in 0..countThreads-1:
        createThread(thr[i], threadProc, params[i])
      echo("Starting ", countThreads, " threads")
      joinThreads(thr)
    else:
      echo("Starting ", 1, " thread")
      threadProc((routes, `createPlugin`()))

  serve(`routes`, `createPlugin`)
