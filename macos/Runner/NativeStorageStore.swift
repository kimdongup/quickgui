import Foundation
import Darwin
import CryptoKit

/// Deletion is limited to native VM bundles and explicitly listed ISO/IPSW files.
/// Preview tokens bind confirmation to the current files, not just a pathname.
final class NativeStorageStore {
  static let shared = NativeStorageStore()
  private let preferences: UserDefaults
  private let registryLock = NSLock()
  private let workspaceKey = "quickgui.storage.workspaces"
  private let mediaKey = "quickgui.storage.media"
  init(preferences: UserDefaults = .standard) { self.preferences = preferences }

  func rememberWorkspace(_ path: String) throws {
    let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
      throw MacVMError("The VM workspace is unavailable.")
    }
    registryLock.lock()
    defer { registryLock.unlock() }
    var paths = preferences.stringArray(forKey: workspaceKey) ?? []
    if !paths.contains(url.path) { paths.append(url.path); preferences.set(paths, forKey: workspaceKey) }
  }

  func rememberMedia(_ path: String) throws {
    let url = try mediaURL(path)
    registryLock.lock()
    defer { registryLock.unlock() }
    var paths = preferences.stringArray(forKey: mediaKey) ?? []
    if !paths.contains(url.path) { paths.append(url.path); preferences.set(paths, forKey: mediaKey) }
  }

  private func mediaURL(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard ["iso", "ipsw"].contains(url.pathExtension.lowercased()) else {
      throw MacVMError("Select a completed ISO or IPSW installation file.")
    }
    try MacVMStore.regularFile(url)
    let resolved = url.resolvingSymlinksInPath()
    guard !resolved.pathComponents.contains(where: { $0.hasSuffix(".quickgui-macvm") || $0.hasSuffix(".quickgui-winarm") }) else {
      throw MacVMError("Files inside a VM must be removed with that VM.")
    }
    return resolved
  }

  func listMedia(workspace: String) throws -> [[String: Any]] {
    try rememberWorkspace(workspace)
    var paths = Set(preferences.stringArray(forKey: mediaKey) ?? [])
    let root = URL(fileURLWithPath: workspace).appendingPathComponent("Install Media")
    func collect(_ folder: URL, children: Bool) throws {
      let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else { return }
      for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
        if ["iso", "ipsw"].contains(file.pathExtension.lowercased()) { paths.insert(file.path) }
        else if children && (file.lastPathComponent.hasPrefix("macos-arm64-") || file.lastPathComponent.hasPrefix("windows-arm64-")) {
          try collect(file, children: false)
        }
      }
    }
    if FileManager.default.fileExists(atPath: root.path) { try collect(root, children: true) }
    // Files outside the workspace are registered through the native file picker.
    return paths.sorted().compactMap { path -> [String: Any]? in
      guard let url = try? mediaURL(path), let info = try? snapshot(url) else { return nil }
      return ["path": url.path, "name": url.lastPathComponent, "bytes": info.bytes,
              "kind": url.pathExtension.uppercased()]
    }.reduce(into: [[String: Any]]()) { rows, row in
      if !rows.contains(where: { $0["path"] as? String == row["path"] as? String }) { rows.append(row) }
    }
  }

  private struct Snapshot { let token: String; let bytes: UInt64 }
  private func snapshot(_ root: URL) throws -> Snapshot {
    var records: [String] = [], total: UInt64 = 0, count = 0
    var rootInfo = stat()
    guard lstat(root.path, &rootInfo) == 0 else { throw MacVMError("The selected item no longer exists.") }
    func visit(_ url: URL, relative: String) throws {
      count += 1
      guard count <= 10000 else { throw MacVMError("The VM contains too many files to safely review.") }
      var info = stat()
      guard lstat(url.path, &info) == 0, info.st_dev == rootInfo.st_dev else {
        throw MacVMError("The item changed or contains another mounted volume.")
      }
      let directory = info.st_mode & S_IFMT == S_IFDIR
      guard directory || (info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1) else {
        throw MacVMError("Deletion refused: a symbolic link, shared hard link, or special file needs manual inspection.")
      }
      if relative != ".", directory, ["quickgui-macvm", "quickgui-winarm"].contains(url.pathExtension) {
        throw MacVMError("A nested VM must be managed separately.")
      }
      // Renaming into quarantine changes ctime, so use identity, mode, size and
      // nanosecond mtime. File and directory membership are checked again there.
      records.append("\(relative):\(info.st_dev):\(info.st_ino):\(info.st_mode):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)")
      total += UInt64(max(0, info.st_blocks)) * 512
      if directory {
        for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
          try visit(child, relative: relative + "/" + child.lastPathComponent)
        }
      }
    }
    try visit(root, relative: ".")
    let data = try JSONSerialization.data(withJSONObject: records)
    return Snapshot(token: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), bytes: total)
  }

  private func json(_ file: URL) throws -> [String: Any] {
    try MacVMStore.regularFile(file)
    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
    guard size < 64 * 1024,
          let value = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
          value["schema"] as? Int == 1 else { throw MacVMError("Cannot verify VM metadata: \(file.path)") }
    return value
  }

  private func ownerIsAlive(_ bundle: URL) throws -> Bool {
    let owner = bundle.appendingPathComponent("owner.json")
    guard FileManager.default.fileExists(atPath: owner.path) else { return false }
    try MacVMStore.regularFile(owner)
    guard (try owner.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 64 * 1024 else {
      throw MacVMError("Invalid VM owner record.")
    }
    let pids = try JSONDecoder().decode([Int32].self, from: Data(contentsOf: owner))
    return pids.contains { $0 > 1 && (kill($0, 0) == 0 || errno == EPERM) }
  }

  private func ensureUnreferenced(_ target: URL, isVM: Bool) throws {
    func refers(_ value: String, relativeTo root: URL) -> Bool {
      let url = (value.hasPrefix("/") ? URL(fileURLWithPath: value) : root.appendingPathComponent(value))
        .standardizedFileURL.resolvingSymlinksInPath()
      return url.path == target.path || (isVM && url.path.hasPrefix(target.path + "/"))
    }
    for path in preferences.stringArray(forKey: workspaceKey) ?? [] {
      let workspace = URL(fileURLWithPath: path)
      guard FileManager.default.fileExists(atPath: path) else {
        // A disconnected workspace cannot be checked for references.
        throw MacVMError("Reconnect the previously used VM workspace before deleting: \(path)")
      }
      for item in try FileManager.default.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil) {
        if item.standardizedFileURL.resolvingSymlinksInPath().path == target.path { continue }
        if ["quickgui-macvm", "quickgui-winarm"].contains(item.pathExtension) {
          let bundle = try MacVMStore.bundle(at: item.path, extensionName: item.pathExtension)
          let lock = try MacVMLock(bundle: bundle)
          defer { lock.release() }
          guard try !ownerIsAlive(bundle) else { throw MacVMError("Stop the VM before deleting storage: \(item.lastPathComponent)") }
          let value = try json(bundle.appendingPathComponent("vm.json"))
          if item.pathExtension == "quickgui-winarm" {
            guard let pending = value["installationPending"] as? Bool, let iso = value["iso"] as? String else {
              throw MacVMError("Cannot verify Windows installation media: \(item.lastPathComponent)")
            }
            if pending && refers(iso, relativeTo: workspace) {
              throw MacVMError("This image is still needed to install \(item.deletingPathExtension().lastPathComponent). Finish installation or delete that VM first.")
            }
          } else {
            guard let state = value["installation"] as? String else { throw MacVMError("Cannot verify Apple VM installation state.") }
            if state == "installing", let ipsw = value["restoreImage"] as? String, refers(ipsw, relativeTo: workspace) {
              throw MacVMError("This IPSW is still referenced by an unfinished macOS installation.")
            }
          }
        } else if item.pathExtension == "conf" {
          try MacVMStore.regularFile(item)
          guard (try item.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 1024 * 1024 else {
            throw MacVMError("Cannot safely inspect the VM configuration: \(item.path)")
          }
          let content = try String(contentsOf: item, encoding: .utf8)
          for line in content.components(separatedBy: .newlines) {
            let assignment = try NSRegularExpression(pattern: #"^\s*(disk_img|iso|fixed_iso|floppy|img|bootloader|firmware)\s*=\s*(.*?)\s*$"#)
            let ns = line as NSString
            guard let match = assignment.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let raw = ns.substring(with: match.range(at: 2))
            let value: String?
            if raw.hasPrefix("'") { value = literal(raw, pattern: #"^'([^']*)'\s*(?:#.*)?$"#) }
            else if raw.hasPrefix("\"") {
              let text = literal(raw, pattern: #"^"([^"\\]*)"\s*(?:#.*)?$"#)
              value = text?.contains("$") == true || text?.contains(String(UnicodeScalar(96))) == true ? nil : text
            } else { value = literal(raw, pattern: #"^([a-zA-Z0-9_./:+-]*)\s*(?:#.*)?$"#) }
            guard let value = value else {
              throw MacVMError("Cannot verify a computed storage path in \(item.lastPathComponent). Review it before deleting.")
            }
            if !value.isEmpty && refers(value, relativeTo: workspace) {
              throw MacVMError("Storage is referenced by \(item.lastPathComponent). Remove that reference first.")
            }
          }
        }
      }
    }
  }

  private func literal(_ raw: String, pattern: String) -> String? {
    let text = raw as NSString
    guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: raw, range: NSRange(location: 0, length: text.length)) else { return nil }
    return text.substring(with: match.range(at: 1))
  }

  private func withItem<T>(path: String, workspace: String, isVM: Bool, body: (URL) throws -> T) throws -> T {
    try rememberWorkspace(workspace)
    let target: URL
    let vmLock: MacVMLock?
    let imageLock: MacVMFileLease?
    if isVM {
      let extensionName = URL(fileURLWithPath: path).pathExtension
      guard ["quickgui-macvm", "quickgui-winarm"].contains(extensionName) else { throw MacVMError("Select a native Quickgui VM.") }
      target = try MacVMStore.bundle(at: path, extensionName: extensionName)
      try rememberWorkspace(target.deletingLastPathComponent().path)
      vmLock = try MacVMLock(bundle: target)
      imageLock = nil
      guard try !ownerIsAlive(target) else { throw MacVMError("This VM is still running in another process.") }
      _ = try json(target.appendingPathComponent("vm.json"))
    } else {
      target = try mediaURL(path)
      vmLock = nil
      imageLock = try MacVMFileLease(target, exclusive: true)
    }
    defer { vmLock?.release(); imageLock?.release() }
    try ensureUnreferenced(target, isVM: isVM)
    return try body(target)
  }

  func preview(path: String, workspace: String, isVM: Bool) throws -> [String: Any] {
    try withItem(path: path, workspace: workspace, isVM: isVM) { url in
      let info = try snapshot(url)
      return ["path": url.path, "name": isVM ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent,
              "bytes": info.bytes, "token": info.token, "isVM": isVM]
    }
  }

  func delete(path: String, workspace: String, isVM: Bool, token: String) throws {
    try withItem(path: path, workspace: workspace, isVM: isVM) { url in
      guard try snapshot(url).token == token else { throw MacVMError("The selected item changed. Review it again before deleting.") }
      // Quarantine in the same directory prevents a new VM start by its old path.
      let staged = url.deletingLastPathComponent().appendingPathComponent(".quickgui-deleting-\(UUID().uuidString)")
      guard renameatx_np(AT_FDCWD, url.path, AT_FDCWD, staged.path, UInt32(RENAME_EXCL)) == 0 else {
        throw MacVMError("Could not prepare the item for deletion. Nothing was deleted.")
      }
      do {
        guard try snapshot(staged).token == token else { throw MacVMError("The item changed while preparing deletion.") }
        try removeWithoutFollowingLinks(staged)
      } catch {
        let restored = renameatx_np(AT_FDCWD, staged.path, AT_FDCWD, url.path, UInt32(RENAME_EXCL)) == 0
        throw MacVMError("Deletion did not finish. Remaining data: \(restored ? url.path : staged.path). \(error.localizedDescription)")
      }
    }
    if !isVM {
      registryLock.lock()
      defer { registryLock.unlock() }
      preferences.set((preferences.stringArray(forKey: mediaKey) ?? []).filter { $0 != URL(fileURLWithPath: path).standardizedFileURL.path }, forKey: mediaKey)
    }
  }

  /// Walk through directory descriptors: never follow a newly introduced symlink.
  private func removeWithoutFollowingLinks(_ url: URL) throws {
    func remove(parent: Int32, name: String, device: dev_t) throws {
      var info = stat()
      guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0, info.st_dev == device else {
        throw MacVMError("A file changed during deletion.")
      }
      if info.st_mode & S_IFMT == S_IFDIR {
        let child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard child >= 0 else { throw MacVMError("Cannot open the VM directory safely.") }
        defer { close(child) }
        guard let stream = fdopendir(dup(child)) else { throw MacVMError("Cannot read the VM directory.") }
        defer { closedir(stream) }
        while let entry = readdir(stream) {
          let childName = withUnsafePointer(to: &entry.pointee.d_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
          }
          if childName != "." && childName != ".." { try remove(parent: child, name: childName, device: device) }
        }
        guard unlinkat(parent, name, AT_REMOVEDIR) == 0 else { throw MacVMError("Cannot remove the VM directory.") }
      } else {
        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, unlinkat(parent, name, 0) == 0 else {
          throw MacVMError("An unsafe or unavailable file was left in place.")
        }
      }
    }
    let parent = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard parent >= 0 else { throw MacVMError("The storage folder is unavailable.") }
    defer { close(parent) }
    var info = stat()
    guard fstatat(parent, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw MacVMError("The item is unavailable.") }
    try remove(parent: parent, name: url.lastPathComponent, device: info.st_dev)
  }
}
