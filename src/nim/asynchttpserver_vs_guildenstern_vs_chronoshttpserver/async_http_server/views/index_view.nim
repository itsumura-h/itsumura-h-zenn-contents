#? stdtmpl(toString="toString") | standard
#import std/asyncdispatch
#import ../fw/lib_view
#proc indexView*(str:string): Future[Component] {.async.} =
# result = Component.new()
<!DOCTYPE html>
  <body>
    <p>${str}</p>
  </body>
</html>
