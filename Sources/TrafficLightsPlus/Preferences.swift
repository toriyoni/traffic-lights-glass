import Foundation

enum ControlStyle: String, CaseIterable {
    case liquidGlass
    case macOS
    case edgeSquares

    func title(language: AppLanguage) -> String {
        switch self {
        case .liquidGlass: return AppLocalization.string(.appearanceLiquidGlass, language: language)
        case .macOS: return AppLocalization.string(.appearanceMacOS, language: language)
        case .edgeSquares: return AppLocalization.string(.appearanceEdgeSquares, language: language)
        }
    }
}

enum HiddenTrafficLightRevealMode: String, CaseIterable {
    case group
    case nearest

    func title(language: AppLanguage) -> String {
        switch self {
        case .group: return AppLocalization.string(.revealGroup, language: language)
        case .nearest: return AppLocalization.string(.revealSingle, language: language)
        }
    }
}

struct QuitOnCloseApplication: Codable, Hashable, Identifiable {
    let bundleIdentifier: String
    let displayName: String

    var id: String { bundleIdentifier }
}

final class Preferences: ObservableObject {
    private enum Key {
        static let language = "appLanguage"
        static let menuBarIconVisible = "menuBarIconVisible"
        static let enabled = "enabled"
        static let size = "controlSize"
        static let spacing = "controlSpacingAdjustment"
        static let style = "controlStyle"
        static let hiddenTrafficLightsEnabled = "hiddenTrafficLightsEnabled"
        static let hiddenTrafficLightRevealMode = "hiddenTrafficLightRevealMode"
        static let showInFullScreen = "showInFullScreen"
        static let dockClickMinimizesActiveWindow = "dockClickMinimizesActiveWindow"
        static let stageManagerCloseButtonsEnabled = "stageManagerCloseButtonsEnabled"
        static let quitOnCloseEnabled = "quitOnCloseEnabled"
        static let closeBehavior = "closeButtonBehavior"
        static let minimizeBehavior = "minimizeButtonBehavior"
        static let zoomBehavior = "zoomButtonBehavior"
        static let quitOnCloseApplications = "quitOnCloseApplications"
        static let applicationRules = "applicationRules"
    }

