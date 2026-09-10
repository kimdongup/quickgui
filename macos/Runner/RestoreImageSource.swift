import Foundation
import Virtualization

enum RestoreImageSource {
  static func latest(completion: @escaping (Result<[String: String], Error>) -> Void) {
    #if arch(arm64)
    if #available(macOS 12.0, *) {
      VZMacOSRestoreImage.fetchLatestSupported { result in
        switch result {
        case .success(let image):
          guard image.mostFeaturefulSupportedConfiguration != nil else {
            completion(.failure(unavailable()))
            return
          }
          let version = image.operatingSystemVersion
          completion(.success([
            "url": image.url.absoluteString,
            "version": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "build": image.buildVersion,
          ]))
        case .failure(let error):
          completion(.failure(error))
        }
      }
      return
    }
    #endif
    completion(.failure(unavailable()))
  }

  private static func unavailable() -> NSError {
    NSError(domain: "QuickguiRestoreImage", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "A compatible Apple Silicon Mac with macOS 12 or later is required."])
  }
}
