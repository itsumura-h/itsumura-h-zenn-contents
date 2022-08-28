import
  std/asyncdispatch,
  std/osproc,
  std/sequtils


template serve*(controllers, plugin, typPlugin:untyped):untyped =
  block:
    proc thread(param:(seq[Controller], typPlugin, int)) {.thread.} =
      let (controllers, `plugin`, nThread) = param
      (proc() {.async.} =
          await controllers[0].action(plugin, nThread)
      )().waitFor

    proc main(`controllers`:seq[Controller]) =
      when compileOption("threads"):
        let countThreads = countProcessors()
        var thr = newSeq[Thread[(seq[Controller], typPlugn, int)]](countThreads)
        for i in 0..countThreads-1:
          createThread(thr[i], thread, (controllers, plugin, i))
        joinThreads(thr)
      else:
        thread((controllers, plugin, 1))

    main(controllers)
