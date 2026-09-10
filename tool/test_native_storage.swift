import Foundation

@main
enum TestNativeStorage {
  static var count = 0
  static func check(_ value: @autoclosure () throws -> Bool, _ label: String) throws {
    guard try value() else { throw MacVMError("FAIL: \(label)") }
    count += 1; print("PASS: \(label)")
  }
  static func rejects(_ label: String, _ action: () throws -> Void) throws {
    do { try action() } catch { count += 1; print("PASS: \(label)"); return }
    throw MacVMError("FAIL: \(label)")
  }
  static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("quickgui-delete-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let suite = "quickgui.delete.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = NativeStorageStore(preferences: defaults)
    func file(_ name: String, _ data: String = "fixture") throws -> URL {
      let url = root.appendingPathComponent(name)
      try Data(data.utf8).write(to: url, options: .withoutOverwriting)
      return url
    }
    func vm(_ name: String, windows: Bool = false, iso: URL? = nil) throws -> URL {
      let url = root.appendingPathComponent(name).appendingPathExtension(windows ? "quickgui-winarm" : "quickgui-macvm")
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
      try MacVMStore.createFile(url.appendingPathComponent("vm.lock"))
      try MacVMStore.createFile(url.appendingPathComponent("disk.img"), size: 64 * 1024 * 1024)
      let value: [String: Any] = windows
        ? ["schema": 1, "installationPending": true, "iso": iso!.path]
        : ["schema": 1, "installation": "ready"]
      try JSONSerialization.data(withJSONObject: value).write(to: url.appendingPathComponent("vm.json"))
      return url
    }
    func preview(_ url: URL, vm: Bool = false) throws -> String {
      try store.preview(path: url.path, workspace: root.path, isVM: vm)["token"] as! String
    }
    func delete(_ url: URL, vm: Bool = false, token: String) throws {
      try store.delete(path: url.path, workspace: root.path, isVM: vm, token: token)
    }
    let original = try file("Original, 한글.ipsw")
    let selected = try vm("My Mac")
    let previewData = try store.preview(path: selected.path, workspace: root.path, isVM: true)
    try check((previewData["bytes"] as! UInt64) < 64 * 1024 * 1024, "preview reports allocated sparse size")
    let lock = try MacVMLock(bundle: selected)
    try rejects("locked VM cannot be deleted after confirmation") {
      try delete(selected, vm: true, token: previewData["token"] as! String)
    }
    lock.release()
    try delete(selected, vm: true, token: previewData["token"] as! String)
    try check(!FileManager.default.fileExists(atPath: selected.path), "confirmed native VM and its disk are removed")
    try check(FileManager.default.fileExists(atPath: original.path), "VM deletion keeps installation media outside the bundle")

    let stale = try file("changed.iso")
    let staleToken = try preview(stale)
    try Data("changed bytes".utf8).write(to: stale)
    try rejects("changed media invalidates confirmation") { try delete(stale, token: staleToken) }
    try check(try String(contentsOf: stale, encoding: .utf8) == "changed bytes", "changed media is preserved")
    let lease = try MacVMFileLease(original)
    try rejects("active image reader prevents deletion") { _ = try preview(original) }
    lease.release()
    try delete(stale, token: preview(stale))
    try check(!FileManager.default.fileExists(atPath: stale.path), "confirmed ISO removal succeeds")
    try rejects("a repeated delete does not affect another file") { try delete(stale, token: staleToken) }

    let linked = root.appendingPathComponent("alias.ipsw")
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: original)
    try rejects("symbolic media cannot be deleted through its alias") { _ = try preview(linked) }
    let hard = root.appendingPathComponent("hard.ipsw")
    try FileManager.default.linkItem(at: original, to: hard)
    try rejects("shared hard-linked media is protected") { _ = try preview(original) }
    try FileManager.default.removeItem(at: hard)
    let partial = try file("download.iso.part")
    try rejects("partial downloads are not deletion candidates") { _ = try preview(partial) }

    let windows = try vm("Windows", windows: true, iso: original)
    try rejects("pending Windows installation protects its image") { _ = try preview(original) }
    let owner = windows.appendingPathComponent("owner.json")
    try JSONEncoder().encode([ProcessInfo.processInfo.processIdentifier]).write(to: owner)
    try rejects("orphan VM owner PID blocks VM deletion") { _ = try preview(windows, vm: true) }
    try FileManager.default.removeItem(at: owner)
    try JSONSerialization.data(withJSONObject: ["schema": 1, "installationPending": false, "iso": original.path]).write(to: windows.appendingPathComponent("vm.json"))
    _ = try preview(original)
    try check(true, "completed Windows VM no longer needs installation ISO")
    try delete(windows, vm: true, token: preview(windows, vm: true))

    let protected = try vm("Protected")
    let originalToken = try preview(original)
    let config = try file("shared.conf", "guest_os=\"linux\"\ndisk_img=\"\(protected.path)/disk.img\"\n")
    try rejects("Quickemu reference to a native disk protects its VM") { _ = try preview(protected, vm: true) }
    try Data("iso=\"\(original.path)\"\n".utf8).write(to: config)
    try rejects("Quickemu ISO reference protects media") { _ = try preview(original) }
    try Data("guest_os=\"linux\"\ndisk_img=\"unrelated/disk.qcow2\"\nexport iso=\"\(original.path)\"\n".utf8).write(to: config)
    try rejects("exported Quickemu ISO reference protects media") { _ = try preview(original) }
    try rejects("a newly exported reference blocks deletion after preview") { try delete(original, token: originalToken) }
    try check(try String(contentsOf: original, encoding: .utf8) == "fixture", "blocked deletion preserves referenced media bytes")
    for prefix in ["export --", "export -n", "declare", "declare -x", "declare -r", "declare -gx --", "typeset -x", "readonly"] {
      try Data("\(prefix) iso='\(original.path)' # installation media\n".utf8).write(to: config)
      try rejects("\(prefix) storage reference protects media") { _ = try preview(original) }
    }
    try Data("declare -r disk_img='\(protected.path)/disk.img'\n".utf8).write(to: config)
    try rejects("declared Quickemu disk reference protects its VM") { _ = try preview(protected, vm: true) }

