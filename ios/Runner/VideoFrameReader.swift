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
  /// The clip's 2–8 kHz sound energy in dB, one value per 5 ms from 0; nil when it has no readable sound.
  let sound: [Float]?

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
    sound = Self.soundEnvelope(asset)
  }

  deinit { reader.cancelReading() }

  /// Reads the whole audio track with a second reader, which mixes it to mono 48 kHz float.
  /// Never throws: no audio track, or audio that won't decode, is nil.
  private static func soundEnvelope(_ asset: AVAsset) -> [Float]? {
    guard let track = asset.tracks(withMediaType: .audio).first,
      let reader = try? AVAssetReader(asset: asset)
    else { return nil }
    let rate = 48000.0
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
        AVNumberOfChannelsKey: 1, AVSampleRateKey: rate,
      ])
    guard reader.canAdd(output) else { return nil }
    reader.add(output)
    guard reader.startReading() else { return nil }
    var envelope = SoundEnvelope(rate: rate)
    var first = true
    while let sample = output.copyNextSampleBuffer() {
      // Sound that starts after 0 (an edit list) is silence until then, so the windows stay on clip time.
      let start = CMSampleBufferGetPresentationTimeStamp(sample)
      if first, start.isNumeric {
        for _ in 0..<max(0, Int((start.seconds * rate).rounded())) { envelope.add(0) }
      }
      first = false
      guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
      var pcm = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / 4)
      if pcm.isEmpty { continue }
      let copied = pcm.withUnsafeMutableBytes {
        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
      }
      guard copied == kCMBlockBufferNoErr else { return nil }
      for x in pcm { envelope.add(x) }
    }
    guard reader.status == .completed, !envelope.db.isEmpty else { return nil }
    return envelope.db
  }

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

/// A 2nd-order RBJ cookbook filter, Q = 0.7071, at `f0` Hz.
private struct Biquad {
  var b0, b1, b2, a1, a2: Float
  var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

  init(highPass: Bool, f0: Double, rate: Double) {
    let w = 2 * Double.pi * f0 / rate, a = sin(w) / (2 * 0.7071), c = cos(w), a0 = 1 + a
    let k = highPass ? (1 + c) / 2 : (1 - c) / 2
    b0 = Float(k / a0); b1 = Float((highPass ? -2 * k : 2 * k) / a0); b2 = b0
    a1 = Float(-2 * c / a0); a2 = Float((1 - a) / a0)
  }

  mutating func run(_ x: Float) -> Float {
    let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
    x2 = x1; x1 = x; y2 = y1; y1 = y
    return y
  }
}

/// Sound energy in dB after a 2 kHz high-pass and an 8 kHz low-pass, one value per 5 ms window:
/// window k is samples [round(k·rate/200), round((k+1)·rate/200)), so windows average exactly 5 ms
/// at any rate. A last, partial window is left out.
private struct SoundEnvelope {
  private let rate: Double
  private var hp, lp: Biquad
  private var sum: Float = 0, n = 0, seen = 0, end: Int
  private(set) var db = [Float]()

  init(rate: Double) {
    self.rate = rate
    hp = Biquad(highPass: true, f0: 2000, rate: rate)
    lp = Biquad(highPass: false, f0: 8000, rate: rate)
    end = Int((rate / 200).rounded())
  }

  /// Feeds the next mono sample.
  mutating func add(_ x: Float) {
    let y = lp.run(hp.run(x))
    sum += y * y
    n += 1
    seen += 1
    guard seen == end else { return }
    db.append(10 * log10(sum / Float(n) + 1e-10))
    sum = 0
    n = 0
    end = Int((Double(db.count + 1) * rate / 200).rounded())
  }
}
