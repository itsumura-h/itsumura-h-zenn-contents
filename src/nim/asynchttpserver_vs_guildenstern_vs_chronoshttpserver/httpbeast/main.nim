import
  std/httpcore,
  std/asyncdispatch,
  std/options,
  allographer/connection,
  allographer/query_builder,
  ./lib/httpbeast,
  ./setting,
  ./controllers

let routes = @[
  (Route(path:"/plaintext", httpMethod:HttpGet), Controller.new(plainText)),
  (Route(path:"/json", httpMethod:HttpGet), Controller.new(json)),
  (Route(path:"/queries", httpMethod:HttpGet), Controller.new(queries))
]

proc cd(req: Request, routes:Routes, plugin:Plugin): Future[void] {.async.}=
  var hasRoute = false
  for route in routes:
    if req.path.get() == route[0].path and req.httpMethod.get() == route[0].httpMethod:
      let resp = route[1].action(req, plugin).waitFor()
      req.send(resp)
      hasRoute = true
      break
  if not hasRoute:
    req.send(Http404)

let settings = initSettings(port=Port(5000), reusePort=true)

# run(onRequest, settings, initDb)

proc createPlugin*():Plugin =
  return Plugin.new()

# serveWithPlugin(onRequest, routes, createPlugin)


type OnRequest* = proc (req: Request, routes:Routes, plugin:Plugin): Future[void] {.gcsafe.}

proc processEvents(selector: Selector[Data],
                  events: array[64, ReadyKey], count: int,
                  onRequest: OnRequest,
                  routes:Routes,
                  plugin:Plugin) =
  for i in 0 ..< count:
    let fd = events[i].fd
    var data: ptr Data = addr(selector.getData(fd))
    # Handle error events first.
    if Event.Error in events[i].events:
      if isDisconnectionError({SocketFlag.SafeDisconn},
                              events[i].errorCode):
        handleClientClosure(selector, fd)
      raiseOSError(events[i].errorCode)

    case data.fdKind
    of Server:
      if Event.Read in events[i].events:
        handleAccept()
      else:
        assert false, "Only Read events are expected for the server"
    of Dispatcher:
      # Run the dispatcher loop.
      assert events[i].events == {Event.Read}
      asyncdispatch.poll(0)
    of Client:
      if Event.Read in events[i].events:
        const size = 256
        var buf: array[size, char]
        # Read until EAGAIN. We take advantage of the fact that the client
        # will wait for a response after they send a request. So we can
        # comfortably continue reading until the message ends with \c\l
        # \c\l.
        while true:
          let ret = recv(fd.SocketHandle, addr buf[0], size, 0.cint)
          if ret == 0:
            handleClientClosure(selector, fd)

          if ret == -1:
            # Error!
            let lastError = osLastError()
            if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
              break
            if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
              handleClientClosure(selector, fd)
            raiseOSError(lastError)

          # Write buffer to our data.
          let origLen = data.data.len
          data.data.setLen(origLen + ret)
          for i in 0 ..< ret: data.data[origLen+i] = buf[i]

          if data.data.len >= 4 and fastHeadersCheck(data) or slowHeadersCheck(data):
            # First line and headers for request received.
            data.headersFinished = true
            when not defined(release):
              if data.sendQueue.len != 0:
                logging.warn("sendQueue isn't empty.")
              if data.bytesSent != 0:
                logging.warn("bytesSent isn't empty.")

            let waitingForBody = methodNeedsBody(data) and bodyInTransit(data)
            if likely(not waitingForBody):
              for start in parseRequests(data.data):
                # For pipelined requests, we need to reset this flag.
                data.headersFinished = true
                data.requestID = genRequestID()

                let request = Request(
                  selector: selector,
                  client: fd.SocketHandle,
                  start: start,
                  requestID: data.requestID,
                )

                template validateResponse(capturedData: ptr Data): untyped =
                  if capturedData.requestID == request.requestID:
                    capturedData.headersFinished = false

                if validateRequest(request):
                  data.reqFut = onRequest(request, routes, plugin)
                  if not data.reqFut.isNil:
                    capture data:
                      data.reqFut.addCallback(
                        proc (fut: Future[void]) =
                          onRequestFutureComplete(fut, selector, fd)
                          validateResponse(data)
                      )
                  else:
                    validateResponse(data)

          if ret != size:
            # Assume there is nothing else for us right now and break.
            break
      elif Event.Write in events[i].events:
        assert data.sendQueue.len > 0
        assert data.bytesSent < data.sendQueue.len
        # Write the sendQueue.
        let leftover = data.sendQueue.len-data.bytesSent
        let ret = send(fd.SocketHandle, addr data.sendQueue[data.bytesSent],
                      leftover, 0)
        if ret == -1:
          # Error!
          let lastError = osLastError()
          if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
            break
          if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
            handleClientClosure(selector, fd)
          raiseOSError(lastError)

        data.bytesSent.inc(ret)

        if data.sendQueue.len == data.bytesSent:
          data.bytesSent = 0
          data.sendQueue.setLen(0)
          data.data.setLen(0)
          selector.updateHandle(fd.SocketHandle,
                                {Event.Read})
      else:
        assert false


