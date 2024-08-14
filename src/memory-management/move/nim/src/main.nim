# nim c -r --expandArc:main src/main.nim

proc main() =
  var someNumbers = @[1, 2]
  let other = someNumbers
  someNumbers.add(3)
  echo other
  echo someNumbers

main()
