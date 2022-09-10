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

serveWithoutPlugin(routes)
