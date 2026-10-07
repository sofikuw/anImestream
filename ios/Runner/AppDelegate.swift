import UIKit
import Flutter
import AVKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var pipChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure AVAudioSession for background audio and PiP playback (like YouTube)
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .moviePlayback,
        options: [.mixWithOthers, .allowAirPlay]
      )
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Animestream iOS PiP: Failed to configure AVAudioSession: \(error.localizedDescription)")
    }

    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    pipChannel = FlutterMethodChannel(name: "com.animestream/pip", binaryMessenger: controller.binaryMessenger)
    
    // Register MethodChannel handlers for Dart communication
    pipChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      
      switch call.method {
      case "isPipSupported":
        let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
        result(isSupported)

      case "enableAutoPip":
        if let args = call.arguments as? [String: Any],
           let enable = args["enable"] as? Bool {
          PiPManager.shared.setAutoPipEnabled(enable)
          result(true)
        } else {
          result(false)
        }

      case "startPip":
        PiPManager.shared.startPictureInPicture { success in
          result(success)
        }

      case "stopPip":
        PiPManager.shared.stopPictureInPicture { success in
          result(success)
        }

      case "isPipActive":
        result(PiPManager.shared.isPipActive)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Set callback listener to notify Dart when PiP state changes
    PiPManager.shared.onPipStateChanged = { [weak self] isActive in
      self?.pipChannel?.invokeMethod("onPipStateChanged", arguments: ["isActive": isActive])
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
