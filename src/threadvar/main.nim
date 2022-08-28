import 
  ./fw/lib,
  ./environment,
  ./controller

var controllers:seq[Controller]
for action in @[controller1, controller2]:
  controllers.add(
    Controller(action:action)
  )

let plugin = Plugin.new()

serve(controllers, plugin, Plugin)
