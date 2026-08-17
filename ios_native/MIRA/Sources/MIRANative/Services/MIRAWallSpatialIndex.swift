import CoreGraphics
import Foundation

public struct MIRAWallCamera: Equatable {
  public var center: CGPoint
  public var scale: CGFloat

  public init(center: CGPoint = .zero, scale: CGFloat = 0.78) {
    self.center = center
    self.scale = scale
  }

  public func screenPoint(forWorld point: CGPoint, viewport: CGSize) -> CGPoint {
    CGPoint(
      x: viewport.width * 0.5 + (point.x - center.x) * scale,
      y: viewport.height * 0.5 + (point.y - center.y) * scale
    )
  }

  public func worldPoint(forScreen point: CGPoint, viewport: CGSize) -> CGPoint {
    CGPoint(
      x: center.x + (point.x - viewport.width * 0.5) / max(scale, 0.001),
      y: center.y + (point.y - viewport.height * 0.5) / max(scale, 0.001)
    )
  }

  public func worldBounds(viewport: CGSize, preload: CGFloat = 0) -> CGRect {
    let halfWidth = viewport.width / max(scale, 0.001) * 0.5 + preload
    let halfHeight = viewport.height / max(scale, 0.001) * 0.5 + preload
    return CGRect(x: center.x - halfWidth, y: center.y - halfHeight, width: halfWidth * 2, height: halfHeight * 2)
  }

  public func zoomed(to newScale: CGFloat, around screenPoint: CGPoint, viewport: CGSize) -> MIRAWallCamera {
    let clampedScale = min(max(newScale, 0.20), 2.50)
    let anchoredWorldPoint = worldPoint(forScreen: screenPoint, viewport: viewport)
    let nextCenter = CGPoint(
      x: anchoredWorldPoint.x - (screenPoint.x - viewport.width * 0.5) / clampedScale,
      y: anchoredWorldPoint.y - (screenPoint.y - viewport.height * 0.5) / clampedScale
    )
    return MIRAWallCamera(center: nextCenter, scale: clampedScale)
  }
}

public enum MIRAWallLayout {
  public static func startSignRect(noteBounds: CGRect?, noteCount: Int) -> CGRect {
    guard noteCount > 0, let noteBounds else {
      return CGRect(x: -145, y: -105, width: 290, height: 210)
    }
    let signSize = CGSize(width: 278, height: 196)
    return CGRect(
      x: noteBounds.midX - signSize.width * 0.5,
      y: noteBounds.maxY + 28,
      width: signSize.width,
      height: signSize.height
    )
  }

  public static func initialCamera(
    noteBounds: CGRect?,
    noteCount: Int,
    viewport: CGSize,
    includeStartSign: Bool
  ) -> MIRAWallCamera {
    var content = noteBounds ?? CGRect(x: -110, y: -90, width: 220, height: 180)
    if includeStartSign {
      content = content.union(startSignRect(noteBounds: noteBounds, noteCount: noteCount))
    }
    let horizontalSpace = max(220, viewport.width - 34)
    let verticalSpace = max(300, viewport.height - 220)
    let fitScale = min(horizontalSpace / max(content.width, 1), verticalSpace / max(content.height, 1))
    let range: ClosedRange<CGFloat>
    switch noteCount {
    case 0: range = 0.78...1.02
    case 1...3: range = 0.62...1.02
    case 4...12: range = 0.52...0.92
    default: range = 0.38...0.68
    }
    let scale = min(max(fitScale * 0.92, range.lowerBound), range.upperBound)
    return MIRAWallCamera(center: CGPoint(x: content.midX, y: content.midY), scale: scale)
  }

  public static func collageCamera(
    noteBounds: CGRect?,
    noteCount: Int,
    viewport: CGSize,
    includeStartSign: Bool
  ) -> MIRAWallCamera {
    var content = noteBounds ?? CGRect(x: -145, y: 0, width: 290, height: 210)
    if includeStartSign {
      content = content.union(startSignRect(noteBounds: noteBounds, noteCount: noteCount))
    }

    let horizontalSpace = max(220, viewport.width - 18)
    let widthScale = horizontalSpace / max(content.width, 1)
    let scale = min(max(widthScale, 0.38), noteCount <= 4 ? 0.86 : 0.62)
    let visibleWorldHeight = viewport.height / max(scale, 0.001)
    let centerY = content.height <= visibleWorldHeight
      ? content.midY
      : content.minY - 18 + visibleWorldHeight * 0.5

    return MIRAWallCamera(
      center: CGPoint(x: content.midX, y: centerY),
      scale: scale
    )
  }
}

public struct MIRAWallSpatialIndex {
  private struct Cell: Hashable {
    let x: Int
    let y: Int
  }

  private let cellSize: CGFloat
  private var cells: [Cell: [MIRAWallNote]] = [:]
  private var frameOverrides: [String: CGRect] = [:]

