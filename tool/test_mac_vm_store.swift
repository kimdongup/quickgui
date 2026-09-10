// Standalone native regression tests. Does not boot or install a VM.
import Foundation

@main
enum TestMacVMStore {
  static var count = 0
  static func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
    guard condition() else { throw MacVMError("FAIL: \(label)") }
    count += 1; print("PASS: \(label)")
  }
  static func rejects(_ label: String, _ action: () throws -> Void) throws {
    do { try action() } catch { count += 1; print("PASS: \(label)"); return }
    throw MacVMError("FAIL: \(label)")
  }
  static func main() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("quickgui-store-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temp) }
    let metadata = MacVMMetadata(name: "My Mac", version: "26.6.2", build: "25G83", cpuCount: 2,
                                 memoryBytes: 4 * MacVMStore.gib, diskBytes: 64 * MacVMStore.gib,
                                 macAddress: "02:00:00:00:00:01", installation: "installing")
    for name in ["", ".", "..", "../Other VM", "a/b", "a:b", "a\\b", "a\n", " leading"] {
      try rejects("unsafe name \(name.debugDescription)") { try MacVMStore.validateName(name) }
    }
    let bundle = try MacVMStore.create(in: temp.path, metadata: metadata)
    let original = try Data(contentsOf: bundle.appendingPathComponent("vm.json"))
    try rejects("existing VM cannot be replaced") { _ = try MacVMStore.create(in: temp.path, metadata: metadata) }
    let after = try Data(contentsOf: bundle.appendingPathComponent("vm.json"))
    try check(original == after, "existing VM metadata preserved")
    let empty = temp.appendingPathComponent("Empty.quickgui-macvm")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: false)
    let emptyMetadata = MacVMMetadata(name: "Empty", version: "test", build: "test", cpuCount: 2,
                                     memoryBytes: 4 * MacVMStore.gib, diskBytes: 64 * MacVMStore.gib,
                                     macAddress: metadata.macAddress, installation: "installing")
    try rejects("existing empty directory cannot be reused") { _ = try MacVMStore.create(in: temp.path, metadata: emptyMetadata) }
    var lock: MacVMLock? = try MacVMLock(bundle: bundle)
    try withExtendedLifetime(lock) {
      try rejects("second writer is locked out") { _ = try MacVMLock(bundle: bundle) }
    }
    lock = nil
    let reopened = try MacVMLock(bundle: bundle)
    reopened.release()
    try check(true, "lock can be acquired after previous owner exits")
    let afterRelease = try MacVMLock(bundle: bundle)
    afterRelease.release()
    try check(true, "explicit stop releases lock before callback returns")
    let disk = bundle.appendingPathComponent("disk.img")
    try MacVMStore.createFile(disk, size: metadata.diskBytes)
    let attributes = try FileManager.default.attributesOfItem(atPath: disk.path)
    try check((attributes[.size] as? NSNumber)?.uint64Value == 64 * MacVMStore.gib, "sparse disk has correct virtual capacity")
    try rejects("existing disk cannot be resized") { try MacVMStore.createFile(disk, size: 0) }
    let link = temp.appendingPathComponent("disk-link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: disk)
    try rejects("symbolic link storage refused") { try MacVMStore.regularFile(link) }
    let hardLink = temp.appendingPathComponent("disk-hard-link")
    try FileManager.default.linkItem(at: disk, to: hardLink)
    try rejects("shared hard-linked disk refused") { try MacVMStore.regularFile(disk) }
    let bundleLink = temp.appendingPathComponent("alias.quickgui-macvm")
    try FileManager.default.createSymbolicLink(at: bundleLink, withDestinationURL: bundle)
    try rejects("symbolic link bundle refused") { _ = try MacVMStore.bundle(at: bundleLink.path) }
    var ready = metadata
    ready.installation = "ready"
    try MacVMStore.write(ready, to: bundle)
    let read = try MacVMStore.read(bundle)
    try check(read.installation == "ready" && read.macAddress == metadata.macAddress && read.diskBytes == metadata.diskBytes,
              "completion preserves resources and network identity across reload")
    var invalid = metadata
    invalid.schema = 999
    try MacVMStore.write(invalid, to: bundle)
    try rejects("unknown schema cannot run") { _ = try MacVMStore.read(bundle) }
    print("\(count) native store checks passed")
  }
}