proc eventLoop(
  params: tuple[onRequest: OnRequest, settings: Settings, isMainThread: bool, routes:Routes, plugin:Plugin]
) =
  let (onRequest, settings, isMainThread, routes, plugin) = params

  if not isMainThread:
    # We are on a new thread. Re-add the loggers from the main thread.
    for logger in settings.loggers:
      addHandler(logger)

  let selector = newSelector[Data]()

  let server = newSocket(settings.domain)
  server.setSockOpt(OptReuseAddr, true)
  if compileOption("threads") and not settings.reusePort:
    raise HttpBeastDefect(msg: "--threads:on requires reusePort to be enabled in settings")
  server.setSockOpt(OptReusePort, settings.reusePort)
  # Windows Subsystem for Linux doesn't support this flag, the only way to know
  # is to retrieve its value it seems.
  try:
    discard server.getSockOpt(OptReusePort)
  except OSError as e:
    if e.errorCode == ENOPROTOOPT:
      echo(
        "SO_REUSEPORT not supported on this platform. HttpBeast will not utilise all threads."
      )
    else: raise

  server.bindAddr(settings.port, settings.bindAddr)
  # Disable Nagle Algorithm if the server socket is likely to be a TCP socket.
  if settings.domain in {Domain.AF_INET, Domain.AF_INET6}:
    server.setSockOpt(OptNoDelay, true, level=Protocol.IPPROTO_TCP.toInt)
  server.listen(settings.listenBacklog)
  server.getFd().setBlocking(false)
  selector.registerHandle(server.getFd(), {Event.Read}, initData(Server))

  let disp = getGlobalDispatcher()
  selector.registerHandle(getIoHandler(disp).getFd(), {Event.Read},
                          initData(Dispatcher))

  # Set up timer to get current date/time.
  discard updateDate(0.AsyncFD)
  asyncdispatch.addTimer(1000, false, updateDate)

  var events: array[64, ReadyKey]
  while true:
    let ret = selector.selectInto(-1, events)
    processEvents(selector, events, ret, onRequest, routes, plugin)

    # Ensure callbacks list doesn't grow forever in asyncdispatch.
    # See https://github.com/nim-lang/Nim/issues/7532.
    # Not processing callbacks can also lead to exceptions being silently
    # lost!
    if unlikely(asyncdispatch.getGlobalDispatcher().callbacks.len > 0):
      asyncdispatch.poll(0)


proc run*(onRequest: OnRequest, settings: Settings, routes:Routes, `createPlugin`:proc():Plugin) =
  when compileOption("threads"):
    let numThreads =
      if settings.numThreads == 0: countProcessors()
      else: settings.numThreads
  else:
    let numThreads = 1

  echo("Starting ", numThreads, " threads")
  if numThreads > 1:
    when compileOption("threads"):
      var threads = newSeq[Thread[(OnRequest, Settings, bool, Routes, Plugin)]](numThreads)
      var params:seq[(OnRequest, Settings, bool, Routes, Plugin)]
      for i in 1..numThreads:
        params.add((onRequest, settings, false, routes, `createPlugin`()))
      for i in 0..numThreads-1:
        createThread[(OnRequest, Settings, bool, Routes, Plugin)](
          threads[i], eventLoop, params[i]
        )
      joinThreads(threads)
    else:
      assert false
  echo("Listening on port ", settings.port) # This line is used in the tester to signal readiness.
  eventLoop((onRequest, settings, true, routes, `createPlugin`()))


run(cd, settings, routes, createPlugin)