  public init(notes: [MIRAWallNote] = [], cellSize: CGFloat = 384) {
    self.cellSize = max(96, cellSize)
    rebuild(with: notes)
  }

  public mutating func rebuild(
    with notes: [MIRAWallNote],
    frameOverrides: [String: CGRect] = [:]
  ) {
    self.frameOverrides = frameOverrides
    cells.removeAll(keepingCapacity: true)
    for note in notes {
      for cell in coveredCells(for: worldRect(for: note)) {
        cells[cell, default: []].append(note)
      }
    }
  }

  @discardableResult
  public mutating func replace(_ note: MIRAWallNote) -> Bool {
    var replaced = false
    for cell in coveredCells(for: worldRect(for: note)) {
      guard var notes = cells[cell],
            let index = notes.firstIndex(where: { $0.id == note.id })
      else { continue }
      notes[index] = note
      cells[cell] = notes
      replaced = true
    }
    return replaced
  }

  public func notes(in bounds: CGRect) -> [MIRAWallNote] {
    var seen = Set<String>()
    var result: [MIRAWallNote] = []
    for cell in coveredCells(for: bounds) {
      for note in cells[cell] ?? [] where seen.insert(note.id).inserted {
        if worldRect(for: note).intersects(bounds) { result.append(note) }
      }
    }
    return result.sorted { left, right in
      left.zIndex == right.zIndex ? left.createdAt < right.createdAt : left.zIndex < right.zIndex
    }
  }

  public func note(at point: CGPoint) -> MIRAWallNote? {
    let cell = Cell(x: Int(floor(point.x / cellSize)), y: Int(floor(point.y / cellSize)))
    return (cells[cell] ?? [])
      .filter { worldRect(for: $0).insetBy(dx: -6, dy: -6).contains(point) }
      .max { left, right in left.zIndex < right.zIndex }
  }

  public func worldRect(for note: MIRAWallNote) -> CGRect {
    frameOverrides[note.id] ?? MIRAWallNotePresentationResolver.wallFrame(for: note)
  }

  private func coveredCells(for rect: CGRect) -> [Cell] {
    guard !rect.isNull, !rect.isInfinite else { return [] }
    let minX = Int(floor(rect.minX / cellSize))
    let maxX = Int(floor(rect.maxX / cellSize))
    let minY = Int(floor(rect.minY / cellSize))
    let maxY = Int(floor(rect.maxY / cellSize))
    var result: [Cell] = []
    result.reserveCapacity(max(1, (maxX - minX + 1) * (maxY - minY + 1)))
    for y in minY...maxY {
      for x in minX...maxX { result.append(Cell(x: x, y: y)) }
    }
    return result
  }
}

public enum MIRAWallReadableLayout {
  public static func frames(for notes: [MIRAWallNote]) -> [String: CGRect] {
    guard !notes.isEmpty else { return [:] }

    let columnCount = 3
    let columnWidth: CGFloat = 242
    let gutter: CGFloat = 9
    let boardWidth = columnWidth * CGFloat(columnCount) + gutter * CGFloat(columnCount - 1)
    let boardOriginX = -boardWidth * 0.5
    let ordered = notes.sorted { left, right in
      if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
      if left.zIndex != right.zIndex { return left.zIndex > right.zIndex }
      return left.id < right.id
    }
    var columnBottoms = Array(repeating: CGFloat.zero, count: columnCount)
    var result: [String: CGRect] = [:]
    result.reserveCapacity(ordered.count)

    for (index, note) in ordered.enumerated() {
      let presentation = MIRAWallNotePresentationResolver.resolve(note)
      let aspect = max(0.32, min(1.9, presentation.size.width / max(presentation.size.height, 1)))
      let shouldFeature = index.isMultiple(of: 9) && aspect >= 1.05
      let span = aspect >= 1.34 || shouldFeature ? 2 : 1
      let candidates = 0...(columnCount - span)
      let column = candidates.min { left, right in
        let leftBottom = columnBottoms[left..<(left + span)].max() ?? 0
        let rightBottom = columnBottoms[right..<(right + span)].max() ?? 0
        if abs(leftBottom - rightBottom) > 0.5 { return leftBottom < rightBottom }
        return left < right
      } ?? 0
      let top = columnBottoms[column..<(column + span)].max() ?? 0
      let width = columnWidth * CGFloat(span) + gutter * CGFloat(span - 1)
      let height = width / aspect
      let frame = CGRect(
        x: boardOriginX + CGFloat(column) * (columnWidth + gutter),
        y: top,
        width: width,
        height: height
      )
      result[note.id] = frame
      for occupiedColumn in column..<(column + span) {
        columnBottoms[occupiedColumn] = frame.maxY + gutter
      }
    }

    return result
  }
}