    private let defaults: UserDefaults

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    @Published var menuBarIconVisible: Bool {
        didSet { defaults.set(menuBarIconVisible, forKey: Key.menuBarIconVisible) }
    }

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }

    @Published var size: Double {
        didSet { defaults.set(size, forKey: Key.size) }
    }

    @Published var spacing: Double {
        didSet { defaults.set(spacing, forKey: Key.spacing) }
    }

    @Published var style: ControlStyle {
        didSet { defaults.set(style.rawValue, forKey: Key.style) }
    }

    @Published var hiddenTrafficLightsEnabled: Bool {
        didSet { defaults.set(hiddenTrafficLightsEnabled, forKey: Key.hiddenTrafficLightsEnabled) }
    }

    @Published var hiddenTrafficLightRevealMode: HiddenTrafficLightRevealMode {
        didSet { defaults.set(hiddenTrafficLightRevealMode.rawValue, forKey: Key.hiddenTrafficLightRevealMode) }
    }

    @Published private(set) var showInFullScreen: Bool

    @Published var dockClickMinimizesActiveWindow: Bool {
        didSet { defaults.set(dockClickMinimizesActiveWindow, forKey: Key.dockClickMinimizesActiveWindow) }
    }

    @Published var stageManagerCloseButtonsEnabled: Bool {
        didSet { defaults.set(stageManagerCloseButtonsEnabled, forKey: Key.stageManagerCloseButtonsEnabled) }
    }

    @Published var quitOnCloseEnabled: Bool {
        didSet { defaults.set(quitOnCloseEnabled, forKey: Key.quitOnCloseEnabled) }
    }

    @Published var closeBehavior: ButtonBehavior {
        didSet { defaults.set(closeBehavior.rawValue, forKey: Key.closeBehavior) }
    }

    @Published var minimizeBehavior: ButtonBehavior {
        didSet { defaults.set(minimizeBehavior.rawValue, forKey: Key.minimizeBehavior) }
    }

    @Published var zoomBehavior: ButtonBehavior {
        didSet { defaults.set(zoomBehavior.rawValue, forKey: Key.zoomBehavior) }
    }

    @Published private(set) var applicationRules: [ApplicationRule] {
        didSet {
            persistApplicationRules()
        }
    }

    init(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.defaults = defaults
        let systemLanguage = AppLanguage.systemDefault(preferredLanguages: preferredLanguages)
        let storedLanguageValue = defaults.object(forKey: Key.language) as? String
        let initialLanguage = storedLanguageValue.flatMap(AppLanguage.init(rawValue:)) ?? systemLanguage
        defaults.register(defaults: [
            Key.menuBarIconVisible: true,
            Key.enabled: true,
            Key.size: ControlLayout.defaultSize,
            Key.spacing: ControlLayout.defaultSpacingAdjustment,
            Key.style: ControlStyle.liquidGlass.rawValue,
            Key.hiddenTrafficLightsEnabled: true,
            Key.hiddenTrafficLightRevealMode: HiddenTrafficLightRevealMode.group.rawValue,
            Key.showInFullScreen: false,
            Key.dockClickMinimizesActiveWindow: true,
            Key.stageManagerCloseButtonsEnabled: true,
            Key.quitOnCloseEnabled: true,
            Key.closeBehavior: ButtonBehavior.closeWindow.rawValue,
            Key.minimizeBehavior: ButtonBehavior.minimizeWindow.rawValue,
            Key.zoomBehavior: ButtonBehavior.zoomWindow.rawValue
        ])
        language = initialLanguage
        if storedLanguageValue != nil, AppLanguage(rawValue: storedLanguageValue ?? "") == nil {
            defaults.set(initialLanguage.rawValue, forKey: Key.language)
        }
        menuBarIconVisible = defaults.bool(forKey: Key.menuBarIconVisible)
        enabled = defaults.bool(forKey: Key.enabled)
        size = Double(ControlLayout.effectiveSize(preferred: defaults.double(forKey: Key.size)))
        spacing = Double(ControlLayout.effectiveSpacingAdjustment(preferred: defaults.double(forKey: Key.spacing)))
        style = ControlStyle(rawValue: defaults.string(forKey: Key.style) ?? "") ?? .liquidGlass
        hiddenTrafficLightsEnabled = defaults.bool(forKey: Key.hiddenTrafficLightsEnabled)
        hiddenTrafficLightRevealMode = HiddenTrafficLightRevealMode(
            rawValue: defaults.string(forKey: Key.hiddenTrafficLightRevealMode) ?? ""
        ) ?? .group
        showInFullScreen = false
        defaults.set(false, forKey: Key.showInFullScreen)
        dockClickMinimizesActiveWindow = defaults.bool(forKey: Key.dockClickMinimizesActiveWindow)
        stageManagerCloseButtonsEnabled = defaults.bool(forKey: Key.stageManagerCloseButtonsEnabled)
        quitOnCloseEnabled = defaults.bool(forKey: Key.quitOnCloseEnabled)
        closeBehavior = ButtonBehavior(rawValue: defaults.string(forKey: Key.closeBehavior) ?? "") ?? .closeWindow
        minimizeBehavior = ButtonBehavior(rawValue: defaults.string(forKey: Key.minimizeBehavior) ?? "") ?? .minimizeWindow
        zoomBehavior = ButtonBehavior(rawValue: defaults.string(forKey: Key.zoomBehavior) ?? "") ?? .zoomWindow
        applicationRules = Self.loadApplicationRules(from: defaults)
        persistApplicationRules()
    }

    // Preserve the user's classic-mode choice while keeping the glass capsule
    // as a single interaction target.
    var effectiveHiddenTrafficLightRevealMode: HiddenTrafficLightRevealMode {
        style == .liquidGlass ? .group : hiddenTrafficLightRevealMode
    }

    func behavior(for action: WindowAction) -> ButtonBehavior {
        switch action {
        case .close: return closeBehavior
        case .minimize: return minimizeBehavior
        case .zoom: return zoomBehavior
        }
    }

    func resetButtonBehaviors() {
        closeBehavior = .closeWindow
        minimizeBehavior = .minimizeWindow
        zoomBehavior = .zoomWindow
    }

    var hasCloseWindowBehavior: Bool {
        [closeBehavior, minimizeBehavior, zoomBehavior].contains(.closeWindow)
    }

    // The global switch is a default, not a master kill switch: an explicit
    // per-app enable must keep window observation and pointer handling alive.
    var hasEnabledOverlays: Bool {
        enabled || applicationRules.contains { $0.overlayMode == .enabled }
    }

    func overlayMode(bundleIdentifier: String?) -> ApplicationOverlayMode {
        applicationRule(bundleIdentifier: bundleIdentifier)?.overlayMode ?? .followGlobal
    }

    func overlaysEnabled(bundleIdentifier: String?) -> Bool {
        overlayMode(bundleIdentifier: bundleIdentifier).resolve(globalEnabled: enabled)
    }

    func shouldTrackApplication(bundleIdentifier: String?) -> Bool {
        overlaysEnabled(bundleIdentifier: bundleIdentifier)
            || shouldQuitOnClose(bundleIdentifier: bundleIdentifier)
    }

    @discardableResult
    func addApplication(bundleIdentifier: String, displayName: String) -> Bool {
        let identifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, applicationRule(bundleIdentifier: identifier) == nil else { return false }
        applicationRules.append(ApplicationRule(bundleIdentifier: identifier, displayName: displayName))
        return true
    }

    func removeApplication(bundleIdentifier: String) {
        applicationRules.removeAll {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
    }

    func setOverlayMode(_ mode: ApplicationOverlayMode, bundleIdentifier: String) {
        guard let index = applicationRuleIndex(bundleIdentifier: bundleIdentifier) else { return }
        applicationRules[index].overlayMode = mode
    }

    func setQuitOnClose(_ enabled: Bool, bundleIdentifier: String) {
        guard let index = applicationRuleIndex(bundleIdentifier: bundleIdentifier) else { return }
        applicationRules[index].quitOnClose = enabled
    }

    func applicationRule(bundleIdentifier: String?) -> ApplicationRule? {
        guard let bundleIdentifier,
              let index = applicationRuleIndex(bundleIdentifier: bundleIdentifier) else { return nil }
        return applicationRules[index]
    }

    private func applicationRuleIndex(bundleIdentifier: String) -> Int? {
        applicationRules.firstIndex {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
    }

    var quitOnCloseApplications: [QuitOnCloseApplication] {
        applicationRules.filter(\.quitOnClose).map {
            QuitOnCloseApplication(bundleIdentifier: $0.bundleIdentifier, displayName: $0.displayName)
        }
    }

    @discardableResult
    func addQuitOnCloseApplication(bundleIdentifier: String, displayName: String) -> Bool {
        guard applicationRule(bundleIdentifier: bundleIdentifier)?.quitOnClose != true else { return false }
        _ = addApplication(bundleIdentifier: bundleIdentifier, displayName: displayName)
        guard applicationRule(bundleIdentifier: bundleIdentifier) != nil else { return false }
        setQuitOnClose(true, bundleIdentifier: bundleIdentifier)
        return true
    }

    func removeQuitOnCloseApplication(bundleIdentifier: String) {
        setQuitOnClose(false, bundleIdentifier: bundleIdentifier)
    }

    func shouldQuitOnClose(bundleIdentifier: String?) -> Bool {
        quitOnCloseEnabled && applicationRule(bundleIdentifier: bundleIdentifier)?.quitOnClose == true
    }

    func effectiveBehavior(for action: WindowAction, bundleIdentifier: String?) -> ButtonBehavior {
        let configuredBehavior = behavior(for: action)
        guard configuredBehavior == .closeWindow,
              shouldQuitOnClose(bundleIdentifier: bundleIdentifier) else {
            return configuredBehavior
        }
        return .quitApplication
    }

    private func persistApplicationRules() {
        guard let data = try? JSONEncoder().encode(applicationRules) else { return }
        defaults.set(data, forKey: Key.applicationRules)
        // Keep the old membership key readable when rolling back the app binary.
        if let legacyData = try? JSONEncoder().encode(quitOnCloseApplications) {
            defaults.set(legacyData, forKey: Key.quitOnCloseApplications)
        }
    }

    private static func loadApplicationRules(from defaults: UserDefaults) -> [ApplicationRule] {
        let applications: [ApplicationRule]
        if let data = defaults.data(forKey: Key.applicationRules) {
            applications = (try? JSONDecoder().decode([ApplicationRule].self, from: data)) ?? []
        } else if let data = defaults.data(forKey: Key.quitOnCloseApplications),
                  let legacy = try? JSONDecoder().decode([QuitOnCloseApplication].self, from: data) {
            applications = legacy.map {
                ApplicationRule(bundleIdentifier: $0.bundleIdentifier, displayName: $0.displayName, quitOnClose: true)
            }
        } else {
            return []
        }

        var seenBundleIdentifiers = Set<String>()
        return applications.filter { application in
            let normalizedIdentifier = application.bundleIdentifier.lowercased()
            guard !normalizedIdentifier.isEmpty,
                  seenBundleIdentifiers.insert(normalizedIdentifier).inserted else { return false }
            return true
        }
    }
}
