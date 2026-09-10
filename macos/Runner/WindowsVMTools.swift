import Foundation
import Darwin
import CryptoKit

enum WindowsVMTools {
  static let qemu = "/opt/homebrew/bin/qemu-system-aarch64"
  static let imageTool = "/opt/homebrew/bin/qemu-img"
  static let tpm = "/opt/homebrew/bin/swtpm"
  static let firmwareDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Quickgui/Firmware/utm-b44153a4")
  static var firmware: String { firmwareDirectory.appendingPathComponent("uefi-code.fd").path }
  static var variables: String { firmwareDirectory.appendingPathComponent("uefi-vars.fd").path }

  static func check(needsFirmware: Bool = true) throws {
    for path in [qemu, imageTool, tpm] {
      guard FileManager.default.isExecutableFile(atPath: path) else {
        throw MacVMError("Install ARM Homebrew QEMU and swtpm before creating a Windows ARM64 VM. Missing: \(path)")
      }
    }
    if needsFirmware {
      let expected = [firmware: "c85a57de1ac39e550a6529bd66a4214eb1d8c14dcda7e22dedf72566a769fbc7",
                      variables: "8203a22c79a52ec6c34320e58bae8a63b890a76bf62167b2e7551e88b974dc77"]
      for (path, hash) in expected {
        guard FileManager.default.isReadableFile(atPath: path) else {
          throw MacVMError("Prepare Windows ARM64 Secure Boot firmware first. Run tool/prepare_windows_arm_firmware.py from the Quickgui source folder. See docs/maintenance/WINDOWS_ARM_VM.ko.md.")
        }
        try MacVMStore.regularFile(URL(fileURLWithPath: path))
        let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        guard data.count == 64 * 1024 * 1024, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash else {
          throw MacVMError("The Windows ARM firmware does not match the verified installation. Restore it with the firmware preparation tool.")
        }
      }
    }
  }

  /// Bounded helper execution; output goes to a file so full pipes cannot deadlock.
  static func run(_ executable: String, _ arguments: [String], timeout: Double = 30) throws -> Data {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("quickgui-command-\(UUID().uuidString)")
    try MacVMStore.createFile(url)
    defer { try? FileManager.default.removeItem(at: url) }
    let output = try FileHandle(forWritingTo: url)
    defer { try? output.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output; process.standardError = output
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    if finished.wait(timeout: .now() + timeout) == .timedOut {
      process.terminate()
      if finished.wait(timeout: .now() + 3) == .timedOut { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
      throw MacVMError("\(URL(fileURLWithPath: executable).lastPathComponent) timed out.")
    }
    let input = try FileHandle(forReadingFrom: url)
    defer { try? input.close() }
    let data = try input.read(upToCount: 64 * 1024) ?? Data()
    guard process.terminationStatus == 0 else {
      throw MacVMError(String(data: data, encoding: .utf8) ?? "The VM tool failed.")
    }
    return data
  }

  static func inspectISO(_ path: String) throws {
    let iso = URL(fileURLWithPath: path).standardizedFileURL
    guard iso.pathExtension.lowercased() == "iso" else { throw MacVMError("Choose a Windows ARM64 ISO file.") }
    try MacVMStore.regularFile(iso)
    let mount = FileManager.default.temporaryDirectory.appendingPathComponent("quickgui-iso-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    // Never recursively remove a mount point, even if detach fails.
    defer { rmdir(mount.path) }
    _ = try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, iso.path])
    // Detach only our private mount point. The user's existing mounts are untouched.
    defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path]) }
    func child(_ parent: URL, _ name: String) throws -> URL {
      guard let found = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).first(where: { $0.lastPathComponent.lowercased() == name }) else {
        throw MacVMError("The image is not a Windows ARM64 installation ISO (missing \(name)).")
      }
      return found
    }
    let boot = try child(child(child(mount, "efi"), "boot"), "bootaa64.efi")
    let source = try child(mount, "sources")
    _ = try child(source, "boot.wim")
    let files = try FileManager.default.contentsOfDirectory(atPath: source.path).map { $0.lowercased() }
    guard files.contains("install.wim") || files.contains("install.esd") else { throw MacVMError("The ISO does not contain Windows installation files.") }
    let file = try FileHandle(forReadingFrom: boot)
    defer { try? file.close() }
    let data = try file.read(upToCount: 4096) ?? Data()
    guard data.count >= 64, data[0] == 0x4d, data[1] == 0x5a else { throw MacVMError("Invalid ARM64 EFI boot file.") }
    let offset = (0..<4).reduce(0) { $0 | Int(data[60 + $1]) << ($1 * 8) }
    guard offset <= data.count - 6, Array(data[offset..<offset+4]) == [0x50, 0x45, 0, 0],
          data[offset+4] == 0x64, data[offset+5] == 0xaa else {
      throw MacVMError("The ISO boot program is not ARM64. Choose the Microsoft ARM64 image.")
    }
  }

  static func block(_ name: String, _ filename: String, format: String, readOnly: Bool = false) throws -> String {
    let object: [String: Any] = ["node-name": name, "driver": format, "read-only": readOnly,
                                "file": ["driver": "file", "filename": filename]]
    return String(data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!
  }

  static func arguments(bundle: URL, runtime: URL, uuid: String, mac: String, cpus: Int, memoryGiB: Int, iso: String?, showWindow: Bool = true) throws -> [String] {
    // This firmware needs a PCI display for discovery and a linear RAM
    // framebuffer for Windows boot. RAMFB stays console 0 for the Cocoa window.
    var args = ["-name", "Windows ARM64", "-uuid", uuid, "-machine", "virt-9.2,highmem=on,gic-version=3", "-accel", "hvf", "-cpu", "host",
                "-smp", "\(cpus)", "-m", "\(memoryGiB * 1024)", "-nodefaults", "-serial", "stdio", "-display", showWindow ? "cocoa" : "none", "-device", "ramfb", "-device", "virtio-gpu-pci",
                "-device", "qemu-xhci,id=usb,p2=8,p3=8", "-device", "usb-kbd,bus=usb.0", "-device", "usb-tablet,bus=usb.0",
                "-blockdev", try block("code", bundle.appendingPathComponent("uefi-code.fd").path, format: "raw", readOnly: true),
                "-blockdev", try block("vars", bundle.appendingPathComponent("uefi-vars.fd").path, format: "raw"),
                "-machine", "pflash0=code,pflash1=vars",
                "-blockdev", try block("disk", bundle.appendingPathComponent("disk.qcow2").path, format: "qcow2"),
                "-device", "nvme,drive=disk,serial=\(uuid.replacingOccurrences(of: "-", with: "").prefix(20)),bootindex=2",
                "-netdev", "user,id=net0", "-device", "usb-net,netdev=net0,mac=\(mac),bus=usb.0",
                "-chardev", "socket,id=chrtpm,path=\(runtime.appendingPathComponent("tpm.sock").path)",
                "-tpmdev", "emulator,id=tpm0,chardev=chrtpm", "-device", "tpm-tis-device,tpmdev=tpm0",
                "-qmp", "unix:\(runtime.appendingPathComponent("qmp.sock").path),server=on,wait=off"]
    if let iso = iso {
      // Windows Setup must see optical media, not an unpartitioned USB disk.
      args += ["-blockdev", try block("cd", iso, format: "raw", readOnly: true),
               "-device", "usb-bot,id=cdusb,bus=usb.0",
               "-device", "scsi-cd,drive=cd,bus=cdusb.0,bootindex=1"]
    }
    return args
  }
}

