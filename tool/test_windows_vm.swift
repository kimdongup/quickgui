// Windows ARM64 configuration and lifecycle safeguards; no guest is launched.
import Foundation

@main
enum TestWindowsVM {
  static var count = 0
  static func check(_ passed: @autoclosure () -> Bool, _ name: String) throws {
    guard passed() else { throw MacVMError("FAIL: \(name)") }
    count += 1; print("PASS: \(name)")
  }
  static func rejects(_ name: String, _ action: () throws -> Void) throws {
    do { try action() } catch { count += 1; print("PASS: \(name)"); return }
    throw MacVMError("FAIL: \(name)")
  }
  static func main() throws {
    #if arch(arm64)
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent("quickgui-windows-tests-\(UUID().uuidString)")
    let bundle = parent.appendingPathComponent("Windows, ARM test.quickgui-winarm")
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    var metadata = WindowsVMMetadata(name: "Windows, ARM test", uuid: UUID().uuidString, mac: "02:11:22:33:44:55", cpus: 2, memoryGiB: 4, diskGiB: 64, iso: "/Install Media/Windows, 한국어.iso")
    let file = bundle.appendingPathComponent("vm.json")
    try JSONEncoder().encode(metadata).write(to: file)
    try MacVMStore.createFile(bundle.appendingPathComponent("vm.lock"))
    let backend = WindowsArmVirtualMachine.shared
    let initial = try backend.status(bundle.path)
    try check(initial["installationPending"] as? Bool == true && initial["state"] as? String == "stopped", "incomplete Windows installation is identifiable")
    let owner = bundle.appendingPathComponent("owner.json")
    try JSONEncoder().encode([ProcessInfo.processInfo.processIdentifier]).write(to: owner)
    let owned = try backend.status(bundle.path)
    try check(owned["state"] as? String == "busy", "owner remaining after app exit blocks reuse")
    try rejects("completion refused while recorded process exists") { try backend.completeInstallation(bundle.path) }
    try FileManager.default.removeItem(at: owner)
    let lock = try MacVMLock(bundle: bundle)
    try rejects("completion refused while another writer holds lock") { try backend.completeInstallation(bundle.path) }
    lock.release()
    try backend.completeInstallation(bundle.path)
    let completed = try JSONDecoder().decode(WindowsVMMetadata.self, from: Data(contentsOf: file))
    try check(!completed.installationPending && completed.uuid == metadata.uuid && completed.mac == metadata.mac && completed.iso == metadata.iso, "completion keeps identities and image reference")
    try rejects("completion is not silently repeated") { try backend.completeInstallation(bundle.path) }
    let install = try WindowsVMTools.arguments(bundle: bundle, runtime: URL(fileURLWithPath: "/tmp/qg-test"), uuid: metadata.uuid, mac: metadata.mac, cpus: 2, memoryGiB: 4, iso: metadata.iso)
    let boot = try WindowsVMTools.arguments(bundle: bundle, runtime: URL(fileURLWithPath: "/tmp/qg-test"), uuid: metadata.uuid, mac: metadata.mac, cpus: 2, memoryGiB: 4, iso: nil)
    try check(install.contains("hvf") && install.contains("host") && install.contains("virt-9.2,highmem=on,gic-version=3"), "native ARM hardware acceleration selected")
    try check(!install.joined(separator: " ").contains("invtsc") && !install.joined(separator: " ").contains("qxl") && !install.joined(separator: " ").contains("ICH9"), "x64-only CPU and device options excluded")
    try check(install.contains("tpm-tis-device,tpmdev=tpm0") && install.contains("ramfb") && install.contains("virtio-gpu-pci") && install.firstIndex(of: "ramfb")! < install.firstIndex(of: "virtio-gpu-pci")! && install.contains(where: { $0.hasPrefix("nvme,") }), "TPM2, primary linear framebuffer plus PCI display, and inbox storage configured")
    let blocks = try install.enumerated().filter { $0.element == "-blockdev" }.map { index, _ -> [String: Any] in
      try JSONSerialization.jsonObject(with: Data(install[index+1].utf8)) as! [String: Any]
    }
    let disk = blocks.first { $0["node-name"] as? String == "disk" }!
    try check((disk["file"] as? [String: Any])?["filename"] as? String == bundle.appendingPathComponent("disk.qcow2").path, "disk path keeps literal commas")
    let cd = blocks.first { $0["node-name"] as? String == "cd" }!
    try check(cd["read-only"] as? Bool == true && (cd["file"] as? [String: Any])?["filename"] as? String == metadata.iso,
              "ISO is read-only and keeps literal commas and Unicode")
    try check(install.contains("scsi-cd,drive=cd,bus=cdusb.0,bootindex=1") && install.contains("usb-bot,id=cdusb,bus=usb.0"),
              "installer is an explicit optical device, never a RAW USB disk")
    try check(!boot.contains(where: { $0.contains("scsi-cd") || $0.contains("cdusb") }), "completed boot does not attach the installer")
    metadata.schema = 99
    try JSONEncoder().encode(metadata).write(to: file)
    try rejects("unknown schema refused") { _ = try backend.status(bundle.path) }
    let list = try backend.list(parent.path)
    try check(list.first?["state"] as? String == "error", "invalid VM is listed with error instead of hidden")
    let alias = parent.appendingPathComponent("Alias.quickgui-winarm")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: bundle)
    try rejects("symbolic bundle alias refused") { _ = try backend.status(alias.path) }
    print("\(count) Windows native checks passed")
    #endif
  }
}
