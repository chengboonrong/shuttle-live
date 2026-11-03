import Flutter
import UIKit

// iOS 27 stops apps at launch that skip the UIScene lifecycle, so this follows
// Flutter's UIScene migration: plugins register on the implicit engine.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    application.isIdleTimerDisabled = true // the phone sits on a tripod for a whole match
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Video-analysis mode: one open clip, decoded on this serial queue (only touched from it).
  private let frames = DispatchQueue(label: "shuttle_live.video_frames")
  private var reader: VideoFrameReader?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerVideoFrames(engineBridge.pluginRegistry.registrar(forPlugin: "VideoFrames")!.messenger())
  }

  /// Channel `shuttle_live/video_frames`: open / next / close, replies on the main queue.
  private func registerVideoFrames(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "shuttle_live/video_frames", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.frames.async {
        var reply: Any?
        switch call.method {
        case "open":
          self?.reader = nil
          let path = (call.arguments as? [String: Any])?["path"] as? String ?? ""
          do {
            let reader = try VideoFrameReader(url: URL(fileURLWithPath: path))
            self?.reader = reader
            var clip: [String: Any] = ["durationUs": reader.durationUs, "width": reader.width, "height": reader.height]
            if let sound = reader.sound {
              clip["sound"] = FlutterStandardTypedData(float32: sound.withUnsafeBufferPointer { Data(buffer: $0) })
            }
            reply = clip
          } catch {
            reply = FlutterError(code: "unreadable", message: "\(error)", details: nil)
          }
        case "next":
          if let frame = self?.reader?.next() {
            reply = [
              "jpeg": FlutterStandardTypedData(bytes: frame.jpeg), "timeUs": frame.timeUs,
              "thumb": FlutterStandardTypedData(bytes: frame.thumb),
            ]
          }
        case "close":
          self?.reader = nil
        default:
          reply = FlutterMethodNotImplemented
        }
        DispatchQueue.main.async { result(reply) }
      }
    }
  }
}
