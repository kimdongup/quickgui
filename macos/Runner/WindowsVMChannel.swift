import FlutterMacOS

final class WindowsVMChannel {
  private let channel: FlutterMethodChannel
  static var hasActiveVM: Bool {
    #if arch(arm64)
    return WindowsArmVirtualMachine.shared.hasActiveVM
    #else
    return false
    #endif
  }
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "quickgui/windows-arm-vm", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, reply in
      func fail(_ error: Error) { reply(FlutterError(code: "windows_arm_vm", message: error.localizedDescription, details: nil)) }
      #if arch(arm64)
      let backend = WindowsArmVirtualMachine.shared
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
        if ["create", "start"].contains(call.method) && NativeStorageChannel.hasActiveOperation {
          throw MacVMError("Wait for the storage operation before starting a VM.")
        }
        if ["create", "start"].contains(call.method) && AppleVMChannel.hasActiveVM {
          throw MacVMError("Shut down the Apple VM before starting a Windows ARM VM.")
        }
        switch call.method {
        case "supported": reply(true)
        case "inspectImage":
          let path = try string("path")
          backend.inspectImage(path) { result in
            if case .success = result { try? NativeStorageStore.shared.rememberMedia(path) }
            map(result)
          }
        case "create":
          try NativeStorageStore.shared.rememberWorkspace(string("directory"))
          backend.create(directory: try string("directory"), name: try string("name"), iso: try string("image"),
                         cpus: try number("cpus"), memoryGiB: try number("memoryGiB"), diskGiB: try number("diskGiB"), completion: map)
        case "list":
          try NativeStorageStore.shared.rememberWorkspace(string("directory"))
          reply(try backend.list(string("directory")))
        case "status": reply(try backend.status(string("path")))
        case "start": backend.start(try string("path"), completion: done)
        case "show": try backend.show(string("path")); reply(nil)
        case "stop": backend.stop(try string("path"), force: args["force"] as? Bool ?? false, completion: done)
        case "completeInstallation": try backend.completeInstallation(string("path")); reply(nil)
        default: reply(FlutterMethodNotImplemented)
        }
      } catch { fail(error) }
      #else
      if call.method == "supported" { reply(false) }
      else { fail(MacVMError("Windows ARM64 VM creation requires an Apple Silicon Mac.")) }
      #endif
    }
  }
}