    let marker = root.appendingPathComponent("must-not-be-executed")
    let included = try file("included.sh", "iso='\(original.path)'\ntouch '\(marker.path)'\n")
    let ambiguous: [(String, String)] = [
      ("source includes", "source '\(included.path)'"),
      ("dot includes", ". '\(included.path)'"),
      ("declaration namerefs", "declare -n alias=iso\nalias='\(original.path)'"),
      ("declaration transformations", "declare -u iso='\(original.path)'"),
      ("multiple declaration assignments", "declare -x label=example iso='\(original.path)'"),
      ("additional assignments", "label=example iso='\(original.path)'"),
      ("inline commands", "label=example; iso='\(original.path)'"),
      ("commands after quoted semicolons", "label='example; value'; iso='\(original.path)'"),
      ("command substitutions in unrelated values", "label=\"$(touch '\(marker.path)')\""),
      ("backtick substitutions", "label=\"`touch '\(marker.path)'`\""),
      ("eval", "eval \"iso='\(original.path)'\""),
      ("whitespace before equals", "iso ='\(original.path)'"),
      ("whitespace after equals", "iso= '\(original.path)'"),
      ("source disguised by equals", "source = /some/file"),
      ("quoted hash suffixes", "iso='\(original.path)'#suffix"),
      ("opaque QEMU storage arguments", "extra_args='-drive file=\(original.path)'"),
    ]
    for (label, content) in ambiguous {
      try Data((content + "\n").utf8).write(to: config)
      try rejects("\(label) fail closed") { _ = try preview(original) }
    }
    try check(!FileManager.default.fileExists(atPath: marker.path), "configuration inspection never executes shell code")
    try Data("""
      #!/usr/bin/env quickemu
      # source and export in comments have no effect.
      guest_os="linux"
      disk_img="unrelated/disk.qcow2"
      ram="4G"
      cpu_cores=2
      public_dir=""
      extra_args=''
      export -- label='literal; $(text) # value'
      declare -rx -- iso='unrelated/image.iso' # unused by this selection
      readonly fixed_iso="unrelated/drivers.iso"
      \n
      """.utf8).write(to: config)
    _ = try preview(original)
    try check(true, "literal configurations and quoted shell punctuation permit unrelated media deletion")
    let punctuation = try file("quoted;# image.iso")
    try Data("export iso='\(punctuation.path)'\n".utf8).write(to: config)
    try rejects("quoted semicolons and hashes stay part of the referenced filename") { _ = try preview(punctuation) }
    try Data("iso=\"$UNKNOWN/image.iso\"\n".utf8).write(to: config)
    try rejects("computed Quickemu paths fail closed") { _ = try preview(original) }
    try FileManager.default.removeItem(at: config)
    let outside = try file("outside.txt", "keep")
    try FileManager.default.createSymbolicLink(at: protected.appendingPathComponent("outside"), withDestinationURL: outside)
    try rejects("VM containing a symbolic link is preserved") { _ = try preview(protected, vm: true) }
    try FileManager.default.removeItem(at: protected.appendingPathComponent("outside"))
    try FileManager.default.linkItem(at: outside, to: protected.appendingPathComponent("shared"))
    try rejects("VM containing shared hard links is preserved") { _ = try preview(protected, vm: true) }
    try FileManager.default.removeItem(at: protected.appendingPathComponent("shared"))
    let oldToken = try preview(protected, vm: true)
    try Data("new".utf8).write(to: protected.appendingPathComponent("new-file"))
    try rejects("new files inside a VM invalidate confirmation") { try delete(protected, vm: true, token: oldToken) }
    try delete(protected, vm: true, token: preview(protected, vm: true))
    try check(try String(contentsOf: outside, encoding: .utf8) == "keep", "unrelated file survives all deletion tests")

    let mediaRoot = root.appendingPathComponent("Install Media/macos-arm64-test")
    try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
    let downloaded = mediaRoot.appendingPathComponent("macOS.ipsw")
    try Data("download".utf8).write(to: downloaded)
    try store.rememberMedia(original.path)
    let restored = NativeStorageStore(preferences: defaults)
    let catalog = try restored.listMedia(workspace: root.path)
    try check(catalog.contains { $0["path"] as? String == downloaded.path }, "completed workspace download is rediscovered")
    try check(catalog.contains { $0["path"] as? String == original.path }, "selected external image registration survives service recreation")
    try check(!catalog.contains { $0["path"] as? String == partial.path || $0["path"] as? String == linked.path }, "catalog excludes partial files and symlinks")

    let second = root.appendingPathComponent("second")
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
    let secondVM = second.appendingPathComponent("Other.quickgui-winarm")
    try FileManager.default.createDirectory(at: secondVM, withIntermediateDirectories: false)
    try MacVMStore.createFile(secondVM.appendingPathComponent("vm.lock"))
    try JSONSerialization.data(withJSONObject: ["schema": 1, "installationPending": true, "iso": original.path]).write(to: secondVM.appendingPathComponent("vm.json"))
    try restored.rememberWorkspace(second.path)
    try rejects("previously visited workspace also protects media") { _ = try restored.preview(path: original.path, workspace: root.path, isVM: false) }
    print("\(count) native deletion checks passed")
  }
}
