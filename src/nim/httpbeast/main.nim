import 
  std/asyncdispatch,
  ./setting,
  ./controller
include ./fw/lib


let routes = @[
  (Route(path:"/", httpMethod:HttpGet), Controller.new(index)),
  (Route(path:"/show", httpMethod:HttpGet), Controller.new(show))
]

proc createPlugin*():Plugin =
  return Plugin.new()

let settings = initSettings(port=Port(5000), bindAddr="0.0.0.0")


proc threadProc(params:(seq[(Route, Controller)], Plugin, Settings, bool)) {.thread.} =
  let (routes, plugin, settings, isMainThread) = params
  proc asyncProc(req: Request):Future[void] {.async, gcsafe.} =
    let headers = {"Content-type": "text/plain; charset=utf-8"}
    var hasRoute = false
    for route in routes:
      if req.path.get == route[0].path and req.httpMethod.get == route[0].httpMethod:
        let resp = route[1].action(plugin).await
        req.send(Http200, resp, $headers.newHttpHeaders())
        hasRoute = true
        break
    if not hasRoute:
      req.send(Http404, "", $headers.newHttpHeaders())

  runWithSettings(settings, asyncProc)


proc serve(routes:seq[(Route, Controller)], createPlugin:proc():Plugin, settings=initSettings()) =
  when compileOption("threads"):
    let numThreads =
      if settings.numThreads == 0: countProcessors()
      else: settings.numThreads
  else:
    let numThreads = 1

  echo("Starting ", numThreads, " threads")
  if numThreads > 1:
    when compileOption("threads"):
      var threads = newSeq[Thread[(seq[(Route, Controller)], Plugin, Settings, bool)]](numThreads - 1)
      var params:seq[(seq[(Route, Controller)], Plugin, Settings, bool)]
      for t in threads.mitems():
        createThread[(seq[(Route, Controller)], Plugin, Settings, bool)](
          t, threadProc, (routes, createPlugin(), settings, false)
        )
    else:
      assert false
  echo("Listening on port ", settings.port) # This line is used in the tester to signal readiness.
  threadProc((routes, createPlugin(), settings, true))

serve(routes, createPlugin, settings)
