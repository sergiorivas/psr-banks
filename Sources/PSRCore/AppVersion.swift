import Foundation

/// Version of the app and of the on-disk library format.
public enum AppVersion {
    /// Shown to the user, e.g. "0.3.0". Comes from Info.plist (written by build_app.sh, which gets the version from git tags).
    public static var marketing: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    public static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    public static var display: String { marketing == "dev" ? "dev build" : "v\(marketing) (\(build))" }
    /// Layout of the Library folder. Bump when `Patches/` or `Setlists/` change incompatibly.
    public static let libraryFormat = 1
}

/// `Library/library.json`: format version, which app version last opened it, and the default patch.
struct LibraryInfo: Codable, Equatable {
    var formatVersion: Int = AppVersion.libraryFormat
    var appVersion: String?
    var defaultPatchID: UUID?
    /// Bank descriptions remembered by content (see `LibraryStore.bankKey`), so a re-imported bank gets its label back.
    var bankLabels: [String: String]?
}
