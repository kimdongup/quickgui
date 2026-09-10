import FlutterMacOS
import Foundation

final class NativeStorageChannel {
  private let channel: FlutterMethodChannel
  static private(set) var hasActiveOperation = false
  static private(set) var hasActiveDeletion = false
  init(messenger: FlutterBinaryMessenger) {
    let queue = DispatchQueue(label: "quickgui.storage", qos: .userInitiated)
    channel = FlutterMethodChannel(name: "quickgui/native-storage", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, reply in
      let args = call.arguments as? [String: Any] ?? [:]
      func string(_ key: String) throws -> String {
        guard let value = args[key] as? String, !value.isEmpty else { throw MacVMError("Missing \(key).") }
        return value
      }
      do {
        let store = NativeStorageStore.shared
        let protected = ["preview", "delete"].contains(call.method)
        if protected {
          guard !Self.hasActiveOperation else { throw MacVMError("Wait for the current storage operation.") }
          guard !AppleVMChannel.hasActiveVM && !WindowsVMChannel.hasActiveVM else {
            throw MacVMError("Stop active ARM VMs and finish or cancel installation before deleting storage.")
          }
        }
        let operation: () throws -> Any?
        switch call.method {
        case "listMedia":
          let directory = try string("directory")
          operation = { try store.listMedia(workspace: directory) }
        case "addMedia":
          let path = try string("path")
          operation = { try store.rememberMedia(path); return nil }
        case "preview":
          let path = try string("path"), directory = try string("directory")
          operation = { try store.preview(path: path, workspace: directory, isVM: args["isVM"] as? Bool ?? false) }
        case "delete":
          let path = try string("path"), directory = try string("directory"), token = try string("token")
          operation = {
            try store.delete(path: path, workspace: directory, isVM: args["isVM"] as? Bool ?? false, token: token)
            return nil
          }
        default: reply(FlutterMethodNotImplemented); return
        }
        if protected { Self.hasActiveOperation = true }
        if call.method == "delete" { Self.hasActiveDeletion = true }
        queue.async {
          let result = Result<Any?, Error>(catching: operation)
          DispatchQueue.main.async {
            if protected { Self.hasActiveOperation = false }
            if call.method == "delete" { Self.hasActiveDeletion = false }
            switch result {
            case .success(let value): reply(value)
            case .failure(let error): reply(FlutterError(code: "native_storage", message: error.localizedDescription, details: nil))
            }
          }
        }
      } catch { reply(FlutterError(code: "native_storage", message: error.localizedDescription, details: nil)) }
    }
  }
}
