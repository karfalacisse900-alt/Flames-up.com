import SwiftUI

/// Read-only historic receipt originals remain available after Capture's scanner retirement.
struct CaptroLocalDocumentViewer: View {
  let document: CaptroLocalDocument
  @Environment(\.dismiss) private var dismiss
  @State private var scale: CGFloat = 1
  @State private var baseScale: CGFloat = 1

  var body: some View {
    NavigationStack {
      Group {
        if document.mediaType == "application/pdf", let data = document.pages.first {
          CaptroPDFOriginal(data: data)
        } else {
          ScrollView([.horizontal, .vertical]) {
            Group {
              if let image = document.firstPageImage {
                Image(uiImage: image).resizable().scaledToFit().scaleEffect(scale)
              } else {
                Image(systemName: "doc.richtext").font(.system(size: 58, weight: .ultraLight)).foregroundStyle(.secondary)
              }
            }
            .frame(maxWidth: .infinity, minHeight: 620).padding(20)
            .gesture(MagnifyGesture()
              .onChanged { scale = min(max(baseScale * $0.magnification, 1), 5) }
              .onEnded { _ in baseScale = scale })
          }
        }
      }
      .background(Color(red: 0.988, green: 0.988, blue: 0.982))
      .navigationTitle("Original document")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }
  }
}
