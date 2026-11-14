import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// Keep the recorded timing. GIF stores centiseconds, so 50 fps has an exact
// 20 ms frame delay; do not use a rounded 60 fps delay or speed up the footage.
@main struct Export {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: export input.mov output.gif") }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 840, height: 330)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let seconds = min(7.6, duration - 0.4)
        let frames = Int((seconds * 50).rounded(.down))
        let gif = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frames, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<frames {
            let time = CMTime(seconds: 0.35 + Double(frame)/50, preferredTimescale: 600)
            let image = try await generator.image(at: time).image
            CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 0.02, kCGImagePropertyGIFUnclampedDelayTime: 0.02
            ]] as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(gif))
        print("Exported \(frames) frames at 50 fps, \(Double(frames)/50)s, original speed: \(output.lastPathComponent)")
    }
}
