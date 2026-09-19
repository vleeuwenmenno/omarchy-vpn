import QtQuick
import QtTest
import "../.." as Plugin

TestCase {
  name: "ConcurrentNetworkManager"
  Component { id: factory; Plugin.NetworkManagerBackend {} }
  property var backend

  function init() {
    backend = createTemporaryObject(factory, this)
    verify(backend !== null)
    backend._nmcliPresent = true
    backend._wireguardPresent = true
    backend.profiles = [
      { name: "cloud", uuid: "cloud", kind: "wireguard", active: true },
      { name: "work-dev", uuid: "dev", kind: "wireguard", active: true },
      { name: "work-prod", uuid: "prod", kind: "wireguard", active: false }
    ]
  }

  function actionProcess() {
    for (var i = 0; i < backend.children.length; i++) {
      var child = backend.children[i]
      if (child.running === true && child.command && child.command[0] === "nmcli"
          && child.command[1] === "connection") return child
    }
    fail("No connection command started")
    return null
  }

  function test_connect_preserves_other_profiles() {
    backend.connectTo(backend.targets[2])
    compare(actionProcess().command, ["nmcli", "connection", "up", "uuid", "prod"])
    compare(backend.connected, true)
    compare(backend.summary, "cloud + work-dev")
  }

  function test_disconnect_one_leaves_other_connected() {
    backend.disconnectTarget(backend.targets[1])
    compare(actionProcess().command, ["nmcli", "connection", "down", "uuid", "dev"])
    backend.applyProfiles([
      { name: "cloud", uuid: "cloud", kind: "wireguard", active: true },
      { name: "work-dev", uuid: "dev", kind: "wireguard", active: false }
    ])
    compare(backend.connected, true)
    compare(backend.summary, "cloud")
  }

  function test_disconnect_all_names_only_active_profiles() {
    backend.disconnect()
    compare(actionProcess().command, ["nmcli", "connection", "down", "uuid", "cloud", "uuid", "dev"])
  }

  function test_failed_connect_keeps_other_status() {
    backend.connectTo(backend.targets[2])
    var process = actionProcess()
    process.stderr.text = "Activation failed"
    process.running = false
    process.exited(1, 0)
    compare(backend.connected, true)
    compare(backend.summary, "cloud + work-dev")
    verify(backend.lastError.indexOf("Activation failed") !== -1)
  }
}
