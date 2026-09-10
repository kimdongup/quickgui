import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var restoreImageChannel: FlutterMethodChannel?
  private var appleVMChannel: AppleVMChannel?
  private var windowsVMChannel: WindowsVMChannel?
  private var nativeStorageChannel: NativeStorageChannel?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    appleVMChannel = AppleVMChannel(messenger: flutterViewController.engine.binaryMessenger)
    windowsVMChannel = WindowsVMChannel(messenger: flutterViewController.engine.binaryMessenger)
    nativeStorageChannel = NativeStorageChannel(messenger: flutterViewController.engine.binaryMessenger)

    restoreImageChannel = FlutterMethodChannel(
      name: "quickgui/restore-image", binaryMessenger: flutterViewController.engine.binaryMessenger)
    restoreImageChannel?.setMethodCallHandler { call, reply in
      guard call.method == "latestSupported" else {
        reply(FlutterMethodNotImplemented)
        return
      }
      RestoreImageSource.latest { result in
        DispatchQueue.main.async {
          switch result {
          case .success(let image): reply(image)
          case .failure(let error):
            reply(FlutterError(code: "restore_image_unavailable", message: error.localizedDescription, details: nil))
          }
        }
      }
    }

    super.awakeFromNib()
  }
}