/// Each control connection has a private Unix socket and a bounded lifetime.
enum WindowsQMP {
  static func command(socket path: String, execute: String, arguments: [String: Any]? = nil) throws -> [String: Any] {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw MacVMError("Cannot open VM control socket.") }
    defer { close(fd) }
    var timeout = timeval(tv_sec: 3, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var enabled: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw MacVMError("VM control path is too long.") }
    withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes) }
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0 else { throw MacVMError("VM control is not ready.") }
    var pending = Data()
    func read() throws -> [String: Any] {
      while true {
        if let end = pending.firstIndex(of: 10) {
          let line = pending.prefix(upTo: end)
          pending.removeSubrange(...end)
          guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw MacVMError("Invalid VM control reply.") }
          return object
        }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = recv(fd, &buffer, buffer.count, 0)
        guard count > 0, pending.count < 1024 * 1024 else { throw MacVMError("VM control timed out or disconnected.") }
        pending.append(contentsOf: buffer.prefix(count))
      }
    }
    func request(_ name: String, _ id: Int, _ arguments: [String: Any]? = nil) throws -> [String: Any] {
      var object: [String: Any] = ["execute": name, "id": id]
      if let arguments = arguments { object["arguments"] = arguments }
      var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
      try data.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
          let count = send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
          guard count > 0 else { throw MacVMError("Cannot send VM control request.") }
          offset += count
        }
      }
      for _ in 0..<100 {
        let reply = try read()
        if reply["id"] as? Int == id {
          if let error = reply["error"] { throw MacVMError("VM control error: \(error)") }
          return reply["return"] as? [String: Any] ?? [:]
        }
      }
      throw MacVMError("No reply to VM control request.")
    }
    guard try read()["QMP"] != nil else { throw MacVMError("Unexpected VM control greeting.") }
    _ = try request("qmp_capabilities", 0)
    return try request(execute, 1, arguments)
  }
}
