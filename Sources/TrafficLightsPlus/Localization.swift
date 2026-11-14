import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    static func systemDefault(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let preferredLanguage = preferredLanguages.first?.lowercased() else { return .english }
        return preferredLanguage.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

enum AppString: String, CaseIterable {
    case settingsWindowTitle = "settings.window.title"
    case settingsSubtitle = "settings.subtitle"
    case languageLabel = "language.label"
    case menuBarIconVisible = "menu_bar_icon.visible"
    case menuBarIconVisibleHelp = "menu_bar_icon.visible.help"
    case overlayEnabled = "overlay.enabled"
    case livePreview = "preview.title"
    case appearance = "appearance.title"
    case appearanceLiquidGlass = "appearance.liquid_glass"
    case liquidGlassHelp = "appearance.liquid_glass.help"
    case followSystemGlassTransparency = "appearance.liquid_glass.follow_system_transparency"
    case followSystemGlassTransparencyHelp = "appearance.liquid_glass.follow_system_transparency.help"
    case glassGroupRevealHelp = "hidden_traffic_lights.glass_group.help"
    case buttonSize = "button.size"
    case restoreDefault = "button.restore_default"
    case buttonSpacing = "button.spacing"
    case restoreSystemSpacing = "button.restore_system_spacing"
    case systemSpacing = "button.spacing.system"
    case hiddenTrafficLights = "hidden_traffic_lights.title"
    case revealMode = "hidden_traffic_lights.reveal_mode"
    case revealGroup = "hidden_traffic_lights.group"
    case revealSingle = "hidden_traffic_lights.single"
    case fullScreenInDevelopment = "fullscreen.in_development"
    case dockClickMinimize = "dock_click.title"
    case dockClickMinimizeHelp = "dock_click.help"
    case stageManagerCloseButtons = "stage_manager_close.title"
    case stageManagerCloseButtonsHelp = "stage_manager_close.help"
    case stageManagerCloseAction = "stage_manager_close.action"
    case softwareUpdates = "software_updates.title"
    case automaticallyCheckForUpdates = "software_updates.automatic_check"
    case automaticallyDownloadUpdates = "software_updates.automatic_download"
    case checkForUpdates = "software_updates.check_now"
    case updatesUnavailable = "software_updates.unavailable"
    case buttonActions = "button_actions.title"
    case redButton = "button.red"
    case yellowButton = "button.yellow"
    case greenButton = "button.green"
    case behaviorCloseWindow = "behavior.close_window"
    case behaviorQuitApplication = "behavior.quit_application"
    case behaviorMinimizeWindow = "behavior.minimize_window"
    case behaviorZoomWindow = "behavior.zoom_window"
    case behaviorHideApplication = "behavior.hide_application"
    case behaviorDoNothing = "behavior.do_nothing"
    case quitOnCloseEnabled = "quit_on_close.enabled"
    case quitOnCloseHelp = "quit_on_close.help"
    case applicationList = "application_list.title"
    case applicationListHelp = "application_list.help"
    case applicationFollowGlobal = "application_list.follow_global"
    case applicationEnabled = "application_list.enabled"
    case applicationDisabled = "application_list.disabled"
    case applicationOverlayAccessibility = "application_list.overlay.accessibility"
    case applicationQuitOnClose = "application_list.quit_on_close"
    case runningApplications = "application_list.running"
    case chooseApplicationFile = "application_list.choose_file"
    case addApplication = "quit_on_close.add"
    case addApplicationAccessibility = "quit_on_close.add.accessibility"
    case noApplicationsAdded = "quit_on_close.empty"
    case removeApplication = "quit_on_close.remove"
    case removeApplicationAccessibility = "quit_on_close.remove.accessibility"
    case accessibilityGranted = "accessibility.granted"
    case accessibilityRequired = "accessibility.required"
    case openAccessibilitySettings = "accessibility.open_settings"
    case accessibilityInstructions = "accessibility.instructions"
    case chooseApplication = "application_list.picker.title"
    case addPickerPrompt = "quit_on_close.picker.prompt"
    case cannotAddApplication = "quit_on_close.error.title"
    case missingBundleIdentifier = "quit_on_close.error.missing_bundle_identifier"
    case ok = "common.ok"
    case menuSettings = "menu.settings"
    case menuEnableOverlays = "menu.enable_overlays"
    case menuEnableDockClick = "menu.enable_dock_click"
    case menuQuit = "menu.quit"
    case windowMenuTitle = "window_menu.title"
    case windowMenuMoveResize = "window_menu.move_resize"
    case windowMenuArrange = "window_menu.arrange"
    case windowMenuFullScreen = "window_menu.full_screen"
    case windowMenuUnsupported = "window_menu.unsupported"
    case windowMenuLeft = "window_menu.left"
    case windowMenuRight = "window_menu.right"
    case windowMenuTop = "window_menu.top"
    case windowMenuBottom = "window_menu.bottom"
    case windowMenuTopLeft = "window_menu.top_left"
    case windowMenuTopRight = "window_menu.top_right"
    case windowMenuBottomLeft = "window_menu.bottom_left"
    case windowMenuBottomRight = "window_menu.bottom_right"
    case windowMenuFill = "window_menu.fill"
    case windowMenuHalves = "window_menu.halves"
    case windowMenuThreeWindows = "window_menu.three_windows"
    case windowMenuQuarters = "window_menu.quarters"
    case windowMenuEnterFullScreen = "window_menu.enter_full_screen"
    case windowMenuExitFullScreen = "window_menu.exit_full_screen"
    case windowMenuFullScreenLeft = "window_menu.full_screen_left"
    case windowMenuFullScreenRight = "window_menu.full_screen_right"
}

enum AppLocalization {
    static func string(
        _ key: AppString,
        language: AppLanguage,
        arguments: [CVarArg] = []
    ) -> String {
        let format = table(for: language)[key.rawValue] ?? key.rawValue
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    static func missingKeys(for language: AppLanguage) -> [AppString] {
        AppString.allCases.filter {
            string($0, language: language) == $0.rawValue
        }
    }

    private static let tables: [AppLanguage: [String: String]] = Dictionary(
        uniqueKeysWithValues: AppLanguage.allCases.map { language in
            (language, loadTable(for: language))
        }
    )

    private static func table(for language: AppLanguage) -> [String: String] {
        tables[language] ?? [:]
    }

    private static func loadTable(for language: AppLanguage) -> [String: String] {
        guard let url = packagedLocalizationURL(for: language) ?? Bundle.module.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: language.rawValue
        ),
        let dictionary = NSDictionary(contentsOf: url) as? [String: String] else {
            return [:]
        }
        return dictionary
    }

    private static func packagedLocalizationURL(for language: AppLanguage) -> URL? {
        guard let resourcesURL = Bundle.main.resourceURL else { return nil }
        let url = resourcesURL
            .appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
