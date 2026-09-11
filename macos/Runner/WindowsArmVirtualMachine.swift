import Cocoa

#if arch(arm64)
struct WindowsVMMetadata: Codable {
  var schema = 1
  let name: String
  let uuid: String
  let mac: String
  let cpus: Int
  let memoryGiB: Int
  let diskGiB: Int
  let iso: String
  var installationPending = true
  var sshPort: Int?
  var error: String?
}

final class WindowsArmVirtualMachine {
  static let shared = WindowsArmVirtualMachine()
  static let bundleExtension = "quickgui-winarm"
  private final class Session {
    let bundle: URL
    let runtime: URL
    let lock: MacVMLock
    let log: FileHandle
    var sshPort: Int?
    let qemu = Process()
    let tpm = Process()
    var phase = "starting"
    var imageLease: MacVMFileLease?
    var networkImageLease: MacVMFileLease?
    init(_ bundle: URL, _ runtime: URL, _ lock: MacVMLock, _ log: FileHandle) {
      self.bundle = bundle; self.runtime = runtime; self.lock = lock; self.log = log
    }
  }
  private var session: Session?
  private var preparing = false
  var hasActiveVM: Bool { preparing || session != nil }
  static var maxCPU: Int { min(8, max(2, ProcessInfo.processInfo.activeProcessorCount - 1)) }
  static var maxMemory: Int { max(0, Int(ProcessInfo.processInfo.physicalMemory / MacVMStore.gib) - 2) }

