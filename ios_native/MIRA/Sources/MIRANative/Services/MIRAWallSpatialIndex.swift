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

public struct MIRAWallSpatialIndex {
  private struct Cell: Hashable {
    let x: Int
    let y: Int
  }

  private let cellSize: CGFloat
  private var cells: [Cell: [MIRAWallNote]] = [:]

  public init(notes: [MIRAWallNote] = [], cellSize: CGFloat = 384) {
    self.cellSize = max(96, cellSize)
    rebuild(with: notes)
  }

  public mutating func rebuild(with notes: [MIRAWallNote]) {
    cells.removeAll(keepingCapacity: true)
    for note in notes {
      for cell in coveredCells(for: worldRect(for: note)) {
        cells[cell, default: []].append(note)
      }
    }
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
    CGRect(x: note.worldX, y: note.worldY, width: note.width, height: note.height)
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
