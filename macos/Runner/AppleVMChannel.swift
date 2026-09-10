import Cocoa
import FlutterMacOS
import Virtualization

final class AppleVMChannel {
  private let channel: FlutterMethodChannel
  static var hasActiveVM: Bool {
    #if arch(arm64)
    if #available(macOS 12.0, *) { return AppleVirtualMachine.shared.hasActiveVM }
    #endif
    return false
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "quickgui/apple-vm", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, reply in
      func fail(_ error: Error) {
        reply(FlutterError(code: "apple_vm", message: error.localizedDescription, details: nil))
      }
      #if arch(arm64)
      if #available(macOS 12.0, *) {
        let backend = AppleVirtualMachine.shared
        let args = call.arguments as? [String: Any] ?? [:]
        func string(_ key: String) throws -> String {
          guard let value = args[key] as? String, !value.isEmpty else { throw MacVMError("Missing \(key).") }
          return value
        }
        func number(_ key: String) throws -> Int {
          guard let value = args[key] as? Int else { throw MacVMError("Missing \(key).") }
          return value
        }
        func done(_ result: Result<Void, Error>) {
          switch result { case .success: reply(nil); case .failure(let error): fail(error) }
        }
        func map(_ result: Result<[String: Any], Error>) {
          switch result { case .success(let value): reply(value); case .failure(let error): fail(error) }
        }
        do {
          if ["create", "start"].contains(call.method) && WindowsVMChannel.hasActiveVM {
            throw MacVMError("Shut down the Windows ARM VM before starting an Apple VM.")
          }
          switch call.method {
          case "supported": reply(VZVirtualMachine.isSupported)
          case "inspectImage": backend.inspectImage(try string("path"), completion: map)
          case "create":
            backend.create(directory: try string("directory"), name: try string("name"), ipsw: try string("image"),
                           cpus: try number("cpus"), memoryGiB: try number("memoryGiB"), diskGiB: try number("diskGiB"), completion: map)
          case "list": reply(try backend.list(string("directory")))
          case "status": reply(try backend.status(string("path")))
          case "start": backend.start(try string("path"), completion: done)
          case "show": try backend.show(string("path")); reply(nil)
          case "cancelInstall": try backend.cancelInstall(string("path")); reply(nil)
          case "stop": backend.stop(try string("path"), force: args["force"] as? Bool ?? false, completion: done)
          default: reply(FlutterMethodNotImplemented)
          }
        } catch { fail(error) }
        return
      }
      #endif
      if call.method == "supported" { reply(false) }
      else { fail(MacVMError("Apple VM installation requires an Apple Silicon Mac with macOS 12 or later.")) }
    }
  }
}