  func inspectImage(_ path: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Result<[String: Any], Error> {
        try WindowsVMTools.check()
        guard try WindowsVMTools.networkDrivers() != nil else {
          throw MacVMError("Prepare Windows ARM64 network drivers first: run tool/prepare_windows_arm_network.py from the Quickgui source folder. See docs/maintenance/WINDOWS_ARM_VM.ko.md.")
        }
        try WindowsVMTools.inspectISO(path)
        return ["version": "11 ARM64", "build": "Microsoft ISO", "minimumCPU": 2, "maximumCPU": Self.maxCPU,
                "minimumMemoryGiB": 4, "maximumMemoryGiB": Self.maxMemory]
      }
      DispatchQueue.main.async { completion(result) }
    }
  }

  private func bundle(_ path: String) throws -> URL { try MacVMStore.bundle(at: path, extensionName: Self.bundleExtension) }
  private func read(_ bundle: URL) throws -> WindowsVMMetadata {
    let file = bundle.appendingPathComponent("vm.json")
    try MacVMStore.regularFile(file)
    let data = try Data(contentsOf: file)
    guard data.count < 64 * 1024 else { throw MacVMError("Invalid VM metadata.") }
    let value = try JSONDecoder().decode(WindowsVMMetadata.self, from: data)
    try MacVMStore.validateName(value.name)
    guard value.schema == 1, UUID(uuidString: value.uuid) != nil,
          value.mac.range(of: "^([0-9a-f]{2}:){5}[0-9a-f]{2}$", options: .regularExpression) != nil,
          (2...8).contains(value.cpus), (4...512).contains(value.memoryGiB), (64...1024).contains(value.diskGiB) else {
      throw MacVMError("Unsupported Windows ARM VM metadata.")
    }
    if let port = value.sshPort, !(1024...65535).contains(port) { throw MacVMError("Invalid SSH port.") }
    return value
  }
  private func write(_ metadata: WindowsVMMetadata, _ bundle: URL) throws {
    let file = bundle.appendingPathComponent("vm.json")
    if FileManager.default.fileExists(atPath: file.path) { try MacVMStore.regularFile(file) }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(metadata).write(to: file, options: .atomic)
  }

  /// A crashed app may leave QEMU running. Refuse to touch the bundle while any
  /// recorded owner PID exists; never signal a process found through a stale PID.
  private func hasOtherOwner(_ bundle: URL) throws -> Bool {
    let file = bundle.appendingPathComponent("owner.json")
    guard FileManager.default.fileExists(atPath: file.path) else { return false }
    try MacVMStore.regularFile(file)
    let pids = try JSONDecoder().decode([Int32].self, from: Data(contentsOf: file))
    return pids.contains { $0 > 1 && (kill($0, 0) == 0 || errno == EPERM) }
  }

  func create(directory: String, name: String, iso: String, cpus: Int, memoryGiB: Int, diskGiB: Int,
              completion: @escaping (Result<[String: Any], Error>) -> Void) {
    guard !hasActiveVM else { completion(.failure(MacVMError("Shut down the active Windows ARM VM first."))); return }
    preparing = true
    inspectImage(iso) { result in
      var created: URL?
      do {
        _ = try result.get()
        try MacVMStore.validateName(name)
        guard (2...Self.maxCPU).contains(cpus), memoryGiB >= 4, memoryGiB <= Self.maxMemory, (64...1024).contains(diskGiB) else {
          throw MacVMError("Select at least 2 CPU cores, 4 GiB memory and a 64 GiB disk, leaving memory for this Mac.")
        }
        let free = try FileManager.default.attributesOfFileSystem(forPath: directory)[.systemFreeSize] as? NSNumber
        guard (free?.uint64Value ?? 0) >= 32 * MacVMStore.gib else {
          throw MacVMError("At least 32 GiB of free host storage is required for a new Windows installation. Choose another workspace or free space first.")
        }
        let parent = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath()
        let target = parent.appendingPathComponent(name).appendingPathExtension(Self.bundleExtension)
        guard mkdir(target.path, 0o700) == 0 else { throw MacVMError("Choose a new VM name and a writable folder. Existing folders are never overwritten.") }
        created = target
        let random = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let mac = "02:" + stride(from: 0, to: 10, by: 2).map { index -> String in
          let start = random.index(random.startIndex, offsetBy: index)
          return String(random[start..<random.index(start, offsetBy: 2)])
        }.joined(separator: ":")
        let metadata = WindowsVMMetadata(name: name, uuid: UUID().uuidString, mac: mac, cpus: cpus, memoryGiB: memoryGiB,
                                         diskGiB: diskGiB, iso: URL(fileURLWithPath: iso).standardizedFileURL.path)
        try MacVMStore.createFile(target.appendingPathComponent("vm.lock"))
        let creationLock = try MacVMLock(bundle: target)
        defer { creationLock.release() }
        try self.write(metadata, target)
        try FileManager.default.copyItem(atPath: WindowsVMTools.firmware, toPath: target.appendingPathComponent("uefi-code.fd").path)
        try FileManager.default.copyItem(atPath: WindowsVMTools.variables, toPath: target.appendingPathComponent("uefi-vars.fd").path)
        for name in ["firmware.json", "COPYRIGHT"] {
          try FileManager.default.copyItem(at: WindowsVMTools.firmwareDirectory.appendingPathComponent(name), to: target.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: target.appendingPathComponent("tpm"), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        _ = try WindowsVMTools.run(WindowsVMTools.imageTool, ["create", "-f", "qcow2", target.appendingPathComponent("disk.qcow2").path, "\(diskGiB)G"])
        creationLock.release()
        self.preparing = false
        self.start(target.path) { result in
          do { try result.get(); completion(.success(try self.status(target.path))) }
          catch { completion(.failure(error)) }
        }
      } catch {
        self.preparing = false
        if let target = created, var metadata = try? self.read(target) {
          metadata.error = error.localizedDescription; try? self.write(metadata, target)
        }
        completion(.failure(error))
      }
    }
  }

  func list(_ directory: String) throws -> [[String: Any]] {
    let files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: nil)
    return files.filter { $0.pathExtension == Self.bundleExtension }.sorted { $0.path < $1.path }.map { file in
      do { return try status(file.path) }
      catch { return ["path": file.path, "name": file.deletingPathExtension().lastPathComponent, "state": "error", "error": error.localizedDescription] }
    }
  }

  func status(_ path: String) throws -> [String: Any] {
    let target = try bundle(path), metadata = try read(target)
    var state = "stopped", message = metadata.error
    if let active = session, active.bundle.path == target.path { state = active.phase }
    else {
      do {
        let lock = try MacVMLock(bundle: target)
        defer { lock.release() }
        if try hasOtherOwner(target) { state = "busy"; message = "A previous Quickgui process left this VM active. Close its QEMU window before starting it again." }
      } catch { state = "busy"; message = error.localizedDescription }
    }
    var result: [String: Any] = ["path": target.path, "name": metadata.name, "state": state, "version": "11 ARM64",
                                 "installationPending": metadata.installationPending]
    if let port = metadata.sshPort { result["savedSshPort"] = port }
    if let active = session, active.bundle.path == target.path, active.phase == "running", active.qemu.isRunning,
       let port = active.sshPort { result["sshHost"] = "127.0.0.1"; result["sshPort"] = port }
    if let message = message { result["error"] = message }
    return result
  }

  func start(_ path: String, showWindow: Bool = true, completion: @escaping (Result<Void, Error>) -> Void) {
    // A rejected second start must never clean up the already running session.
    guard !hasActiveVM else {
      completion(.failure(MacVMError("Shut down the active Windows ARM VM first."))); return
    }
    do {
      try WindowsVMTools.check(needsFirmware: false)
      let target = try bundle(path), lock = try MacVMLock(bundle: target)
      guard try !hasOtherOwner(target) else { throw MacVMError("This VM is still owned by another process.") }
      var metadata = try read(target)
      guard metadata.cpus <= Self.maxCPU, metadata.memoryGiB <= Self.maxMemory else { throw MacVMError("This Mac cannot provide the saved VM resources.") }
      for name in ["disk.qcow2", "uefi-code.fd", "uefi-vars.fd"] { try MacVMStore.regularFile(target.appendingPathComponent(name)) }
      let tpmValues = try target.appendingPathComponent("tpm").resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard tpmValues.isDirectory == true, tpmValues.isSymbolicLink != true else { throw MacVMError("Invalid TPM state directory.") }
      if metadata.installationPending {
        try MacVMStore.regularFile(URL(fileURLWithPath: metadata.iso))
      }
      let networkISO = try WindowsVMTools.networkDrivers()
      let runtime = URL(fileURLWithPath: "/tmp/qg-win-\(UUID().uuidString.prefix(12))")
      guard mkdir(runtime.path, 0o700) == 0 else { throw MacVMError("Cannot create VM control directory.") }
      let logURL = target.appendingPathComponent("last-run.log")
      if FileManager.default.fileExists(atPath: logURL.path) { try MacVMStore.regularFile(logURL) }
      else { try MacVMStore.createFile(logURL) }
      let log = try FileHandle(forWritingTo: logURL)
      try log.truncate(atOffset: 0)
      let active = Session(target, runtime, lock, log)
      if metadata.installationPending { active.imageLease = try MacVMFileLease(URL(fileURLWithPath: metadata.iso)) }
      if let networkISO = networkISO { active.networkImageLease = try MacVMFileLease(networkISO) }
      session = active
      if metadata.sshPort == nil { metadata.sshPort = try WindowsVMTools.availableSSHPort() }
      active.sshPort = metadata.sshPort
      metadata.error = nil; try write(metadata, target)
      active.tpm.executableURL = URL(fileURLWithPath: WindowsVMTools.tpm)
      active.tpm.currentDirectoryURL = target
      active.tpm.arguments = ["socket", "--tpm2", "--tpmstate", "dir=tpm", "--ctrl", "type=unixio,path=\(runtime.appendingPathComponent("tpm.sock").path)", "--terminate"]
      active.tpm.standardOutput = log; active.tpm.standardError = log
      active.qemu.executableURL = URL(fileURLWithPath: WindowsVMTools.qemu)
      active.qemu.currentDirectoryURL = target
      active.qemu.arguments = try WindowsVMTools.arguments(bundle: target, runtime: runtime, uuid: metadata.uuid, mac: metadata.mac,
                                                          cpus: metadata.cpus, memoryGiB: metadata.memoryGiB, iso: metadata.installationPending ? metadata.iso : nil,
                                                          networkISO: networkISO?.path, showWindow: showWindow, sshPort: active.sshPort)
      active.qemu.standardInput = FileHandle.nullDevice
      active.qemu.standardOutput = log; active.qemu.standardError = log
      active.qemu.terminationHandler = { process in
        DispatchQueue.main.async {
          if process.terminationStatus != 0, var current = try? self.read(target) {
            current.error = "QEMU exited with status \(process.terminationStatus). See last-run.log in the VM folder."
            try? self.write(current, target)
          }
          self.cleanup(active)
        }
      }
      try active.tpm.run()
      try writeOwner(active)
      waitForTPM(active, until: Date().addingTimeInterval(10), completion: completion)
    } catch {
      if let active = session { cleanup(active) }
      completion(.failure(error))
    }
  }

  private func writeOwner(_ active: Session) throws {
    let file = active.bundle.appendingPathComponent("owner.json")
    if FileManager.default.fileExists(atPath: file.path) { try MacVMStore.regularFile(file) }
    let pids = [active.qemu, active.tpm].filter { $0.isRunning }.map { $0.processIdentifier }
    try JSONEncoder().encode(pids).write(to: file, options: .atomic)
  }

  private func waitForTPM(_ active: Session, until deadline: Date, completion: @escaping (Result<Void, Error>) -> Void) {
    guard session === active, active.tpm.isRunning, Date() < deadline else {
      cleanup(active); completion(.failure(MacVMError("TPM failed to start. See last-run.log in the VM folder."))); return
    }
    if !FileManager.default.fileExists(atPath: active.runtime.appendingPathComponent("tpm.sock").path) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.waitForTPM(active, until: deadline, completion: completion) }
      return
    }
    do {
      try active.qemu.run(); try writeOwner(active)
      waitForQEMU(active, until: Date().addingTimeInterval(15), completion: completion)
    } catch { cleanup(active); completion(.failure(error)) }
  }

  private func waitForQEMU(_ active: Session, until deadline: Date, completion: @escaping (Result<Void, Error>) -> Void) {
    guard session === active, active.qemu.isRunning, Date() < deadline else {
      cleanup(active); completion(.failure(MacVMError("Windows ARM VM failed to start. See last-run.log in the VM folder."))); return
    }
    DispatchQueue.global().async {
      let status = try? WindowsQMP.command(socket: active.runtime.appendingPathComponent("qmp.sock").path, execute: "query-status")
      DispatchQueue.main.async {
        if status?["running"] as? Bool == true, self.session === active {
          active.phase = "running"; completion(.success(()))
        } else {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.waitForQEMU(active, until: deadline, completion: completion) }
        }
      }
    }
  }

  func show(_ path: String) throws {
    let active = try selected(path)
    guard let app = NSRunningApplication(processIdentifier: active.qemu.processIdentifier) else { throw MacVMError("The QEMU display is unavailable.") }
    app.activate(options: [.activateAllWindows])
  }
  // Used by the native integration probe; not exported on the Flutter channel.
  func controlSocket(for path: String) throws -> String {
    try selected(path).runtime.appendingPathComponent("qmp.sock").path
  }
  private func selected(_ path: String) throws -> Session {
    let target = try bundle(path)
    guard let active = session, active.bundle.path == target.path else { throw MacVMError("This VM is not active in this Quickgui process.") }
    return active
  }
  func stop(_ path: String, force: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    do {
      let active = try selected(path)
      guard active.qemu.isRunning else { throw MacVMError("Wait for VM startup to finish.") }
      DispatchQueue.global().async {
        let result = Result<Void, Error> {
          _ = try WindowsQMP.command(socket: active.runtime.appendingPathComponent("qmp.sock").path, execute: force ? "quit" : "system_powerdown")
        }
        DispatchQueue.main.async {
          if case .success = result, self.session === active { active.phase = "stopping" }
          completion(result)
        }
      }
    } catch { completion(.failure(error)) }
  }
  /// Connections are configured only while stopped, under the same VM lock as start.
  func configureSSH(_ path: String, port: Int) throws {
    guard (1024...65535).contains(port) else { throw MacVMError("SSH port must be between 1024 and 65535.") }
    let target = try bundle(path)
    guard session?.bundle.path != target.path else { throw MacVMError("Shut down the guest before changing its SSH port.") }
    let lock = try MacVMLock(bundle: target)
    defer { lock.release() }
    guard try !hasOtherOwner(target) else { throw MacVMError("The VM is still running.") }
    var metadata = try read(target)
    metadata.sshPort = port
    try write(metadata, target)
  }

  func completeInstallation(_ path: String) throws {
    let target = try bundle(path)
    guard session?.bundle.path != target.path else { throw MacVMError("Shut down the guest before confirming installation.") }
    let lock = try MacVMLock(bundle: target)
    defer { lock.release() }
    guard try !hasOtherOwner(target) else { throw MacVMError("The VM is still running.") }
    var metadata = try read(target)
    guard metadata.installationPending else { throw MacVMError("Installation is already marked complete.") }
    metadata.installationPending = false
    try write(metadata, target)
  }

  private func cleanup(_ active: Session) {
    guard session === active else { return }
    active.phase = "stopping"
    // Only signal Process objects we launched, never PIDs from metadata.
    if active.qemu.isRunning { active.qemu.terminate() }
    if active.tpm.isRunning { active.tpm.terminate() }
    DispatchQueue.global().async {
      let deadline = Date().addingTimeInterval(5)
      while (active.qemu.isRunning || active.tpm.isRunning) && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
      for process in [active.qemu, active.tpm] where process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
      DispatchQueue.main.async {
        guard self.session === active else { return }
        try? active.log.close()
        active.imageLease?.release()
        active.networkImageLease?.release()
        try? FileManager.default.removeItem(at: active.bundle.appendingPathComponent("owner.json"))
        try? FileManager.default.removeItem(at: active.runtime)
        active.lock.release()
        self.session = nil
      }
    }
  }
}
#endif
