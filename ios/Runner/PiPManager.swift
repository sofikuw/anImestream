import Foundation
import AVKit
import AVFoundation

/// Manages YouTube-style Picture-in-Picture on iOS for Animestream.
/// Uses Apple's AVPictureInPictureController with automatic inline support on iOS 15+.
class PiPManager: NSObject, AVPictureInPictureControllerDelegate {
  static let shared = PiPManager()

  private var pipController: AVPictureInPictureController?
  private var playerLayer: AVPlayerLayer?

  var isPipActive: Bool = false
  var onPipStateChanged: ((Bool) -> Void)?

  private override init() {
    super.init()
  }

  /// Attach the native player layer to enable PiP
  func setup(with playerLayer: AVPlayerLayer) {
    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      print("Animestream PiP: Picture-in-Picture is not supported on this device.")
      return
    }

    self.playerLayer = playerLayer
    self.pipController = AVPictureInPictureController(playerLayer: playerLayer)
    self.pipController?.delegate = self

    // YouTube-style auto PiP: Automatically transitions to PiP when the user swipes to home or switches apps!
    if #available(iOS 15.0, *) {
      self.pipController?.canStartPictureInPictureAutomaticallyFromInline = true
      print("Animestream PiP: canStartPictureInPictureAutomaticallyFromInline enabled (iOS 15+).")
    }
  }

  /// Toggle automatic PiP on iOS 15+
  func setAutoPipEnabled(_ enabled: Bool) {
    if #available(iOS 15.0, *) {
      self.pipController?.canStartPictureInPictureAutomaticallyFromInline = enabled
    }
  }

  /// Manually start Picture-in-Picture
  func startPictureInPicture(completion: @escaping (Bool) -> Void) {
    guard let pipController = pipController, pipController.isPictureInPicturePossible else {
      completion(false)
      return
    }

    pipController.startPictureInPicture()
    completion(true)
  }

  /// Manually stop Picture-in-Picture
  func stopPictureInPicture(completion: @escaping (Bool) -> Void) {
    guard let pipController = pipController, pipController.isPictureInPictureActive else {
      completion(false)
      return
    }

    pipController.stopPictureInPicture()
    completion(true)
  }

  // MARK: - AVPictureInPictureControllerDelegate

  func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    isPipActive = true
    onPipStateChanged?(true)
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    isPipActive = true
    onPipStateChanged?(true)
  }

  func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    isPipActive = false
    onPipStateChanged?(false)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    isPipActive = false
    onPipStateChanged?(false)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    // Restores Animestream UI when the user taps the restore icon in the PiP window
    completionHandler(true)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    print("Animestream PiP Error: \(error.localizedDescription)")
    isPipActive = false
    onPipStateChanged?(false)
  }
}
