import Foundation
import Testing
@testable import TrafficLightsPlus

@Test func automaticDownloadControlRequiresAutomaticChecksAndUpdaterSupport() {
    #expect(UpdateController.automaticDownloadsControlEnabled(
        automaticallyChecksForUpdates: true,
        allowsAutomaticUpdates: true
    ))
    #expect(!UpdateController.automaticDownloadsControlEnabled(
        automaticallyChecksForUpdates: false,
        allowsAutomaticUpdates: true
    ))
    #expect(!UpdateController.automaticDownloadsControlEnabled(
        automaticallyChecksForUpdates: true,
        allowsAutomaticUpdates: false
    ))
}

@Test func updaterConfigurationRequiresAnHTTPSFeedAndPublicKey() {
    let key = Data(repeating: 1, count: 32).base64EncodedString()
    #expect(UpdateController.configurationAvailable(
        feedURL: "https://example.com/appcast.xml",
        publicKey: key
    ))
    #expect(!UpdateController.configurationAvailable(feedURL: nil, publicKey: key))
    for invalidKey in ["public-key", Data(repeating: 1, count: 31).base64EncodedString(), Data(repeating: 1, count: 33).base64EncodedString()] {
        #expect(!UpdateController.configurationAvailable(feedURL: "https://example.com/appcast.xml", publicKey: invalidKey))
    }
    #expect(!UpdateController.configurationAvailable(feedURL: "https:///appcast.xml", publicKey: key))
    #expect(!UpdateController.configurationAvailable(feedURL: "https://name:password@example.com/appcast.xml", publicKey: key))
    #expect(!UpdateController.configurationAvailable(
        feedURL: "http://example.com/appcast.xml",
        publicKey: key
    ))
    #expect(!UpdateController.configurationAvailable(
        feedURL: "https://example.com/appcast.xml",
        publicKey: ""
    ))
}
