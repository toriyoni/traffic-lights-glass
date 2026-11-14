import Foundation
import CryptoKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else {
    fail("Usage: verify-update-signatures.swift <public-key> <appcast.xml> [archive.zip]")
}
let args = CommandLine.arguments
let publicKey: Curve25519.Signing.PublicKey
do {
    guard let raw = Data(base64Encoded: args[1]), raw.count == 32 else { fail("Invalid Ed25519 public key") }
    publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: raw)
} catch { fail("Invalid public key: \(error)") }
let feed = try Data(contentsOf: URL(fileURLWithPath: args[2]))
let marker = Data("<!-- sparkle-signatures:".utf8)
guard let range = feed.range(of: marker, options: .backwards),
      let trailer = String(data: feed[range.lowerBound...], encoding: .utf8) else { fail("Missing signed-feed trailer") }
let expression = try NSRegularExpression(pattern: #"\A<!-- sparkle-signatures:\s*edSignature: ([A-Za-z0-9+/=]+)\s*length: ([0-9]+)\s*-->\s*\z"#)
guard let match = expression.firstMatch(in: trailer, range: NSRange(trailer.startIndex..., in: trailer)),
      let signatureRange = Range(match.range(at: 1), in: trailer),
      let lengthRange = Range(match.range(at: 2), in: trailer),
      let length = Int(trailer[lengthRange]), length == range.lowerBound,
      let signature = Data(base64Encoded: String(trailer[signatureRange])), signature.count == 64,
      publicKey.isValidSignature(signature, for: feed.prefix(length)) else { fail("Invalid appcast signature or signed length") }

final class Enclosures: NSObject, XMLParserDelegate {
    var entries: [[String: String]] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "enclosure" { entries.append(attributes) }
    }
}
let enclosures = Enclosures()
let parser = XMLParser(data: feed)
parser.shouldResolveExternalEntities = false
parser.delegate = enclosures
guard parser.parse() else { fail("Invalid appcast XML") }
if args.count == 4 {
    let archiveURL = URL(fileURLWithPath: args[3])
    let matches = enclosures.entries.filter { URL(string: $0["url"] ?? "")?.lastPathComponent == archiveURL.lastPathComponent }
    guard matches.count == 1, let entry = matches.first,
          let signatureText = entry["sparkle:edSignature"],
          let archiveSignature = Data(base64Encoded: signatureText), archiveSignature.count == 64 else { fail("Missing or ambiguous archive signature") }
    let archive = try Data(contentsOf: archiveURL)
    guard entry["length"].flatMap(Int.init) == archive.count,
          publicKey.isValidSignature(archiveSignature, for: archive) else { fail("Invalid archive signature or size") }
}
print("Verified signed appcast\(args.count == 4 ? " and archive" : "") with the embedded public key")
