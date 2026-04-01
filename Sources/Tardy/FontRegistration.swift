import AppKit
import CoreText

enum FontRegistration {
    static func registerCustomFonts() {
        let fontFiles = [
            "InstrumentSans-Variable",
            "DMMono-Light",
            "DMMono-Regular",
        ]

        for fontFile in fontFiles {
            guard let fontURL = Bundle.module.url(forResource: fontFile, withExtension: "ttf", subdirectory: "Fonts") else {
                print("Tardy: Font file not found: \(fontFile).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
                print("Tardy: Failed to register font \(fontFile): \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            }
        }
    }
}
