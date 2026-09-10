import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !AppleVMChannel.hasActiveVM && !WindowsVMChannel.hasActiveVM
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if AppleVMChannel.hasActiveVM || WindowsVMChannel.hasActiveVM {
      let alert = NSAlert()
      alert.messageText = "An ARM virtual machine is active"
      alert.informativeText = "Return to Manager to cancel macOS installation or shut down the VM before quitting Quickgui."
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
