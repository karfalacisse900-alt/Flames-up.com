import SwiftUI
import UIKit

enum CaptroNoteAsset: String, CaseIterable {
  case paperCotton = "captro_paper_cotton"
  case paperNotebook = "captro_paper_notebook"
  case paperKraft = "captro_paper_kraft"
  case paperBlue = "captro_paper_blue"

  case tornIvory = "captro_prop_torn_ivory"
  case linedSheet = "captro_prop_lined_sheet"
  case warmTape = "captro_prop_warm_tape"
  case coolTape = "captro_prop_cool_tape"
  case lavenderPen = "captro_prop_lavender_pen"
  case silverPaperclip = "captro_prop_silver_paperclip"
  case brassPushpin = "captro_prop_brass_pushpin"
  case vintageTicket = "captro_prop_vintage_ticket"
  case pressedWildflower = "captro_prop_pressed_wildflower"

  case vintageRose = "captro_decor_vintage_rose"
  case carnationBouquet = "captro_decor_carnation_bouquet"
  case pinkRose = "captro_decor_pink_rose"
  case purpleBud = "captro_decor_purple_bud"
  case tapedBotanicals = "captro_decor_taped_botanicals"
  case pressedScatter = "captro_decor_pressed_scatter"
  case tapedYellowSprig = "captro_decor_taped_yellow_sprig"
  case tapedEucalyptus = "captro_decor_taped_eucalyptus"
  case tapedBrownBloom = "captro_decor_taped_brown_bloom"
  case tapedBillyButton = "captro_decor_taped_billy_button"
  case tapedDryBranch = "captro_decor_taped_dry_branch"
  case ivoryHydrangea = "captro_decor_ivory_hydrangea"
  case ivoryDaisy = "captro_decor_ivory_daisy"
  case ivoryPompom = "captro_decor_ivory_pompom"
  case ivoryAirySprig = "captro_decor_ivory_airy_sprig"
  case driedSprig = "captro_decor_dried_sprig"
  case pinkBabysBreath = "captro_decor_pink_babys_breath"
  case whiteGerbera = "captro_decor_white_gerbera"
  case magentaDaisy = "captro_decor_magenta_daisy"
  case tangerineDaisy = "captro_decor_tangerine_daisy"
  case sunshineDaisy = "captro_decor_sunshine_daisy"
  case limeDaisy = "captro_decor_lime_daisy"
  case cyanDaisy = "captro_decor_cyan_daisy"
  case violetDaisy = "captro_decor_violet_daisy"
  case impastoBlossom = "captro_decor_impasto_blossom"
  case peachRibbonRose = "captro_decor_peach_ribbon_rose"
  case berryRibbonRose = "captro_decor_berry_ribbon_rose"

  case mountainLake = "captro_demo_mountain_lake"
  case editorialPortrait = "captro_demo_editorial_portrait"
  case creamFlower = "captro_demo_cream_flower"
  case venueNight = "captro_demo_venue_night"
  case blueTelephone = "captro_demo_blue_telephone"
  case oceanShore = "captro_demo_ocean_shore"

