import Cocoa
import Virtualization

#if arch(arm64)
@available(macOS 12.0, *)
final class AppleVirtualMachine: NSObject, VZVirtualMachineDelegate {
  static let shared = AppleVirtualMachine()
  private final class Session {
    let bundle: URL
    var metadata: MacVMMetadata
    let lock: MacVMLock
    let vm: VZVirtualMachine
    var installer: VZMacOSInstaller?
    var window: NSWindow?
    var phase: String
    var error: String?
    var imageLease: MacVMFileLease?
    init(_ bundle: URL, _ metadata: MacVMMetadata, _ lock: MacVMLock, _ vm: VZVirtualMachine, _ phase: String) {
      self.bundle = bundle; self.metadata = metadata; self.lock = lock; self.vm = vm; self.phase = phase
    }
  }
  private var session: Session?
  private var preparing = false
  var hasActiveVM: Bool { preparing || session != nil }

  static var maxCPU: Int {
    min(VZVirtualMachineConfiguration.maximumAllowedCPUCount, max(2, ProcessInfo.processInfo.activeProcessorCount - 1))
  }
  static var maxMemory: UInt64 {
    min(VZVirtualMachineConfiguration.maximumAllowedMemorySize, ProcessInfo.processInfo.physicalMemory - min(ProcessInfo.processInfo.physicalMemory, 2 * MacVMStore.gib))
  }

  func inspectImage(_ path: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
    loadImage(path) { result in
      completion(result.flatMap { image in
        do { return .success(try self.imageInfo(image)) } catch { return .failure(error) }
      })
    }
  }

  private func loadImage(_ path: String, completion: @escaping (Result<VZMacOSRestoreImage, Error>) -> Void) {
    do {
      guard VZVirtualMachine.isSupported else { throw MacVMError("Virtualization is unavailable on this Mac.") }
      let url = URL(fileURLWithPath: path).standardizedFileURL
      guard url.pathExtension.lowercased() == "ipsw" else { throw MacVMError("Select a macOS IPSW restore image.") }
      try MacVMStore.regularFile(url)
      let lease = try MacVMFileLease(url)
      VZMacOSRestoreImage.load(from: url) { result in
        DispatchQueue.main.async {
          withExtendedLifetime(lease) { completion(result) }
        }
      }
    } catch { completion(.failure(error)) }
  }

  private func imageInfo(_ image: VZMacOSRestoreImage) throws -> [String: Any] {
    guard let requirements = image.mostFeaturefulSupportedConfiguration, requirements.hardwareModel.isSupported else {
      throw MacVMError("This IPSW is not compatible with this Mac. Download a compatible image first.")
    }
    let version = image.operatingSystemVersion
    return ["version": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "build": image.buildVersion, "minimumCPU": requirements.minimumSupportedCPUCount,
            "maximumCPU": Self.maxCPU, "minimumMemoryGiB": Int((requirements.minimumSupportedMemorySize + MacVMStore.gib - 1) / MacVMStore.gib),
            "maximumMemoryGiB": Int(Self.maxMemory / MacVMStore.gib)]
  }

