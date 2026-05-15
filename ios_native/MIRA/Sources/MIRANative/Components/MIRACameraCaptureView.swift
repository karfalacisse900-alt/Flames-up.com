import SwiftUI
import UIKit
import UniformTypeIdentifiers

public struct MIRACameraCaptureView: UIViewControllerRepresentable {
  public typealias UIViewControllerType = UIImagePickerController

  let allowsVideo: Bool
  let onCapture: (MIRAPickedMedia) -> Void

  @Environment(\.dismiss) private var dismiss

  public init(allowsVideo: Bool = true, onCapture: @escaping (MIRAPickedMedia) -> Void) {
    self.allowsVideo = allowsVideo
    self.onCapture = onCapture
  }

  public func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    picker.mediaTypes = allowsVideo ? [UTType.image.identifier, UTType.movie.identifier] : [UTType.image.identifier]
    picker.videoQuality = .typeHigh
    picker.delegate = context.coordinator
    return picker
  }

  public func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    private let parent: MIRACameraCaptureView

    init(parent: MIRACameraCaptureView) {
      self.parent = parent
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }

    public func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      defer { parent.dismiss() }

      if let videoURL = info[.mediaURL] as? URL,
         let data = try? Data(contentsOf: videoURL) {
        parent.onCapture(MIRAPickedMedia(data: data, kind: .video, fileName: "\(UUID().uuidString).mov", mimeType: "video/quicktime"))
        return
      }

      if let image = info[.originalImage] as? UIImage,
         let data = image.jpegData(compressionQuality: 0.9) {
        parent.onCapture(MIRAPickedMedia(data: data, kind: .image, fileName: "\(UUID().uuidString).jpg", mimeType: "image/jpeg"))
      }
    }
  }
}
