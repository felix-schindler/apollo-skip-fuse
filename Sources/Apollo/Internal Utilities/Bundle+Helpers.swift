import Foundation

extension Bundle {

  /// Type-safe getter for info dictionary key objects
  ///
  /// - Parameter key: The key to try to grab an object for
  /// - Returns: The object of the desired type, or nil if it is not present or of the incorrect type.
  private func bundleValue<T>(forKey key: String) -> T? {
    return object(forInfoDictionaryKey: key) as? T
  }

  /// The bundle identifier of this bundle, or nil if not present.
  ///
  /// Not declared on Android: `Foundation.Bundle` already provides `bundleIdentifier` there, and
  /// redeclaring it makes deserialization of the Skip bridge's `AndroidBundle` subclass fail
  /// (`Bundle.bundleIdentifier` becomes an ambiguous override target in any module that imports
  /// Apollo), crashing `swift-frontend` with a SIL vtable deserialization failure.
  #if !os(Android)
  var bundleIdentifier: String? {
    return self.bundleValue(forKey: "CFBundleIdentifier")
  }
  #endif

  /// The build number of this bundle (kCFBundleVersion) as a string, or nil if not present.
  var buildNumber: String? {
    return self.bundleValue(forKey: "CFBundleVersion")
  }

  /// The short version string for this bundle, or nil if not present.
  var shortVersion: String? {
    return self.bundleValue(forKey: "CFBundleShortVersionString")
  }
}
