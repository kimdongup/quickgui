// Compile together with macos/Runner/RestoreImageSource.swift and ad-hoc sign
// with macos/Runner/Release.entitlements. Fetches metadata, not the IPSW body.
import Foundation

@main
enum CheckRestoreImage {
  static func main() {
    DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
      fputs("Restore image lookup timed out\n", stderr)
      exit(2)
    }
    RestoreImageSource.latest { result in
      switch result {
      case .success(let image):
        let data = try! JSONSerialization.data(withJSONObject: image, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        exit(0)
      case .failure(let error):
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
      }
    }
    dispatchMain()
  }
}