  static func resolve(_ token: String?) -> Self? {
    guard let token else { return nil }
    return Self(rawValue: token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }

  var atlasName: String {
    switch self {
    case .paperCotton, .paperNotebook, .paperKraft, .paperBlue:
      return "CaptroNotePaperAtlas"
    case .tornIvory, .linedSheet, .warmTape, .coolTape, .lavenderPen,
         .silverPaperclip, .brassPushpin, .vintageTicket, .pressedWildflower:
      return "CaptroNotePropsAtlas"
    case .mountainLake, .editorialPortrait, .creamFlower, .venueNight,
         .blueTelephone, .oceanShore:
      return "CaptroNotePhotoAtlas"
    case .vintageRose, .carnationBouquet, .pinkRose, .purpleBud,
         .tapedBotanicals, .pressedScatter,
         .tapedYellowSprig, .tapedEucalyptus, .tapedBrownBloom,
         .tapedBillyButton, .tapedDryBranch, .ivoryHydrangea,
         .ivoryDaisy, .ivoryPompom, .ivoryAirySprig, .driedSprig,
         .pinkBabysBreath, .whiteGerbera, .magentaDaisy,
         .tangerineDaisy, .sunshineDaisy, .limeDaisy, .cyanDaisy,
         .violetDaisy, .impastoBlossom, .peachRibbonRose,
         .berryRibbonRose:
      return rawValue
    }
  }

  fileprivate var isDirectImage: Bool {
    switch self {
    case .vintageRose, .carnationBouquet, .pinkRose, .purpleBud,
         .tapedBotanicals, .pressedScatter,
         .tapedYellowSprig, .tapedEucalyptus, .tapedBrownBloom,
         .tapedBillyButton, .tapedDryBranch, .ivoryHydrangea,
         .ivoryDaisy, .ivoryPompom, .ivoryAirySprig, .driedSprig,
         .pinkBabysBreath, .whiteGerbera, .magentaDaisy,
         .tangerineDaisy, .sunshineDaisy, .limeDaisy, .cyanDaisy,
         .violetDaisy, .impastoBlossom, .peachRibbonRose,
         .berryRibbonRose:
      return true
    default:
      return false
    }
  }

  fileprivate var atlasGrid: (columns: Int, rows: Int, column: Int, row: Int) {
    switch self {
    case .paperCotton: return (2, 2, 0, 0)
    case .paperNotebook: return (2, 2, 1, 0)
    case .paperKraft: return (2, 2, 0, 1)
    case .paperBlue: return (2, 2, 1, 1)

    case .tornIvory: return (3, 3, 0, 0)
    case .linedSheet: return (3, 3, 1, 0)
    case .warmTape: return (3, 3, 2, 0)
    case .coolTape: return (3, 3, 0, 1)
    case .lavenderPen: return (3, 3, 1, 1)
    case .silverPaperclip: return (3, 3, 2, 1)
    case .brassPushpin: return (3, 3, 0, 2)
    case .vintageTicket: return (3, 3, 1, 2)
    case .pressedWildflower: return (3, 3, 2, 2)

    case .mountainLake: return (3, 2, 0, 0)
    case .editorialPortrait: return (3, 2, 1, 0)
    case .creamFlower: return (3, 2, 2, 0)
    case .venueNight: return (3, 2, 0, 1)
    case .blueTelephone: return (3, 2, 1, 1)
    case .oceanShore: return (3, 2, 2, 1)

    case .vintageRose, .carnationBouquet, .pinkRose, .purpleBud,
         .tapedBotanicals, .pressedScatter,
         .tapedYellowSprig, .tapedEucalyptus, .tapedBrownBloom,
         .tapedBillyButton, .tapedDryBranch, .ivoryHydrangea,
         .ivoryDaisy, .ivoryPompom, .ivoryAirySprig, .driedSprig,
         .pinkBabysBreath, .whiteGerbera, .magentaDaisy,
         .tangerineDaisy, .sunshineDaisy, .limeDaisy, .cyanDaisy,
         .violetDaisy, .impastoBlossom, .peachRibbonRose,
         .berryRibbonRose:
      return (1, 1, 0, 0)
    }
  }

  /// Insets are local to a single atlas cell and remove unused transparent
  /// space without trimming the natural object shadow.
  fileprivate var localContentRect: CGRect {
    switch self {
    case .tornIvory: return CGRect(x: 0.03, y: 0.12, width: 0.94, height: 0.76)
    case .linedSheet: return CGRect(x: 0.18, y: 0.02, width: 0.64, height: 0.96)
    case .warmTape, .coolTape: return CGRect(x: 0.03, y: 0.22, width: 0.94, height: 0.56)
    case .lavenderPen: return CGRect(x: 0.23, y: 0.01, width: 0.54, height: 0.98)
    case .silverPaperclip: return CGRect(x: 0.25, y: 0.05, width: 0.67, height: 0.90)
    case .brassPushpin: return CGRect(x: 0.08, y: 0.12, width: 0.84, height: 0.76)
    case .vintageTicket: return CGRect(x: 0.04, y: 0.20, width: 0.92, height: 0.60)
    case .pressedWildflower: return CGRect(x: 0.10, y: 0.01, width: 0.87, height: 0.98)
    default: return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
  }
}

struct CaptroNoteAssetView: View {
  let asset: CaptroNoteAsset
  var contentMode: ContentMode = .fit

  var body: some View {
    Group {
      if let image = CaptroNoteAssetImageStore.image(for: asset) {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
      } else {
        Color.clear
      }
    }
    .accessibilityHidden(true)
  }
}

enum CaptroNoteAssetImageStore {
  private static let cache = NSCache<NSString, UIImage>()

  static func image(for asset: CaptroNoteAsset) -> UIImage? {
    let key = asset.rawValue as NSString
    if let cached = cache.object(forKey: key) { return cached }
    if asset.isDirectImage {
      guard let image = UIImage(named: asset.rawValue, in: .main, compatibleWith: nil) else {
        return nil
      }
      cache.setObject(image, forKey: key)
      return image
    }
    guard
      let atlas = UIImage(named: asset.atlasName, in: .main, compatibleWith: nil),
      let source = atlas.cgImage
    else {
      return nil
    }

    let grid = asset.atlasGrid
    let cell = CGRect(
      x: CGFloat(grid.column) / CGFloat(grid.columns),
      y: CGFloat(grid.row) / CGFloat(grid.rows),
      width: 1 / CGFloat(grid.columns),
      height: 1 / CGFloat(grid.rows)
    )
    let local = asset.localContentRect
    let normalized = CGRect(
      x: cell.minX + local.minX * cell.width,
      y: cell.minY + local.minY * cell.height,
      width: local.width * cell.width,
      height: local.height * cell.height
    )
    let pixelRect = CGRect(
      x: normalized.minX * CGFloat(source.width),
      y: normalized.minY * CGFloat(source.height),
      width: normalized.width * CGFloat(source.width),
      height: normalized.height * CGFloat(source.height)
    ).integral
    guard let cropped = source.cropping(to: pixelRect) else { return nil }
    let image = UIImage(cgImage: cropped, scale: atlas.scale, orientation: atlas.imageOrientation)
    cache.setObject(image, forKey: key)
    return image
  }
}