  func create(directory: String, name: String, ipsw: String, cpus: Int, memoryGiB: Int, diskGiB: Int,
              completion: @escaping (Result<[String: Any], Error>) -> Void) {
    guard !hasActiveVM else { completion(.failure(MacVMError("Shut down the active Apple VM before creating another one."))); return }
    let imageLease: MacVMFileLease
    do { imageLease = try MacVMFileLease(URL(fileURLWithPath: ipsw)) }
    catch { completion(.failure(error)); return }
    preparing = true
    loadImage(ipsw) { result in
      defer { self.preparing = false }
      var created: URL?
      do {
        let image = try result.get()
        let info = try self.imageInfo(image)
        let requirements = image.mostFeaturefulSupportedConfiguration!
        guard cpus >= requirements.minimumSupportedCPUCount, cpus <= Self.maxCPU,
              (2...512).contains(memoryGiB), (64...1024).contains(diskGiB) else {
          throw MacVMError("Choose supported CPU and memory values and a disk between 64 and 1024 GiB.")
        }
        let memory = UInt64(memoryGiB) * MacVMStore.gib
        guard memory >= requirements.minimumSupportedMemorySize, memory <= Self.maxMemory else {
          throw MacVMError("The memory selection must meet the IPSW minimum and leave memory for the host.")
        }
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory)
        guard let free = attributes[.systemFreeSize] as? NSNumber, free.uint64Value >= 32 * MacVMStore.gib else {
          throw MacVMError("At least 32 GiB of free host storage is required to begin installation. The virtual disk grows as it is used.")
        }
        let metadata = MacVMMetadata(name: name, version: info["version"] as! String, build: image.buildVersion,
                                     cpuCount: cpus, memoryBytes: memory, diskBytes: UInt64(diskGiB) * MacVMStore.gib,
                                     macAddress: VZMACAddress.randomLocallyAdministered().string, installation: "installing",
                                     restoreImage: URL(fileURLWithPath: ipsw).standardizedFileURL.path)
        let bundle = try MacVMStore.create(in: directory, metadata: metadata)
        created = bundle
        let lock = try MacVMLock(bundle: bundle)
        try requirements.hardwareModel.dataRepresentation.write(to: bundle.appendingPathComponent("hardware-model"), options: .withoutOverwriting)
        try VZMacMachineIdentifier().dataRepresentation.write(to: bundle.appendingPathComponent("machine-identifier"), options: .withoutOverwriting)
        _ = try VZMacAuxiliaryStorage(creatingStorageAt: bundle.appendingPathComponent("auxiliary-storage"), hardwareModel: requirements.hardwareModel, options: [])
        try MacVMStore.createFile(bundle.appendingPathComponent("disk.img"), size: metadata.diskBytes)
        let vm = try self.makeVM(bundle: bundle, metadata: metadata)
        let active = Session(bundle, metadata, lock, vm, "installing")
        active.imageLease = imageLease
        let installer = VZMacOSInstaller(virtualMachine: vm, restoringFromImageAt: image.url)
        active.installer = installer
        self.session = active
        installer.install { result in
          switch result {
          case .success:
            active.metadata.installation = "ready"
            active.metadata.error = nil
          case .failure(let error):
            active.metadata.installation = active.phase == "cancelling" ? "cancelled" : "failed"
            active.metadata.error = error.localizedDescription
          }
          do { try MacVMStore.write(active.metadata, to: bundle) }
          catch {
            // Keep the session/lock when persistence fails; never report a ready VM.
            active.phase = "error"; active.error = "Could not save installation status: \(error.localizedDescription)"
            active.installer = nil
            return
          }
          active.installer = nil
          self.releaseStoppedSession(active)
        }
        completion(.success(try self.status(bundle.path)))
      } catch {
        if let bundle = created, var metadata = try? MacVMStore.read(bundle) {
          metadata.installation = "failed"; metadata.error = error.localizedDescription
          try? MacVMStore.write(metadata, to: bundle)
        }
        completion(.failure(error))
      }
    }
  }

  private func makeVM(bundle: URL, metadata: MacVMMetadata) throws -> VZVirtualMachine {
    for name in ["hardware-model", "machine-identifier", "auxiliary-storage", "disk.img"] {
      try MacVMStore.regularFile(bundle.appendingPathComponent(name))
    }
    guard let hardware = VZMacHardwareModel(dataRepresentation: try Data(contentsOf: bundle.appendingPathComponent("hardware-model"))), hardware.isSupported,
          let identifier = VZMacMachineIdentifier(dataRepresentation: try Data(contentsOf: bundle.appendingPathComponent("machine-identifier"))),
          let address = VZMACAddress(string: metadata.macAddress) else {
      throw MacVMError("The saved VM identity is invalid or unsupported on this Mac.")
    }
    let platform = VZMacPlatformConfiguration()
    platform.hardwareModel = hardware
    platform.machineIdentifier = identifier
    platform.auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: bundle.appendingPathComponent("auxiliary-storage"))
    let config = VZVirtualMachineConfiguration()
    config.platform = platform
    config.bootLoader = VZMacOSBootLoader()
    guard metadata.cpuCount <= Self.maxCPU, metadata.memoryBytes <= Self.maxMemory else {
      throw MacVMError("This VM requires more resources than this Mac can provide.")
    }
    config.cpuCount = metadata.cpuCount
    config.memorySize = metadata.memoryBytes
    let graphics = VZMacGraphicsDeviceConfiguration()
    graphics.displays = [VZMacGraphicsDisplayConfiguration(widthInPixels: 1440, heightInPixels: 900, pixelsPerInch: 110)]
    config.graphicsDevices = [graphics]
    config.keyboards = [VZUSBKeyboardConfiguration()]
    config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
    let disk = try VZDiskImageStorageDeviceAttachment(url: bundle.appendingPathComponent("disk.img"), readOnly: false)
    config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: disk)]
    let network = VZVirtioNetworkDeviceConfiguration()
    network.macAddress = address
    network.attachment = VZNATNetworkDeviceAttachment()
    config.networkDevices = [network]
    let sound = VZVirtioSoundDeviceConfiguration()
    let output = VZVirtioSoundDeviceOutputStreamConfiguration()
    output.sink = VZHostAudioOutputStreamSink()
    sound.streams = [output]
    config.audioDevices = [sound]
    config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
    try config.validate()
    let vm = VZVirtualMachine(configuration: config)
    vm.delegate = self
    return vm
  }

  func list(_ directory: String) throws -> [[String: Any]] {
    let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: nil)
    return urls.filter { $0.pathExtension == MacVMStore.bundleExtension }.sorted { $0.path < $1.path }.map { url in
      do { return try status(url.path) }
      catch { return ["path": url.path, "name": url.deletingPathExtension().lastPathComponent, "state": "error", "error": error.localizedDescription] }
    }
  }

  func status(_ path: String) throws -> [String: Any] {
    let bundle = try MacVMStore.bundle(at: path)
    let metadata = try MacVMStore.read(bundle)
    var state = metadata.installation == "ready" ? "stopped" : metadata.installation
    var message = metadata.error
    var progress: Double?
    if let active = session, active.bundle.path == bundle.path {
      state = active.phase
      message = active.error ?? message
      progress = active.installer?.progress.fractionCompleted
    } else {
      do {
        let lock = try MacVMLock(bundle: bundle)
        withExtendedLifetime(lock) {}
        if state == "installing" {
          state = "interrupted"
          message = "Installation was interrupted. Create a new VM from the IPSW; this disk is kept for inspection."
        }
      } catch { state = "busy"; message = error.localizedDescription }
    }
    var info: [String: Any] = ["path": bundle.path, "name": metadata.name, "version": metadata.version,
                               "build": metadata.build, "state": state, "cpuCount": metadata.cpuCount,
                               "memoryGiB": metadata.memoryBytes / MacVMStore.gib, "diskGiB": metadata.diskBytes / MacVMStore.gib]
    if let message = message { info["error"] = message }
    if let progress = progress { info["progress"] = progress }
    return info
  }

  func start(_ path: String, showWindow: Bool = true, completion: @escaping (Result<Void, Error>) -> Void) {
    do {
      let bundle = try MacVMStore.bundle(at: path)
      guard !hasActiveVM else { throw MacVMError("Shut down the active Apple VM before starting another one.") }
      let lock = try MacVMLock(bundle: bundle)
      let metadata = try MacVMStore.read(bundle)
      guard metadata.installation == "ready" else { throw MacVMError("Installation has not completed. Create a new VM from the IPSW.") }
      let vm = try makeVM(bundle: bundle, metadata: metadata)
      let active = Session(bundle, metadata, lock, vm, "starting")
      session = active
      vm.start { result in
        switch result {
        case .success:
          active.phase = "running"
          if showWindow { self.show(active) }
        case .failure: self.releaseStoppedSession(active)
        }
        completion(result)
      }
    } catch { completion(.failure(error)) }
  }

  func show(_ path: String) throws {
    let active = try selectedSession(path)
    guard active.phase == "running" || active.phase == "stopping" else { throw MacVMError("Wait for the VM to start.") }
    show(active)
  }

  private func show(_ active: Session) {
    if active.window == nil {
      let view = VZVirtualMachineView(frame: NSRect(x: 0, y: 0, width: 1008, height: 630))
      view.virtualMachine = active.vm
      // System shortcuts stay with the host; ordinary keyboard/mouse events go to the guest.
      view.capturesSystemKeys = false
      if #available(macOS 14.0, *) { view.automaticallyReconfiguresDisplay = true }
      let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
      window.title = "\(active.metadata.name) — Apple Silicon"
      window.isReleasedWhenClosed = false
      window.contentView = view
      window.minSize = NSSize(width: 640, height: 400)
      window.center()
      active.window = window
    }
    active.window?.makeKeyAndOrderFront(nil)
    active.window?.makeFirstResponder(active.window?.contentView)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  private func selectedSession(_ path: String) throws -> Session {
    let bundle = try MacVMStore.bundle(at: path)
    guard let active = session, active.bundle.path == bundle.path else { throw MacVMError("This VM is not active in this Quickgui process.") }
    return active
  }

  func cancelInstall(_ path: String) throws {
    let active = try selectedSession(path)
    guard active.phase == "installing", let installer = active.installer else { throw MacVMError("No installation can be cancelled.") }
    active.phase = "cancelling"
    installer.progress.cancel()
  }

  func stop(_ path: String, force: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    do {
      let active = try selectedSession(path)
      guard active.installer == nil, ["running", "stopping", "error"].contains(active.phase) else {
        throw MacVMError("Cancel installation or wait for the current operation before stopping.")
      }
      if force {
        if active.vm.state == .stopped { releaseStoppedSession(active); completion(.success(())); return }
        guard active.vm.canStop else { throw MacVMError("The VM cannot stop yet. Try again shortly.") }
        active.phase = "stopping"
        active.vm.stop { error in
          if let error = error { active.phase = "running"; completion(.failure(error)) }
          else { self.releaseStoppedSession(active); completion(.success(())) }
        }
      } else {
        try active.vm.requestStop()
        active.phase = "stopping"
        completion(.success(()))
      }
    } catch { completion(.failure(error)) }
  }

  private func releaseStoppedSession(_ active: Session) {
    guard session === active else { return }
    guard active.vm.state == .stopped else {
      active.phase = "error"
      active.error = "The VM has not stopped. Use Force stop before closing Quickgui."
      return
    }
    (active.window?.contentView as? VZVirtualMachineView)?.virtualMachine = nil
    active.window?.close()
    active.imageLease?.release()
    active.lock.release()
    session = nil
  }

  func guestDidStop(_ virtualMachine: VZVirtualMachine) {
    if let active = session, active.vm === virtualMachine, active.installer == nil { releaseStoppedSession(active) }
  }
  func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
    guard let active = session, active.vm === virtualMachine, active.installer == nil else { return }
    active.metadata.error = error.localizedDescription
    try? MacVMStore.write(active.metadata, to: active.bundle)
    releaseStoppedSession(active)
  }
}
#endif
