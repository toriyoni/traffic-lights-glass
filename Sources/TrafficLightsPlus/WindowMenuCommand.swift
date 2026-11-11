import AppKit
import ApplicationServices

/// These identifiers come from the target application's standard Window menu.
/// They are matched as AX identifiers, never invoked as private ObjC selectors.
enum WindowMenuCommand: String, CaseIterable, Sendable {
    case left = "_zoomLeft:"
    case right = "_zoomRight:"
    case top = "_zoomTop:"
    case bottom = "_zoomBottom:"
    case topLeft = "_zoomTopLeft:"
    case topRight = "_zoomTopRight:"
    case bottomLeft = "_zoomBottomLeft:"
    case bottomRight = "_zoomBottomRight:"
    case fill = "_zoomFill:"
    case halves = "_zoomLeftAndRight:"
    case threeWindows = "_zoomRightThreeUp:"
    case quarters = "_zoomQuarters:"
    case fullScreen = "toggleFullScreen"
    case fullScreenLeft = "_tileLeft:"
    case fullScreenRight = "_tileRight:"

    static let halvesRow: [Self] = [.left, .right, .top, .bottom]
    static let cornersRow: [Self] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    static let arrangementRow: [Self] = [.fill, .halves, .threeWindows, .quarters]
    static let fullScreenRow: [Self] = [.fullScreen, .fullScreenLeft, .fullScreenRight]

    var frameFraction: CGRect? {
        switch self {
        case .left: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .top: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottom: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .fill: return CGRect(x: 0, y: 0, width: 1, height: 1)
        default: return nil
        }
    }

    func frame(in visibleScreen: CGRect) -> CGRect? {
        guard let fraction = frameFraction,
              visibleScreen.width > 0, visibleScreen.height > 0,
              !visibleScreen.isInfinite, !visibleScreen.isNull else { return nil }
        return CGRect(x: visibleScreen.minX + visibleScreen.width * fraction.minX,
                      y: visibleScreen.minY + visibleScreen.height * fraction.minY,
                      width: visibleScreen.width * fraction.width,
                      height: visibleScreen.height * fraction.height)
    }

    func title(language: AppLanguage, isFullScreen: Bool = false) -> String {
        let key: AppString
        switch self {
        case .left: key = .windowMenuLeft
        case .right: key = .windowMenuRight
        case .top: key = .windowMenuTop
        case .bottom: key = .windowMenuBottom
        case .topLeft: key = .windowMenuTopLeft
        case .topRight: key = .windowMenuTopRight
        case .bottomLeft: key = .windowMenuBottomLeft
        case .bottomRight: key = .windowMenuBottomRight
        case .fill: key = .windowMenuFill
        case .halves: key = .windowMenuHalves
        case .threeWindows: key = .windowMenuThreeWindows
        case .quarters: key = .windowMenuQuarters
        case .fullScreen: key = isFullScreen ? .windowMenuExitFullScreen : .windowMenuEnterFullScreen
        case .fullScreenLeft: key = .windowMenuFullScreenLeft
        case .fullScreenRight: key = .windowMenuFullScreenRight
        }
        return AppLocalization.string(key, language: language)
    }
}

struct WindowMenuSnapshot: Sendable {
    let enabled: Set<WindowMenuCommand>
    let isFullScreen: Bool
}

/// AX work runs on the overlay's serial menu queue. No menu action is cached:
/// resolve and validate again at selection time against the original window.
enum WindowMenuAccess {
    static func snapshot(pid: pid_t, window: AXUIElement) -> WindowMenuSnapshot {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.2)
        let native = nativeCommands(in: application)
        let fullScreen: Bool = attribute("AXFullScreen", of: window) ?? false
        let resizable = !fullScreen && settable(kAXPositionAttribute, on: window) && settable(kAXSizeAttribute, on: window)
        var enabled = Set(native.filter { attribute(kAXEnabledAttribute, of: $0.value) ?? false }.keys)
        // A few apps omit the standard Window menu. Only single-window geometry
        // has a fallback; never imitate multi-app arrangement or Split View.
        for command in WindowMenuCommand.allCases where native[command] == nil && command.frameFraction != nil && resizable {
            enabled.insert(command)
        }
        if settable("AXFullScreen", on: window) { enabled.insert(.fullScreen) }
        return WindowMenuSnapshot(enabled: enabled, isFullScreen: fullScreen)
    }

    static func perform(_ command: WindowMenuCommand, pid: pid_t, window: AXUIElement, visibleScreen: CGRect) -> AXError {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.2)
        guard attribute(kAXFrontmostAttribute, of: application) == true,
              let focused: AXUIElement = attribute(kAXFocusedWindowAttribute, of: application),
              CFEqual(focused, window) else { return .invalidUIElement }
        if command == .fullScreen {
            guard settable("AXFullScreen", on: window) else { return .attributeUnsupported }
            let current: Bool = attribute("AXFullScreen", of: window) ?? false
            return AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, current ? kCFBooleanFalse : kCFBooleanTrue)
        }
        if let item = nativeCommands(in: application)[command] {
            guard attribute(kAXEnabledAttribute, of: item) == true else { return .actionUnsupported }
            return AXUIElementPerformAction(item, kAXPressAction as CFString)
        }
        guard attribute("AXFullScreen", of: window) != true,
              settable(kAXPositionAttribute, on: window), settable(kAXSizeAttribute, on: window),
              let frame = command.frame(in: visibleScreen) else { return .actionUnsupported }
        var size = frame.size
        let resize = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
        guard resize == .success else { return resize }
        // Respect an app's minimum size and keep its top-left corner reachable.
        if let actual: AXValue = attribute(kAXSizeAttribute, of: window) { AXValueGetValue(actual, .cgSize, &size) }
        var origin = CGPoint(x: min(frame.minX, max(visibleScreen.minX, visibleScreen.maxX - size.width)),
                             y: min(frame.minY, max(visibleScreen.minY, visibleScreen.maxY - size.height)))
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
    }

    private static func nativeCommands(in application: AXUIElement) -> [WindowMenuCommand: AXUIElement] {
        guard let bar: AXUIElement = attribute(kAXMenuBarAttribute, of: application) else { return [:] }
        var result: [WindowMenuCommand: AXUIElement] = [:]
        func children(_ element: AXUIElement) -> [AXUIElement] { attribute(kAXChildrenAttribute, of: element) ?? [] }
        func command(_ element: AXUIElement) -> WindowMenuCommand? {
            let identifier: String? = attribute(kAXIdentifierAttribute, of: element)
            return identifier.flatMap(WindowMenuCommand.init(rawValue:))
        }
        func visit(_ element: AXUIElement, depth: Int) {
            guard depth < 5 else { return }
            if let command = command(element) { result[command] = element; return }
            for child in children(element).prefix(80) { visit(child, depth: depth + 1) }
        }
        // Identify the Window menu by its standard commands, not localized text.
        // Do not traverse unrelated document, history or recent-file submenus.
        for section in children(bar).prefix(20) {
            let items = children(section).flatMap(children)
            guard items.contains(where: { command($0) != nil }) else { continue }
            for item in items.prefix(80) { visit(item, depth: 0) }
        }
        return result
    }

    private static func settable(_ name: String, on element: AXUIElement) -> Bool {
        var value = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &value) == .success && value.boolValue
    }

    private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
