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
