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
    if noteBounds.width < 430 {
      return CGRect(
        x: noteBounds.maxX + 46,
        y: noteBounds.midY - signSize.height * 0.52,
        width: signSize.width,
        height: signSize.height
      )
    }
    return CGRect(
      x: noteBounds.minX + 24,
      y: noteBounds.maxY + 42,
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
    case 4...12: range = 0.46...0.88
    default: range = 0.28...0.58
    }
    let scale = min(max(fitScale * 0.92, range.lowerBound), range.upperBound)
    return MIRAWallCamera(center: CGPoint(x: content.midX, y: content.midY), scale: scale)
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
  private struct Cell: Hashable {
    let x: Int
    let y: Int
  }

  private struct PlacedNote {
    let frame: CGRect
    let readableFrame: CGRect
  }

  private struct CandidateScore {
    let valid: Bool
    let value: CGFloat
  }

  public static func frames(
    for notes: [MIRAWallNote],
    cellSize: CGFloat = 360
  ) -> [String: CGRect] {
    guard !notes.isEmpty else { return [:] }

    let safeCellSize = max(180, cellSize)
    let ordered = notes.sorted { left, right in
      if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
      if left.zIndex != right.zIndex { return left.zIndex < right.zIndex }
      return left.id < right.id
    }
    var placed: [PlacedNote] = []
    placed.reserveCapacity(ordered.count)
    var cells: [Cell: [Int]] = [:]
    var result: [String: CGRect] = [:]
    result.reserveCapacity(ordered.count)

    for note in ordered {
      let desired = MIRAWallNotePresentationResolver.wallFrame(for: note)
      let phase = CGFloat(MIRAWallNotePresentationResolver.stableHash(note.id) % 360)
        * .pi / 180
      var chosen = desired
      var best = desired
      var bestScore = candidateScore(
        desired,
        desired: desired,
        neighbors: neighborIndices(for: desired, cells: cells, cellSize: safeCellSize),
        placed: placed
      )

      if !bestScore.valid {
        search: for ring in 1...14 {
          let step = max(30, min(44, min(desired.width, desired.height) * 0.17))
          let radius = CGFloat(ring) * step
          let slots = ring < 4 ? 10 : 14
          for slot in 0..<slots {
            let angle = phase + CGFloat(slot) * 2 * .pi / CGFloat(slots)
            let candidate = desired.offsetBy(
              dx: cos(angle) * radius,
              dy: sin(angle) * radius
            )
            let score = candidateScore(
              candidate,
              desired: desired,
              neighbors: neighborIndices(for: candidate, cells: cells, cellSize: safeCellSize),
              placed: placed
            )
            if score.value < bestScore.value {
              best = candidate
              bestScore = score
            }
            if score.valid {
              chosen = candidate
              break search
            }
          }
        }
        if !bestScore.valid {
          chosen = best
        }
      }

      let placedNote = PlacedNote(
        frame: chosen,
        readableFrame: readableFrame(for: chosen)
      )
      let index = placed.count
      placed.append(placedNote)
      for cell in coveredCells(for: chosen.insetBy(dx: -10, dy: -10), cellSize: safeCellSize) {
        cells[cell, default: []].append(index)
      }
      result[note.id] = chosen
    }

    return result
  }

  private static func candidateScore(
    _ candidate: CGRect,
    desired: CGRect,
    neighbors: [Int],
    placed: [PlacedNote]
  ) -> CandidateScore {
    let readable = readableFrame(for: candidate)
    var fullOverlap: CGFloat = 0
    var readableOverlap: CGFloat = 0
    var valid = true

    for index in neighbors {
      guard placed.indices.contains(index) else { continue }
      let other = placed[index]
      let overlap = intersectionArea(candidate, other.frame)
      let protectedOverlap = intersectionArea(readable, other.readableFrame)
      fullOverlap += overlap
      readableOverlap += protectedOverlap

      let smallerArea = max(
        1,
        min(candidate.width * candidate.height, other.frame.width * other.frame.height)
      )
      if overlap / smallerArea > 0.16 || protectedOverlap > 1 {
        valid = false
      }
    }

    let displacement = hypot(candidate.midX - desired.midX, candidate.midY - desired.midY)
    return CandidateScore(
      valid: valid,
      value: displacement + fullOverlap * 2.8 + readableOverlap * 40
    )
  }

  private static func readableFrame(for frame: CGRect) -> CGRect {
    frame.insetBy(
      dx: max(10, frame.width * 0.07),
      dy: max(12, frame.height * 0.08)
    )
  }

  private static func intersectionArea(_ left: CGRect, _ right: CGRect) -> CGFloat {
    let intersection = left.intersection(right)
    guard !intersection.isNull, !intersection.isEmpty else { return 0 }
    return intersection.width * intersection.height
  }

  private static func neighborIndices(
    for frame: CGRect,
    cells: [Cell: [Int]],
    cellSize: CGFloat
  ) -> [Int] {
    var seen = Set<Int>()
    var result: [Int] = []
    for cell in coveredCells(for: frame.insetBy(dx: -12, dy: -12), cellSize: cellSize) {
      for index in cells[cell] ?? [] where seen.insert(index).inserted {
        result.append(index)
      }
    }
    return result
  }

  private static func coveredCells(for rect: CGRect, cellSize: CGFloat) -> [Cell] {
    guard !rect.isNull, !rect.isInfinite else { return [] }
    let minX = Int(floor(rect.minX / cellSize))
    let maxX = Int(floor(rect.maxX / cellSize))
    let minY = Int(floor(rect.minY / cellSize))
    let maxY = Int(floor(rect.maxY / cellSize))
    var result: [Cell] = []
    result.reserveCapacity(max(1, (maxX - minX + 1) * (maxY - minY + 1)))
    for y in minY...maxY {
      for x in minX...maxX {
        result.append(Cell(x: x, y: y))
      }
    }
    return result
  }
}
