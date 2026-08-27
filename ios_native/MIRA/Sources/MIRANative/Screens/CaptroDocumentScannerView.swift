import SwiftUI
import VisionKit

struct CaptroDocumentScannerView: UIViewControllerRepresentable {
  let completion: (Result<[Data], Error>) -> Void
  let cancellation: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(completion: completion, cancellation: cancellation)
  }

  func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
    let controller = VNDocumentCameraViewController()
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(
    _ uiViewController: VNDocumentCameraViewController,
    context: Context
  ) {}

  final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    private let completion: (Result<[Data], Error>) -> Void
    private let cancellation: () -> Void

    init(
      completion: @escaping (Result<[Data], Error>) -> Void,
      cancellation: @escaping () -> Void
    ) {
      self.completion = completion
      self.cancellation = cancellation
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFinishWith scan: VNDocumentCameraScan
    ) {
      var pages: [Data] = []
      pages.reserveCapacity(scan.pageCount)
      for index in 0..<scan.pageCount {
        guard let data = scan.imageOfPage(at: index).jpegData(compressionQuality: 0.92) else {
          completion(.failure(CaptroLocalDocumentError.corrupt))
          controller.dismiss(animated: true)
          return
        }
        pages.append(data)
      }
      completion(.success(pages))
      controller.dismiss(animated: true)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
      cancellation()
      controller.dismiss(animated: true)
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFailWithError error: Error
    ) {
      completion(.failure(error))
      controller.dismiss(animated: true)
    }
  }
}
