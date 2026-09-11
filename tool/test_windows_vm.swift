// Windows ARM64 configuration and lifecycle safeguards; no guest is launched.
import Foundation
import CryptoKit

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
    try check(completed.sshPort == nil, "legacy metadata needs no migration")
    try backend.configureSSH(bundle.path, port: 50222)
    let configured = try backend.status(bundle.path)
    try check(configured["savedSshPort"] as? Int == 50222 && configured["sshPort"] == nil,
              "saved port survives metadata reload but stopped VM exposes no live endpoint")
    try rejects("privileged port rejected") { try backend.configureSSH(bundle.path, port: 22) }
    try rejects("overflow port rejected") { try backend.configureSSH(bundle.path, port: 65536) }
    let portLock = try MacVMLock(bundle: bundle)
    try rejects("port change refused under another writer") { try backend.configureSSH(bundle.path, port: 50223) }
    portLock.release()
    try JSONEncoder().encode([ProcessInfo.processInfo.processIdentifier]).write(to: owner)
    try rejects("port change refused for orphaned running VM") { try backend.configureSSH(bundle.path, port: 50223) }
    try FileManager.default.removeItem(at: owner)
    let forwarded = try WindowsVMTools.arguments(bundle: bundle, runtime: URL(fileURLWithPath: "/tmp/qg-test"), uuid: metadata.uuid, mac: metadata.mac, cpus: 2, memoryGiB: 4, iso: nil, sshPort: 50222)
    try check(forwarded.contains("user,id=net0,hostfwd=tcp:127.0.0.1:50222-:22"), "SSH binds loopback only and targets guest 22")
    try rejects("invalid direct QEMU port rejected") {
      _ = try WindowsVMTools.arguments(bundle: bundle, runtime: URL(fileURLWithPath: "/tmp/qg-test"), uuid: metadata.uuid, mac: metadata.mac, cpus: 2, memoryGiB: 4, iso: nil, sshPort: -1)
    }
    try backend.configureConnections(bundle.path, port: 50222, spiceEnabled: true)
    try backend.configureSSH(bundle.path, port: 50223)
    let spiceConfig = try backend.status(bundle.path)
    try check(spiceConfig["spiceRequested"] as? Bool == true && spiceConfig["savedSshPort"] as? Int == 50223,
              "SSH-only changes preserve the persisted SPICE choice")
    try check(spiceConfig["spiceSocket"] == nil && spiceConfig["displayMode"] as? String == "cocoa",
              "stopped VM never exposes a stale SPICE endpoint")
    let spiceArgs = try WindowsVMTools.arguments(bundle: bundle, runtime: URL(fileURLWithPath: "/tmp/qg-test"), uuid: metadata.uuid,
      mac: metadata.mac, cpus: 2, memoryGiB: 4, iso: nil, sshPort: 50223, spiceSocket: URL(fileURLWithPath: "/tmp/private space,한글/spice.sock"))
    try check(spiceArgs.contains("unix=on,addr=/tmp/private space,,한글/spice.sock,disable-ticketing=on,display=windows-display") && spiceArgs.contains("cocoa"),
              "SPICE preserves literal paths and Cocoa while using a local Unix socket")
    try check(spiceArgs.contains("ramfb,id=windows-display") && spiceArgs.contains("virtio-gpu-pci") && spiceArgs.contains("tpm-tis-device,tpmdev=tpm0"),
              "SPICE leaves existing framebuffer, PCI GPU and TPM unchanged")
    try rejects("overlong SPICE socket refused before launch") {
      _ = try WindowsVMTools.arguments(bundle: bundle, runtime: URL(fileURLWithPath: "/tmp/qg-test"), uuid: metadata.uuid,
        mac: metadata.mac, cpus: 2, memoryGiB: 4, iso: nil, spiceSocket: URL(fileURLWithPath: "/tmp/" + String(repeating: "x", count: 110)))
    }
    let install = try WindowsVMTools.arguments(bundle: bundle, runtime: URL(fileURLWithPath: "/tmp/qg-test"), uuid: metadata.uuid, mac: metadata.mac, cpus: 2, memoryGiB: 4, iso: metadata.iso)
    let boot = try WindowsVMTools.arguments(bundle: bundle, runtime: URL(fileURLWithPath: "/tmp/qg-test"), uuid: metadata.uuid, mac: metadata.mac, cpus: 2, memoryGiB: 4, iso: nil)
    try check(install.contains("hvf") && install.contains("host") && install.contains("virt-9.2,highmem=on,gic-version=3"), "native ARM hardware acceleration selected")
    try check(!install.joined(separator: " ").contains("invtsc") && !install.joined(separator: " ").contains("qxl") && !install.joined(separator: " ").contains("ICH9"), "x64-only CPU and device options excluded")
    try check(install.contains("tpm-tis-device,tpmdev=tpm0") && install.contains("ramfb,id=windows-display") && install.contains("virtio-gpu-pci") && install.firstIndex(of: "ramfb,id=windows-display")! < install.firstIndex(of: "virtio-gpu-pci")! && install.contains(where: { $0.hasPrefix("nvme,") }), "TPM2, primary linear framebuffer plus PCI display, and inbox storage configured")
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
    try check(install.contains("user,id=net0") && install.contains("virtio-net-pci,netdev=net0,mac=\(metadata.mac)") && !install.contains(where: { $0.hasPrefix("usb-net,") }),
              "ARM64 VirtIO NIC uses NAT and preserves the saved MAC")
    let networkPath = "/Driver Media/네트워크, ARM64.iso"
    let networkBoot = try WindowsVMTools.arguments(bundle: bundle, runtime: URL(fileURLWithPath: "/tmp/qg-test"), uuid: metadata.uuid, mac: metadata.mac, cpus: 2, memoryGiB: 4, iso: nil, networkISO: networkPath)
    let networkBlocks = try networkBoot.enumerated().filter { $0.element == "-blockdev" }.map { index, _ -> [String: Any] in
      try JSONSerialization.jsonObject(with: Data(networkBoot[index+1].utf8)) as! [String: Any]
    }
    let networkCD = networkBlocks.first { $0["node-name"] as? String == "netdrivers" }!
    try check(networkCD["read-only"] as? Bool == true && (networkCD["file"] as? [String: Any])?["filename"] as? String == networkPath && networkBoot.contains("scsi-cd,drive=netdrivers,bus=netdriverusb.0"),
              "network-only CD stays read-only and available after installer removal")
    let drivers = parent.appendingPathComponent("drivers")
    let missingDrivers = try WindowsVMTools.networkDrivers(in: drivers)
    try check(missingDrivers == nil, "installed guests can start without optional driver media")
    try FileManager.default.createDirectory(at: drivers, withIntermediateDirectories: false)
    let image = drivers.appendingPathComponent("network-drivers.iso")
    let bytes = Data("fixture".utf8)
    try bytes.write(to: image)
    let manifest: [String: Any] = ["schema": 1, "sourceSHA256": "65b6a69b392ee01dd314c10f3dad9ebbf9c4160be43f5f0dd6bb715944d9095b",
                                   "imageSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()]
    try JSONSerialization.data(withJSONObject: manifest).write(to: drivers.appendingPathComponent("network.json"))
    let verifiedDrivers = try WindowsVMTools.networkDrivers(in: drivers)
    try check(verifiedDrivers?.path == image.path, "prepared driver media hash verified")
    try Data("changed".utf8).write(to: image)
    try rejects("changed driver CD refused") { _ = try WindowsVMTools.networkDrivers(in: drivers) }
    try FileManager.default.removeItem(at: image)
    try FileManager.default.createSymbolicLink(at: image, withDestinationURL: file)
    try rejects("driver CD symlink refused") { _ = try WindowsVMTools.networkDrivers(in: drivers) }
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
