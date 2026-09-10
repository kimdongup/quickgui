import Foundation
import Darwin

struct MacVMError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

/// Personal Apple VM bundles never contain or execute Quickemu shell configs.
struct MacVMMetadata: Codable {
  var schema = 1
  let name: String
  let version: String
  let build: String
  let cpuCount: Int
  let memoryBytes: UInt64
  let diskBytes: UInt64
  let macAddress: String
  var installation: String // installing, ready, failed, cancelled
  var error: String?
}

final class MacVMLock {
  private var descriptor: Int32
  init(bundle: URL) throws {
    descriptor = open(bundle.appendingPathComponent("vm.lock").path, O_RDWR | O_NOFOLLOW)
    guard descriptor >= 0 else { throw MacVMError("Cannot open the VM lock.") }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
          info.st_nlink == 1, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(descriptor)
      descriptor = -1
      throw MacVMError("This VM is in use by another Quickgui process, or its lock is invalid.")
    }
  }
  func release() {
    if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1 }
  }
  deinit { release() }
}

enum MacVMStore {
  static let bundleExtension = "quickgui-macvm"
  static let gib: UInt64 = 1024 * 1024 * 1024

  static func validateName(_ name: String) throws {
    guard !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
          name != ".", name != "..", name.utf8.count <= 100,
          name.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)) == nil else {
      throw MacVMError("Enter a VM name without slashes, colons, or control characters (up to 100 bytes).")
    }
  }

  static func bundle(at path: String) throws -> URL {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard url.pathExtension == bundleExtension else { throw MacVMError("Select a Quickgui Apple VM bundle.") }
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw MacVMError("The VM bundle must be a directory, not a symbolic link.")
    }
    return url.resolvingSymlinksInPath()
  }

  static func regularFile(_ url: URL) throws {
    var info = stat()
    guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
      throw MacVMError("Missing or unsafe VM file: \(url.lastPathComponent)")
    }
  }

  static func read(_ bundle: URL) throws -> MacVMMetadata {
    let file = bundle.appendingPathComponent("vm.json")
    try regularFile(file)
    let data = try Data(contentsOf: file, options: .mappedIfSafe)
    guard data.count < 64 * 1024 else { throw MacVMError("VM metadata is too large.") }
    let metadata = try JSONDecoder().decode(MacVMMetadata.self, from: data)
    try validateName(metadata.name)
    guard metadata.schema == 1, (1...64).contains(metadata.cpuCount),
          (2 * gib...512 * gib).contains(metadata.memoryBytes),
          (32 * gib...2 * 1024 * gib).contains(metadata.diskBytes),
          ["installing", "ready", "failed", "cancelled"].contains(metadata.installation) else {
      throw MacVMError("Unsupported or invalid Apple VM metadata.")
    }
    return metadata
  }

  static func write(_ metadata: MacVMMetadata, to bundle: URL) throws {
    let file = bundle.appendingPathComponent("vm.json")
    if FileManager.default.fileExists(atPath: file.path) { try regularFile(file) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(metadata).write(to: file, options: .atomic)
  }

  static func createFile(_ url: URL, size: UInt64 = 0) throws {
    let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw MacVMError("Cannot create \(url.lastPathComponent): \(String(cString: strerror(errno)))") }
    defer { close(fd) }
    guard ftruncate(fd, off_t(size)) == 0 else { throw MacVMError("Cannot size the virtual disk.") }
  }

  /// mkdir is exclusive: even an empty existing directory is never reused.
  static func create(in directory: String, metadata: MacVMMetadata) throws -> URL {
    try validateName(metadata.name)
    let parent = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath()
    let url = parent.appendingPathComponent(metadata.name).appendingPathExtension(bundleExtension)
    guard mkdir(url.path, S_IRWXU) == 0 else {
      throw MacVMError("Cannot create VM folder. Choose a new name and a writable workspace; existing folders are never overwritten.")
    }
    // Failed creation stays visible as incomplete; never recursively delete a VM.
    try createFile(url.appendingPathComponent("vm.lock"))
    try write(metadata, to: url)
    return url
  }
}
