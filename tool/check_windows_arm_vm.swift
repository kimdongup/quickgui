// Native Windows ARM64 integration probe. `probe` boots the installer on a
// disposable empty disk; it does not select a disk or install Windows.
import Cocoa

@main
enum CheckWindowsArmVM {
  static var timers: [Timer] = []
  static func emit(_ value: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
      print(String(data: data, encoding: .utf8)!); fflush(stdout)
    }
  }
  static func fail(_ error: Error) -> Never { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
  static func main() {
    #if arch(arm64)
    var args = CommandLine.arguments
    guard args.count >= 3 else { fail(MacVMError("inspect ISO | probe ISO SCREENSHOT | lifecycle OUTPUT_LABEL")) }
    let lifecycle = args[1] == "lifecycle"
    var syntheticImage: URL?
    do {
      try WindowsVMTools.check()
      if lifecycle {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("quickgui-lease-fixture-\(UUID().uuidString).iso")
        try MacVMStore.createFile(fixture, size: 8 * 1024 * 1024)
        syntheticImage = fixture
        args.insert(fixture.path, at: 2)
        args[1] = "probe"
        emit(["syntheticMedia": true, "purpose": "QEMU and media-lock lifecycle only; no Windows installation"])
      } else {
        try WindowsVMTools.inspectISO(args[2])
        emit(["iso": args[2], "architecture": "ARM64", "windowsFiles": true])
      }
      if args[1] == "inspect" { return }
      guard args[1] == "probe", args.count >= 4 else { fail(MacVMError("probe ISO SCREENSHOT [SECONDS]")) }
      let parent = FileManager.default.temporaryDirectory.appendingPathComponent("quickgui-windows-probe-\(UUID().uuidString)")
      let bundle = parent.appendingPathComponent("Windows Probe.quickgui-winarm")
      try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      let metadata = WindowsVMMetadata(name: "Windows Probe", uuid: UUID().uuidString, mac: "02:11:22:33:44:55", cpus: 2,
                                       memoryGiB: 4, diskGiB: 64, iso: args[2])
      try JSONEncoder().encode(metadata).write(to: bundle.appendingPathComponent("vm.json"))
      try MacVMStore.createFile(bundle.appendingPathComponent("vm.lock"))
      try FileManager.default.copyItem(atPath: WindowsVMTools.firmware, toPath: bundle.appendingPathComponent("uefi-code.fd").path)
      try FileManager.default.copyItem(atPath: WindowsVMTools.variables, toPath: bundle.appendingPathComponent("uefi-vars.fd").path)
      try FileManager.default.createDirectory(at: bundle.appendingPathComponent("tpm"), withIntermediateDirectories: false)
      _ = try WindowsVMTools.run(WindowsVMTools.imageTool, ["create", "-f", "qcow2", bundle.appendingPathComponent("disk.qcow2").path, "64G"])
      let backend = WindowsArmVirtualMachine.shared
      let app = NSApplication.shared
      app.setActivationPolicy(.prohibited)
      DispatchQueue.main.async {
        backend.start(bundle.path, showWindow: false) { result in
          do {
            try result.get(); emit(try backend.status(bundle.path))
            let control = try backend.controlSocket(for: bundle.path)
            emit(["controlSocket": control])
            do {
              let lease = try MacVMFileLease(URL(fileURLWithPath: args[2]), exclusive: true)
              lease.release()
              fail(MacVMError("Running VM did not protect its installation image."))
            } catch { emit(["activeImageDeletionBlocked": true]) }
            if let networkImage = try WindowsVMTools.networkDrivers() {
              do {
                let lease = try MacVMFileLease(networkImage, exclusive: true)
                lease.release()
                fail(MacVMError("Running VM did not protect its network driver CD."))
              } catch { emit(["activeNetworkMediaDeletionBlocked": true]) }
            }
            backend.start(bundle.path, showWindow: false) { duplicate in
              if case .success = duplicate { fail(MacVMError("Duplicate start was accepted.")) }
              do {
                guard try backend.status(bundle.path)["state"] as? String == "running",
                      try WindowsQMP.command(socket: control, execute: "query-status")["running"] as? Bool == true else {
                  throw MacVMError("Rejected duplicate start disturbed the running VM.")
                }
                emit(["duplicateStartRejected": true, "originalStillRunning": true])
              } catch { fail(error) }
            }
            if !lifecycle {
            var bootKeys = 0
            timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
              bootKeys += 1
              if bootKeys > 25 { timer.invalidate(); return }
              do { _ = try WindowsQMP.command(socket: control, execute: "send-key", arguments: ["keys": [["type": "qcode", "data": "ret"]]]) }
              catch { emit(["keyError": error.localizedDescription]) }
            })
            timers.append(Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
              do { _ = try WindowsQMP.command(socket: control, execute: "screendump", arguments: ["filename": args[3] + ".early.png", "format": "png"]); emit(["earlyScreenshot": args[3] + ".early.png"]) }
              catch { emit(["captureError": error.localizedDescription]) }
            })
            }
            timers.append(Timer.scheduledTimer(withTimeInterval: lifecycle ? 3 : (args.count > 4 ? Double(args[4]) ?? 90 : 90), repeats: false) { _ in
              do {
                emit(try WindowsQMP.command(socket: control, execute: "query-status"))
                if !lifecycle {
                  _ = try WindowsQMP.command(socket: control, execute: "screendump", arguments: ["filename": args[3], "format": "png"])
                  emit(["screenshot": args[3]])
                }
                backend.stop(bundle.path, force: true) { result in
                  do {
                    try result.get()
                    timers.append(Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
                      if !backend.hasActiveVM {
                        timer.invalidate()
                        do {
                          emit(try backend.status(bundle.path))
                          let lease = try MacVMFileLease(URL(fileURLWithPath: args[2]), exclusive: true)
                          lease.release()
                          emit(["imageReleasedAfterStop": true])
                          if let networkImage = try WindowsVMTools.networkDrivers() {
                            let lease = try MacVMFileLease(networkImage, exclusive: true)
                            lease.release()
                            emit(["networkMediaReleasedAfterStop": true])
                          }
                          try FileManager.default.removeItem(at: parent)
                          if let syntheticImage = syntheticImage { try FileManager.default.removeItem(at: syntheticImage) }
                          emit(["probeRemoved": true]); exit(0)
                        } catch { fail(error) }
                      }
                    })
                  } catch { fail(error) }
                }
              } catch { fail(error) }
            })
          } catch { emit(["probeFolder": parent.path]); fail(error) }
        }
      }
      app.run()
    } catch { fail(error) }
    #else
    fail(MacVMError("Apple Silicon is required."))
    #endif
  }
}
