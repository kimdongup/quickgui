// Uses the exact native backend compiled into Quickgui. No Quickemu subprocesses.
// Compile with MacVMStore.swift + AppleVirtualMachine.swift, then sign with the
// Runner virtualization entitlement. `install` creates a NEW 64 GiB sparse disk.
import Cocoa

@main
enum CheckAppleVM {
  static var timer: Timer?
  static func emit(_ value: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print(text); fflush(stdout) }
  }
  static func fail(_ error: Error) -> Never {
    fputs("\(error.localizedDescription)\n", stderr); exit(1)
  }
  static func main() {
    #if arch(arm64)
    if #available(macOS 12.0, *) {
      let args = CommandLine.arguments
      let backend = AppleVirtualMachine.shared
      guard args.count >= 3 else { fail(MacVMError("inspect IPSW | install WORKSPACE NAME IPSW | boot BUNDLE SECONDS [SCREENSHOT] | status BUNDLE")) }
      let app = NSApplication.shared
      app.setActivationPolicy(.regular)
      DispatchQueue.main.async {
        switch args[1] {
        case "inspect": backend.inspectImage(args[2]) { result in
          do { emit(try result.get()); exit(0) } catch { fail(error) }
        }
        case "status":
          do { emit(try backend.status(args[2])); exit(0) } catch { fail(error) }
        case "install":
          guard args.count == 5 else { fail(MacVMError("install WORKSPACE NAME IPSW")) }
          backend.create(directory: args[2], name: args[3], ipsw: args[4], cpus: 2, memoryGiB: 4, diskGiB: 64) { result in
            do {
              let created = try result.get(); emit(created)
              let path = created["path"] as! String
              timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
                do {
                  let status = try backend.status(path); emit(status)
                  if status["state"] as? String == "stopped" { exit(0) }
                  if ["failed", "cancelled", "error", "interrupted"].contains(status["state"] as? String ?? "") { exit(1) }
                } catch { fail(error) }
              }
            } catch { fail(error) }
          }
        case "boot":
          guard args.count >= 4, let seconds = Double(args[3]), seconds >= 30 else { fail(MacVMError("boot BUNDLE SECONDS [SCREENSHOT]")) }
          backend.start(args[2]) { result in
            do {
              try result.get(); emit(try backend.status(args[2]))
              // A second start must be refused while retaining the first VM.
              backend.start(args[2], showWindow: false) { duplicate in
                if case .success = duplicate { fail(MacVMError("Duplicate start unexpectedly succeeded.")) }
                emit(["duplicateStartRefused": true])
              }
              let display = app.windows.first(where: { $0.title.hasSuffix("— Apple Silicon") })
              display?.close()
              try backend.show(args[2])
              emit(["displayReopened": display?.isVisible == true])
              timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
                do {
                  emit(try backend.status(args[2]))
                  if args.count > 4, let view = app.windows.first(where: { $0.title.hasSuffix("— Apple Silicon") })?.contentView,
                     let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: URL(fileURLWithPath: args[4])); emit(["screenshot": args[4]]) }
                  }
                  // Validation VM has no user work. Force-stop is explicit in this
                  // probe, unlike the app's default graceful shutdown action.
                  backend.stop(args[2], force: true) { result in
                    do { try result.get(); emit(try backend.status(args[2])); exit(0) } catch { fail(error) }
                  }
                } catch { fail(error) }
              }
            } catch { fail(error) }
          }
        default: fail(MacVMError("Unknown operation."))
        }
      }
      app.run()
      return
    }
    #endif
    fail(MacVMError("An Apple Silicon Mac with macOS 12 or later is required."))
  }
}
