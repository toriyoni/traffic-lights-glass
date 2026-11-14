import Foundation
import Testing
@testable import TrafficLightsPlus

@Test func releaseMetadataKeepsTheInstalledIdentityAndRequiresSignedUpdates() throws {
    let info = try sourceInfoPlist()
    #expect(info["CFBundleIdentifier"] as? String == "app.trafficlightsplus.glass.local")
    #expect(info["CFBundleName"] as? String == "Traffic Lights Glass")
    let version = try #require(info["CFBundleShortVersionString"] as? String)
    #expect(version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil)
    let build = try #require((info["CFBundleVersion"] as? String).flatMap(Int.init))
    #expect(build > 9) // Installed development copies used upstream build 9.
    #expect(info["SUFeedURL"] as? String == "https://github.com/toriyoni/traffic-lights-glass/releases/latest/download/appcast-arm64.xml")
    #expect(info["SURequireSignedFeed"] as? Bool == true)
    #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
    #expect(info["SUSendProfileInfo"] as? Bool == false)
    #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
    #expect(info["SUAutomaticallyUpdate"] as? Bool == false)
    let publicKey = try #require(info["SUPublicEDKey"] as? String)
    #expect(Data(base64Encoded: publicKey)?.count == 32)
    #expect(publicKey != "eiz9SZ4C/0cljdNMa0/7yweFUbXH+vUTHOoI71DHwrg=")
}

@Test func softwareUpdateCopyIsLocalizedInBothLanguages() {
    #expect(AppLocalization.string(.softwareUpdates, language: .simplifiedChinese) == "软件更新")
    #expect(AppLocalization.string(.softwareUpdates, language: .english) == "Software Updates")
    #expect(AppLocalization.string(.checkForUpdates, language: .simplifiedChinese) == "检查更新…")
    #expect(AppLocalization.string(.checkForUpdates, language: .english) == "Check for Updates…")
}

private func sourceInfoPlist() throws -> [String: Any] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Info.plist"))
    let value = try PropertyListSerialization.propertyList(from: data, format: nil)
    return try #require(value as? [String: Any])
}
