import
  std/asyncdispatch,
  std/asynchttpserver,
  std/osproc,
  ./fw/lib,
  ./setting,
  ./controller


let routes = @[
  (Route(path:"/", httpMethod:HttpGet), Controller.new(index)),
  (Route(path:"/show", httpMethod:HttpGet), Controller.new(show))
]

proc createPlugin*():Plugin =
  return Plugin.new()

serveWithPlugin(routes, createPlugin)

# proc threadProc(params:(seq[(Route, Controller)], Plugin, int)) {.thread.} =
#   proc asyncProc(params:(seq[(Route, Controller)], Plugin, int)) {.async.} =
#     var server = newAsyncHttpServer(true, true)
#     proc cb(req: Request) {.async, gcsafe.} =
#       let headers = {"Content-type": "text/plain; charset=utf-8"}
#       let (routes, plugin, nThreads) = params
#       var hasRoute = false
#       for route in routes:
#         if req.url.path == route[0].path and req.reqMethod == route[0].httpMethod:
#           let resp = route[1].action(plugin).await
#           await req.respond(Http200, resp, headers.newHttpHeaders())
#           hasRoute = true
#           break
#       if not hasRoute:
#         await req.respond(Http404, "", headers.newHttpHeaders())

#     server.listen(Port(5000))
#     while true:
#       if server.shouldAcceptRequest():
#         await server.acceptRequest(cb)
#       else:
#         await sleepAsync(500)

#   while true:
#     try:
#       asyncProc(params).waitFor
#       runForever()
#     except:
#       echo repr(getCurrentException())

# proc serve(routes:seq[(Route, Controller)], `createPlugin`:proc():Plugin) =
#   when compileOption("threads"):
#     let countThreads = countProcessors()
#     var params:seq[(seq[(Route, Controller)], Plugin, int)]
#     for i in 1..countThreads:
#       params.add((routes, `createPlugin`(), i-1))
#     echo("Starting ", countThreads, " threads")
#     var thr = newSeq[Thread[(seq[(Route, Controller)], Plugin, int)]](countThreads)
#     for i in 0..countThreads-1:
#       createThread(thr[i], threadProc, params[i])
#     joinThreads(thr)
#   else:
#     echo("Starting ", 1, " thread")
#     threadProc((routes, `createPlugin`(), 1))

# serve(routes, createPlugin)
