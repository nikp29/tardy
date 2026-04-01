import Foundation

// Override SPM's Bundle.module to also search Contents/Resources/ inside an .app bundle
extension Bundle {
    static let appModule: Bundle = {
        // First try SPM's default location (works during development via swift run)
        let spmPath = Bundle.main.bundleURL.appendingPathComponent("Tardy_Tardy.bundle").path
        if let bundle = Bundle(path: spmPath) {
            return bundle
        }

        // In a packaged .app, Bundle.main.bundleURL is Tardy.app/
        // Resources are at Tardy.app/Contents/Resources/
        let appResourcePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/Tardy_Tardy.bundle").path
        if let bundle = Bundle(path: appResourcePath) {
            return bundle
        }

        // Fallback: look next to the executable
        let executablePath = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("Tardy_Tardy.bundle").path ?? ""
        if let bundle = Bundle(path: executablePath) {
            return bundle
        }

        fatalError("Could not find Tardy_Tardy.bundle")
    }()
}
