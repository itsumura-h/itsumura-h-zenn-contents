# nim c -r --expandArc:main src/main.nim

proc main() =
  var x = @[1,2,3]
  var y = x
  echo x
  var z = y
  echo z

main()
