import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !AppleVMChannel.hasActiveVM
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if AppleVMChannel.hasActiveVM {
      let alert = NSAlert()
      alert.messageText = "An Apple Silicon VM is active"
      alert.informativeText = "Return to Manager to cancel installation or shut down the VM before quitting Quickgui. Closing the VM display keeps the VM running."
      alert.addButton(withTitle: "Return to Quickgui")
      alert.runModal()
      return .terminateCancel
    }
    return super.applicationShouldTerminate(sender)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
