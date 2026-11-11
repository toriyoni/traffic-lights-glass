import Foundation

enum ApplicationOverlayMode: String, Codable, CaseIterable, Identifiable {
    case followGlobal
    case enabled
    case disabled

    var id: String { rawValue }

    func resolve(globalEnabled: Bool) -> Bool {
        switch self {
        case .followGlobal: return globalEnabled
        case .enabled: return true
        case .disabled: return false
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .followGlobal: return AppLocalization.string(.applicationFollowGlobal, language: language)
        case .enabled: return AppLocalization.string(.applicationEnabled, language: language)
        case .disabled: return AppLocalization.string(.applicationDisabled, language: language)
        }
    }
}

struct ApplicationRule: Codable, Hashable, Identifiable {
    let bundleIdentifier: String
    let displayName: String
    var overlayMode: ApplicationOverlayMode = .followGlobal
    // Membership in the existing, separately enabled quit-on-close feature.
    // Adding an enlargement exception must never opt an app into quitting.
    var quitOnClose = false

    var id: String { bundleIdentifier.lowercased() }
}
