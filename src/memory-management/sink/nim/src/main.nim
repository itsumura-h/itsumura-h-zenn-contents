# nim c -r --sinkInference:on --expandArc:main -d:release src/main.nim

proc main() =
  type
    Table = object
      data: seq[int]

  proc new(_:type Table, data: seq[int]): Table =
    return Table(data: data)

  proc get(t: sink Table, index: sink int):lent int =
    return t.data[index]

  let tab = Table.new(@[1, 2, 3])
  echo tab.get(0)
  echo tab.get(1)


main()
