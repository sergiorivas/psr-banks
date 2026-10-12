import Foundation

enum Resources {
    /// Looks in the app bundle first (packaged .app), then in the SwiftPM resource bundle (swift run / tests).
    static func url(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext) ?? Bundle.module.url(forResource: name, withExtension: ext)
    }
}
