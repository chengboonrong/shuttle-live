import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

enum VideoFrameReaderError: Error {
  case noVideoTrack
  case cannotStart
}

/// Reads one video's frames in presentation order for the `shuttle_live/video_frames`
/// channel. Frames under 1/30 s after the last one returned are skipped, so a 60 fps
/// clip yields every other frame. Call from one thread at a time; no Flutter dependency.
final class VideoFrameReader {
  let durationUs: Int64
  /// Size after the track's rotation is applied.
  let width: Int
  let height: Int

  private static let minGapUs: Int64 = 32333
  private static let longestSide: CGFloat = 1280
  private static let thumbSize = CGSize(width: 32, height: 18)

  private let reader: AVAssetReader
  private let output: AVAssetReaderTrackOutput
  /// preferredTransform turned from top-left-origin (video) to bottom-left-origin (Core Image).
  private let orient: CGAffineTransform
  private let context = CIContext()
  private var lastUs: Int64?

  // ponytail: the sync track/duration/transform getters are deprecated since iOS 16 but still work
  // at the deployment target (15); switch to load(_:) when the target moves up.
  init(url: URL) throws {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
      throw VideoFrameReaderError.noVideoTrack
    }
    let t = track.preferredTransform
    let size = CGRect(origin: .zero, size: track.naturalSize).applying(t).standardized.size
    width = Int(size.width.rounded())
    height = Int(size.height.rounded())
    durationUs = asset.duration.isNumeric ? Self.micros(asset.duration) : 0
    orient = CGAffineTransform(a: t.a, b: -t.b, c: -t.c, d: t.d, tx: 0, ty: 0)

    reader = try AVAssetReader(asset: asset)
    output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    output.alwaysCopiesSampleData = false
    guard width > 0, height > 0, reader.canAdd(output) else {
      throw VideoFrameReaderError.cannotStart
    }
    reader.add(output)
    guard reader.startReading() else {
      throw reader.error ?? VideoFrameReaderError.cannotStart
    }
  }

  deinit { reader.cancelReading() }

  /// The next kept frame, or nil at the end of the clip (or if decoding stops).
  func next() -> (jpeg: Data, timeUs: Int64, thumb: Data)? {
    while let sample = output.copyNextSampleBuffer() {
      let us = Self.micros(CMSampleBufferGetPresentationTimeStamp(sample))
      if let last = lastUs, us - last < Self.minGapUs { continue }
      guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
      lastUs = us

      let rotated = CIImage(cvPixelBuffer: pixels).transformed(by: orient)
      let upright = rotated.transformed(
        by: CGAffineTransform(translationX: -rotated.extent.minX, y: -rotated.extent.minY))
      let side = CGFloat(max(width, height))
      let k = min(1, Self.longestSide / side)
      let small = scaled(upright, to: CGSize(width: (CGFloat(width) * k).rounded(), height: (CGFloat(height) * k).rounded()))
      guard
        let jpeg = context.jpegRepresentation(
          of: small, colorSpace: CGColorSpaceCreateDeviceRGB(),
          options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8])
      else { continue }

      // Gray = (77r + 150g + 29b) >> 8, the same formula as the Android reader, so one cut threshold fits both.
      var rgba = [UInt8](repeating: 0, count: 32 * 18 * 4)
      rgba.withUnsafeMutableBytes {
        context.render(
          scaled(upright, to: Self.thumbSize), toBitmap: $0.baseAddress!, rowBytes: 32 * 4,
          bounds: CGRect(origin: .zero, size: Self.thumbSize), format: .RGBA8,
          colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
      }
      let thumb: [UInt8] = (0..<32 * 18).map { i in
        let r = Int(rgba[4 * i]), g = Int(rgba[4 * i + 1]), b = Int(rgba[4 * i + 2])
        return UInt8((77 * r + 150 * g + 29 * b) >> 8)
      }
      return (jpeg, us, Data(thumb))
    }
    return nil
  }

  private static func micros(_ t: CMTime) -> Int64 {
    CMTimeConvertScale(t, timescale: 1_000_000, method: .roundTowardZero).value
  }

  /// Lanczos-scales to exactly `size` whatever the aspect (a plain affine downscale aliases badly at 32x18).
  /// The input is clamped to its extent so the kernel doesn't blend in transparent edges and darken the rim.
  private func scaled(_ image: CIImage, to size: CGSize) -> CIImage {
    let sy = size.height / image.extent.height
    let filter = CIFilter(name: "CILanczosScaleTransform")!
    filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
    filter.setValue(sy, forKey: kCIInputScaleKey)
    filter.setValue(size.width / image.extent.width / sy, forKey: kCIInputAspectRatioKey)
    return filter.outputImage!.cropped(to: CGRect(origin: .zero, size: size))
  }
}
