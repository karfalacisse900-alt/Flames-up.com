import SwiftUI
import UIKit

@MainActor
public final class MIRAYearbookNativeModel: ObservableObject {
  @Published public private(set) var profiles: [MIRAYearbookProfile] = []
  @Published public private(set) var myProfile: MIRAYearbookProfile?
  @Published public private(set) var isLoading = false
  @Published public private(set) var isLoadingMore = false
  @Published public private(set) var hasMore = false
  @Published public private(set) var errorMessage: String?
  @Published public private(set) var datingUnavailable = false
  @Published public var selectedIntent: MIRAYearbookIntent?
  @Published public var searchText = ""
  @Published public var cityFilter = ""
  @Published public var languageFilter = ""
  @Published public var interestFilter = ""
  @Published public var ageMinimum = ""
  @Published public var ageMaximum = ""

  let api: MIRAAPIClient
  private var nextOffset = 0
  private var loadTask: Task<Void, Never>?

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  deinit {
    loadTask?.cancel()
  }

  public func prepare() async {
    async let browse: Void = reload()
    async let mine: Void = loadMyProfile()
    _ = await (browse, mine)
  }

  public func reload() async {
    loadTask?.cancel()
    let task = Task { [weak self] in
      guard let self else { return }
      isLoading = profiles.isEmpty
      errorMessage = nil
      defer { isLoading = false }
      do {
        let response: MIRAYearbookDiscoverResponse = try await api.get(discoverPath(offset: 0))
        guard !Task.isCancelled else { return }
        let uniqueProfiles = deduplicatedProfiles(response.profiles)
        profiles = uniqueProfiles
        hasMore = response.hasMore
        nextOffset = response.nextOffset
        datingUnavailable = response.datingUnavailable == true
        prefetchPortraits(uniqueProfiles)
      } catch is CancellationError {
        return
      } catch {
        if profiles.isEmpty { errorMessage = error.localizedDescription }
      }
    }
    loadTask = task
    await task.value
  }

  public func loadMoreIfNeeded(current profile: MIRAYearbookProfile) async {
    guard hasMore, !isLoadingMore, profiles.suffix(5).contains(where: { $0.id == profile.id }) else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let response: MIRAYearbookDiscoverResponse = try await api.get(discoverPath(offset: nextOffset))
      let known = Set(profiles.map(\.userId))
      let uniqueProfiles = deduplicatedProfiles(response.profiles).filter { !known.contains($0.userId) }
      profiles.append(contentsOf: uniqueProfiles)
      hasMore = response.hasMore
      nextOffset = response.nextOffset
      prefetchPortraits(uniqueProfiles)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func loadMyProfile() async {
    do {
      let response: MIRAYearbookProfileResponse = try await api.get("/yearbook/me")
      myProfile = response.profile
    } catch {
      if myProfile == nil { errorMessage = error.localizedDescription }
    }
  }

  public func profileSaved(_ profile: MIRAYearbookProfile) {
    myProfile = profile
    Task { await reload() }
  }

  private func discoverPath(offset: Int) -> String {
    var components = URLComponents()
    var items: [URLQueryItem] = [
      URLQueryItem(name: "limit", value: "24"),
      URLQueryItem(name: "offset", value: String(offset)),
    ]
    if let selectedIntent { items.append(URLQueryItem(name: "intent", value: selectedIntent.rawValue)) }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty { items.append(URLQueryItem(name: "query", value: query)) }
    let city = cityFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    if !city.isEmpty { items.append(URLQueryItem(name: "city", value: city)) }
    let language = languageFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    if !language.isEmpty { items.append(URLQueryItem(name: "language", value: language)) }
    let interest = interestFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    if !interest.isEmpty { items.append(URLQueryItem(name: "interest", value: interest)) }
    if let minimum = Int(ageMinimum), (16...120).contains(minimum) {
      items.append(URLQueryItem(name: "age_min", value: String(minimum)))
    }
    if let maximum = Int(ageMaximum), (16...120).contains(maximum) {
      items.append(URLQueryItem(name: "age_max", value: String(maximum)))
    }
    components.queryItems = items
    return "/yearbook/discover?\(components.percentEncodedQuery ?? "limit=24&offset=0")"
  }

  private func prefetchPortraits(_ profiles: [MIRAYearbookProfile]) {
    let urls = profiles.compactMap(\.profilePhoto)
    Task.detached(priority: .utility) {
      await MIRAImagePrefetcher.prefetch(urls: urls, maxPixelSize: 720, limit: 24)
    }
  }

  private func deduplicatedProfiles(_ incoming: [MIRAYearbookProfile]) -> [MIRAYearbookProfile] {
    var seenUserIDs = Set<String>()
    return incoming.filter { profile in
      let userID = profile.userId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !userID.isEmpty, !seenUserIDs.contains(userID) else { return false }
      seenUserIDs.insert(userID)
      return true
    }
  }
}

public struct MIRAYearbookNativeView: View {
  @StateObject private var model: MIRAYearbookNativeModel
  @State private var showFilters = false
  @State private var showEditor = false
  @State private var isSearchVisible = false
  @State private var searchDraft = ""
  @State private var selectedSpread: Int? = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let api: MIRAAPIClient
  private let currentUser: MIRAUser?

  public init(api: MIRAAPIClient, currentUser: MIRAUser?) {
    self.api = api
    self.currentUser = currentUser
    _model = StateObject(wrappedValue: MIRAYearbookNativeModel(api: api))
  }

  public var body: some View {
    ZStack {
      YearbookPaperBackground()
        .ignoresSafeArea()

      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      header
        .frame(maxHeight: .infinity, alignment: .top)
        .zIndex(20)
    }
    .navigationBarHidden(true)
    .task { await model.prepare() }
    .sheet(isPresented: $showFilters) {
      YearbookFilterSheet(
        selectedIntent: $model.selectedIntent,
        city: $model.cityFilter,
        language: $model.languageFilter,
        interest: $model.interestFilter,
        ageMinimum: $model.ageMinimum,
        ageMaximum: $model.ageMaximum
      ) {
        selectedSpread = 0
        Task { await model.reload() }
      }
      .presentationDetents([.fraction(0.88)])
      .presentationDragIndicator(.visible)
      .presentationCornerRadius(28)
      .presentationBackground {
        YearbookPageTexture(
          base: Color(red: 0.965, green: 0.945, blue: 0.895),
          ruled: false
        )
      }
    }
    .fullScreenCover(isPresented: $showEditor) {
      YearbookEditorView(api: api, currentUser: currentUser, existingProfile: model.myProfile) { profile in
        model.profileSaved(profile)
      }
    }
  }

  private var header: some View {
    Group {
      if isSearchVisible {
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(Color.black.opacity(0.52))
          TextField("Name, city, school, or interest", text: $searchDraft)
            .foregroundStyle(Color.black.opacity(0.84))
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .onSubmit {
              selectedSpread = 0
              model.searchText = searchDraft
              Task { await model.reload() }
            }
          Button {
            if searchDraft.isEmpty {
              withAnimation(.easeOut(duration: 0.18)) { isSearchVisible = false }
            } else {
              searchDraft = ""
              model.searchText = ""
              selectedSpread = 0
              Task { await model.reload() }
            }
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(Color.black.opacity(0.46))
          }
          .accessibilityLabel(searchDraft.isEmpty ? "Close search" : "Clear search")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(YearbookHeaderPaper())
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(alignment: .top) {
          YearbookTapeStrip(color: Color(red: 0.76, green: 0.66, blue: 0.49))
            .frame(width: 54, height: 14)
            .offset(y: -7)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if model.isLoading && model.profiles.isEmpty {
      YearbookSkeletonGrid()
    } else if let error = model.errorMessage, model.profiles.isEmpty {
      VStack(spacing: 4) {
        MIRAEmptyState(title: "The Yearbook could not open", message: error, systemImage: "book.closed")
        Button("Try again") { Task { await model.prepare() } }
          .buttonStyle(.borderedProminent)
          .tint(MIRATheme.Color.forest)
      }
      .padding(.bottom, 40)
    } else if model.profiles.isEmpty {
      MIRAEmptyState(
        title: model.datingUnavailable ? "Dating discovery is off" : "No pages here yet",
        message: model.datingUnavailable
          ? "Choose Dating on your own Yearbook page and confirm you are 18 or older before browsing dating profiles."
          : (model.selectedIntent == nil ? "Create your page, then check back as more people join." : "Try another Yearbook section or clear a filter."),
        systemImage: model.datingUnavailable ? "lock.heart" : "person.2.crop.square.stack"
      )
      .padding(.top, 38)
    } else {
      ScrollView(.horizontal) {
        LazyHStack(spacing: 0) {
          ForEach(Array(profileSpreads.enumerated()), id: \.offset) { index, profiles in
            YearbookOpenSpread(
              profiles: profiles,
              loadedProfileCount: model.profiles.count,
              pageNumber: index + 1,
              pageCount: profileSpreads.count,
              profilesPerLeaf: profilesPerLeaf,
              selectedIntent: model.selectedIntent,
              api: api,
              currentUserID: currentUser?.id ?? "",
              onSearch: {
                withAnimation(.easeOut(duration: 0.2)) { isSearchVisible.toggle() }
              },
              onFilter: { showFilters = true },
              onSelectIntent: { intent in
                selectedSpread = 0
                model.selectedIntent = intent
                Task { await model.reload() }
              },
              onEdit: { showEditor = true }
            )
            .containerRelativeFrame(.horizontal)
            .scrollTransition(axis: .horizontal) { content, phase in
              content
                .rotation3DEffect(
                  .degrees(reduceMotion ? 0 : phase.value * -3.2),
                  axis: (x: 0, y: 1, z: 0),
                  anchor: phase.value > 0 ? .leading : .trailing,
                  perspective: 0.28
                )
                .scaleEffect(reduceMotion ? 1 : 1 - abs(phase.value) * 0.012)
                .opacity(reduceMotion ? (phase.isIdentity ? 1 : 0.88) : 1)
            }
            .id(index)
            .task {
              if let last = profiles.last {
                await model.loadMoreIfNeeded(current: last)
              }
            }
          }
        }
        .scrollTargetLayout()
      }
      .scrollTargetBehavior(.paging)
      .scrollPosition(id: $selectedSpread)
      .scrollIndicators(.hidden)
      .scrollDisabled(profileSpreads.count <= 1)
      .padding(.horizontal, 2)
      .padding(.vertical, 2)
      .onChange(of: profileSpreads.count) { _, count in
        guard count > 0 else {
          selectedSpread = nil
          return
        }
        if let selectedSpread, selectedSpread >= count {
          self.selectedSpread = count - 1
        }
      }
      .overlay(alignment: .bottom) {
        if model.isLoadingMore {
          ProgressView()
            .tint(Color.black.opacity(0.64))
            .padding(.bottom, 44)
        }
      }
    }
  }

  private var profileSpreads: [[MIRAYearbookProfile]] {
    stride(from: 0, to: model.profiles.count, by: profilesPerSpread).map { start in
      let end = min(start + profilesPerSpread, model.profiles.count)
      return Array(model.profiles[start..<end])
    }
  }

  private var profilesPerLeaf: Int {
    2
  }

  private var profilesPerSpread: Int { profilesPerLeaf * 2 }
}

private struct YearbookOpenSpread: View {
  let profiles: [MIRAYearbookProfile]
  let loadedProfileCount: Int
  let pageNumber: Int
  let pageCount: Int
  let profilesPerLeaf: Int
  let selectedIntent: MIRAYearbookIntent?
  let api: MIRAAPIClient
  let currentUserID: String
  let onSearch: () -> Void
  let onFilter: () -> Void
  let onSelectIntent: (MIRAYearbookIntent?) -> Void
  let onEdit: () -> Void

  private let pageColor = Color(red: 0.955, green: 0.925, blue: 0.85)

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let outerInset = max(4.0, size.width * 0.012)
      let headerHeight = max(40.0, size.height * 0.068)
      let footerHeight = max(36.0, size.height * 0.058)
      let tabRailWidth = min(58.0, max(50.0, size.width * 0.135))

      ZStack {
        YearbookBookCoverSurface()
          .shadow(color: Color.black.opacity(0.58), radius: 24, y: 14)

        ForEach(0..<4, id: \.self) { layer in
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(red: 0.77, green: 0.71, blue: 0.59).opacity(0.96 - Double(layer) * 0.08))
            .padding(outerInset + CGFloat(layer) * 1.2)
            .offset(x: CGFloat(layer) * 0.45, y: 6 + CGFloat(layer) * 1.4)
            .allowsHitTesting(false)
        }

        VStack(spacing: 0) {
          HStack(spacing: 10) {
            Image(systemName: "chevron.left")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(Color.black.opacity(0.72))
              .accessibilityHidden(true)
            Spacer()
            Text("CAPTRO YEARBOOK")
              .font(.system(size: max(13, size.width * 0.038), weight: .bold, design: .serif))
              .tracking(0.7)
              .foregroundStyle(Color.black.opacity(0.82))
            Spacer()
            Button(action: onEdit) {
              Image(systemName: "heart")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(red: 0.72, green: 0.27, blue: 0.30))
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.miraPress)
            .accessibilityLabel("Edit my Yearbook page")
          }
          .padding(.horizontal, 14)
          .frame(height: headerHeight)
          .background(YearbookPageTexture(base: pageColor, ruled: false))

          HStack(spacing: 0) {
            pageLeaf(startIndex: 0, side: .left)
            YearbookCenterBinding()
              .frame(width: max(14, size.width * 0.042))
            pageLeaf(startIndex: profilesPerLeaf, side: .right)
          }
          .padding(.trailing, tabRailWidth - 7)

          HStack {
            Text("\(loadedProfileCount) \(loadedProfileCount == 1 ? "person" : "people")")
            Spacer()
            Text("Class of 2026")
              .font(.custom("Noteworthy-Bold", size: max(12, size.width * 0.036), relativeTo: .headline))
            Image(systemName: "heart")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(Color(red: 0.72, green: 0.31, blue: 0.34))
            Spacer()
            Text("\(pageNumber)/\(max(pageCount, 1))")
              .font(.system(size: 9, weight: .bold, design: .serif))
            Button(action: onSearch) {
              Image(systemName: "magnifyingglass")
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search Yearbook")
            Button(action: onFilter) {
              Image(systemName: "slider.horizontal.3")
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Yearbook filters")
          }
          .font(.system(size: max(10, size.width * 0.029), weight: .semibold, design: .serif))
          .foregroundStyle(Color.black.opacity(0.72))
          .padding(.horizontal, 11)
          .frame(height: footerHeight)
          .background(YearbookPageTexture(base: pageColor.opacity(0.98), ruled: false))
        }
        .padding(outerInset)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        bookTabs
          .frame(width: tabRailWidth)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.top, headerHeight + outerInset + 8)
          .padding(.bottom, footerHeight + outerInset + 10)
          .padding(.trailing, outerInset - 1)
      }
    }
    .accessibilityElement(children: .contain)
  }

  private enum PageSide { case left, right }

  private func pageLeaf(startIndex: Int, side: PageSide) -> some View {
    let pageShape = UnevenRoundedRectangle(
      topLeadingRadius: side == .left ? 10 : 1,
      bottomLeadingRadius: side == .left ? 10 : 1,
      bottomTrailingRadius: side == .right ? 10 : 1,
      topTrailingRadius: side == .right ? 10 : 1,
      style: .continuous
    )

    let availableProfiles = Array(profiles.dropFirst(startIndex).prefix(profilesPerLeaf))

    return GeometryReader { proxy in
      let verticalPadding = 10.0
      let cardSpacing = 8.0
      let columnCount = 1
      let rowCount = Int(ceil(Double(profilesPerLeaf) / Double(columnCount)))
      let totalSpacing = cardSpacing * CGFloat(max(rowCount - 1, 0))
      let cardHeight = max(108.0, (proxy.size.height - verticalPadding * 2 - totalSpacing) / CGFloat(rowCount))
      let columns = Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: cardSpacing, alignment: .top),
        count: columnCount
      )

      ZStack {
        YearbookPageTexture(base: pageColor, ruled: false)

        LinearGradient(
          colors: side == .left
            ? [Color.white.opacity(0.24), Color.clear, Color.black.opacity(0.15)]
            : [Color.black.opacity(0.15), Color.clear, Color.white.opacity(0.24)],
          startPoint: .leading,
          endPoint: .trailing
        )
        .allowsHitTesting(false)

        LazyVGrid(columns: columns, alignment: .leading, spacing: cardSpacing) {
          ForEach(0..<profilesPerLeaf, id: \.self) { slot in
            if slot < availableProfiles.count {
              let profile = availableProfiles[slot]
              let profileIndex = startIndex + slot
              NavigationLink {
                YearbookProfileDetailView(api: api, initialProfile: profile, currentUserID: currentUserID)
              } label: {
                YearbookPortraitCard(profile: profile, placement: profileIndex + (pageNumber * profilesPerSpread))
              }
              .buttonStyle(.miraPress)
              .frame(height: cardHeight)
              .accessibilityHint("Opens \(profile.name)'s complete Yearbook page")
            } else {
              YearbookEmptyPortraitSlot()
                .frame(height: cardHeight)
            }
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, verticalPadding)

        if side == .left {
          YearbookPageHoles()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 1)
            .allowsHitTesting(false)
        }
      }
      .clipShape(pageShape)
      .overlay {
        pageShape
          .stroke(Color.black.opacity(0.17), lineWidth: 0.8)
      }
      .overlay(alignment: side == .left ? .trailing : .leading) {
        LinearGradient(
          colors: side == .left
            ? [Color.clear, Color.black.opacity(0.20)]
            : [Color.black.opacity(0.20), Color.clear],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: 12)
        .allowsHitTesting(false)
      }
      .shadow(color: Color.black.opacity(0.24), radius: 5, x: side == .left ? -2 : 2, y: 3)
    }
  }

  private var bookTabs: some View {
    VStack(spacing: 4) {
      bookTab(title: "All", intent: nil, color: Color(red: 0.79, green: 0.48, blue: 0.49))
      bookTab(title: "Friends", intent: .friends, color: Color(red: 0.59, green: 0.70, blue: 0.52))
      bookTab(title: "Dating", intent: .dating, color: Color(red: 0.49, green: 0.61, blue: 0.76))
      bookTab(title: "Both", intent: .friendsAndDating, color: Color(red: 0.67, green: 0.56, blue: 0.74))
      bookTab(title: "Creative", intent: .creativeNetworking, color: Color(red: 0.86, green: 0.67, blue: 0.34))
      bookTab(title: "Browse", intent: .justBrowsing, color: Color(red: 0.76, green: 0.70, blue: 0.57))
    }
    .frame(maxHeight: .infinity, alignment: .center)
  }

  private func bookTab(title: String, intent: MIRAYearbookIntent?, color: Color) -> some View {
    let selected = selectedIntent == intent
    return Button {
      onSelectIntent(intent)
    } label: {
      Text(title)
        .font(.system(size: 9.5, weight: selected ? .bold : .semibold, design: .serif))
        .foregroundStyle(Color.black.opacity(0.78))
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(color.opacity(selected ? 1 : 0.82))
        .overlay(alignment: .leading) {
          Rectangle().fill(selected ? Color.black.opacity(0.35) : Color.clear).frame(width: 2)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 5, topTrailingRadius: 5))
        .shadow(color: Color.black.opacity(selected ? 0.22 : 0.12), radius: 2, x: 1, y: 1)
        .offset(x: selected ? -5 : 0)
        .animation(.snappy(duration: 0.24), value: selected)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Show \(title) pages")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private struct YearbookPortraitCard: View {
  let profile: MIRAYearbookProfile
  var placement = 0

  var body: some View {
    GeometryReader { proxy in
      let compact = proxy.size.height < 205
      let footerHeight = compact ? 44.0 : 52.0
      let imageHeight = max(82.0, proxy.size.height - footerHeight - 12)

      VStack(alignment: .leading, spacing: compact ? 2 : 3) {
        ZStack(alignment: .topTrailing) {
          MIRACachedImage(url: profile.profilePhoto, maxPixelSize: 640) { image in
            image.resizable().scaledToFill()
          } placeholder: {
            ZStack {
              MIRATheme.Color.mediaPlaceholderRaised
              Image(systemName: "person.crop.square")
                .font(.system(size: compact ? 27 : 34, weight: .light))
                .foregroundStyle(MIRATheme.Color.textMuted)
            }
          }
          .frame(maxWidth: .infinity)
          .frame(height: imageHeight)
          .clipShape(RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous)
              .stroke(photoBorderColor, lineWidth: photoBorderWidth)
          }
          .clipped()

        }

        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(profile.name)
            .font(.custom("Noteworthy-Bold", size: compact ? 14 : 17, relativeTo: .headline))
            .foregroundStyle(Color.black.opacity(0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.70)

          Spacer(minLength: 2)

          if let personalitySymbol {
            Image(systemName: personalitySymbol)
              .font(.system(size: compact ? 9 : 11, weight: .bold))
              .foregroundStyle(personalityColor)
          }
        }

        if profile.age != nil || !profile.locationLine.isEmpty {
          HStack(spacing: 4) {
            if let age = profile.age { Text("\(age)") }
            if profile.age != nil && !profile.locationLine.isEmpty { Text("·") }
            if !profile.locationLine.isEmpty { Text(profile.locationLine) }
          }
          .font(.system(size: compact ? 8.5 : 10, weight: .semibold, design: .serif))
          .foregroundStyle(Color.black.opacity(0.65))
          .lineLimit(1)
          .minimumScaleFactor(0.68)
        }

        Spacer(minLength: 0)
      }
      .padding(compact ? 5 : 6)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(YearbookPolaroidPaper())
      .clipShape(Rectangle())
      .overlay {
        Rectangle().stroke(Color.black.opacity(0.13), lineWidth: 0.7)
      }
      .overlay(alignment: .top) {
        if placement.isMultiple(of: 2) {
          YearbookTapeStrip(color: Color(red: 0.76, green: 0.67, blue: 0.49))
            .frame(width: 36, height: 13)
            .offset(y: -7)
        } else {
          YearbookPushpin(color: placement.isMultiple(of: 3) ? .green : .blue)
            .scaleEffect(0.78)
            .offset(y: -7)
        }
      }
      .rotationEffect(.degrees(stableYearbookRotation(profile.id, placement: placement)))
      .shadow(color: Color.black.opacity(0.18), radius: 3.5, x: 1, y: 2.5)
      .contentShape(Rectangle())
    }
  }

  private var personalitySelector: Int {
    let checksum = profile.userId.utf8.reduce(UInt64(max(placement, 0) + 1)) {
      ($0 &* 31) &+ UInt64($1)
    }
    return Int(checksum % 6)
  }

  private var personalitySymbol: String? {
    switch personalitySelector {
    case 2: return "camera.fill"
    case 3: return "music.note"
    case 4: return "cup.and.saucer.fill"
    case 5: return "sparkles"
    default: return nil
    }
  }

  private var personalityColor: Color {
    switch personalitySelector {
    case 2: return Color(red: 0.22, green: 0.37, blue: 0.55)
    case 3: return Color(red: 0.58, green: 0.26, blue: 0.38)
    case 4: return Color(red: 0.45, green: 0.29, blue: 0.18)
    default: return Color(red: 0.28, green: 0.42, blue: 0.22)
    }
  }

  private var photoCornerRadius: CGFloat {
    switch personalitySelector % 3 {
    case 1: return 3
    case 2: return 6
    default: return 0
    }
  }

  private var photoBorderColor: Color {
    personalitySelector == 3 ? Color.black.opacity(0.52) : Color.white.opacity(0.56)
  }

  private var photoBorderWidth: CGFloat {
    personalitySelector == 3 ? 2 : 1
  }
}

private struct YearbookEmptyPortraitSlot: View {
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "person.crop.square")
        .font(.system(size: 30, weight: .ultraLight))
      Text("A page is waiting")
        .font(.system(size: 12, weight: .semibold, design: .serif))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .foregroundStyle(Color.black.opacity(0.24))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      YearbookPageTexture(
        base: Color(red: 0.955, green: 0.935, blue: 0.875),
        ruled: true
      )
    )
    .overlay {
      Rectangle()
        .stroke(Color.black.opacity(0.13), style: StrokeStyle(lineWidth: 0.8, dash: [5, 4]))
        .padding(6)
    }
    .rotationEffect(.degrees(0.35))
    .shadow(color: Color.black.opacity(0.10), radius: 2, x: 1, y: 2)
    .accessibilityElement(children: .combine)
  }
}

private struct YearbookHeaderPaper: View {
  var body: some View {
    YearbookPageTexture(base: Color(red: 0.965, green: 0.945, blue: 0.895), ruled: false)
      .overlay(alignment: .top) {
        Rectangle()
          .fill(Color.white.opacity(0.52))
          .frame(height: 1)
      }
      .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
  }
}

private struct YearbookBookCoverSurface: View {
  private let coverShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

  var body: some View {
    ZStack {
      coverShape
        .fill(Color(red: 0.20, green: 0.15, blue: 0.105))

      LinearGradient(
        colors: [
          Color.white.opacity(0.12),
          Color.clear,
          Color.black.opacity(0.26),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Canvas { context, size in
        for index in 0..<96 {
          let x = CGFloat((index * 37 + 11) % 101) / 101 * max(size.width, 1)
          let y = CGFloat((index * 71 + 23) % 103) / 103 * max(size.height, 1)
          var grain = Path()
          grain.move(to: CGPoint(x: x, y: y))
          grain.addLine(to: CGPoint(x: min(size.width, x + CGFloat(3 + index % 8)), y: y + 0.7))
          context.stroke(grain, with: .color(Color.white.opacity(0.035)), lineWidth: 0.7)
        }
      }
      .allowsHitTesting(false)

      coverShape
        .stroke(Color.black.opacity(0.72), lineWidth: 2.2)

      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(
          Color(red: 0.73, green: 0.61, blue: 0.43).opacity(0.46),
          style: StrokeStyle(lineWidth: 1, dash: [3, 3])
        )
        .padding(5)
    }
    .clipShape(coverShape)
    .allowsHitTesting(false)
  }
}

private struct YearbookPageTexture: View {
  let base: Color
  var ruled = false

  var body: some View {
    ZStack {
      base

      LinearGradient(
        colors: [Color.white.opacity(0.24), Color.clear, Color.black.opacity(0.055)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Canvas { context, size in
        if ruled {
          for y in stride(from: 19.0, through: size.height, by: 20.0) {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(Color.blue.opacity(0.075)), lineWidth: 0.55)
          }
        }

        for index in 0..<48 {
          let x = CGFloat((index * 47 + 13) % 211) / 211 * max(size.width, 1)
          let y = CGFloat((index * 79 + 29) % 223) / 223 * max(size.height, 1)
          let length = CGFloat(4 + (index % 9))
          var fiber = Path()
          fiber.move(to: CGPoint(x: x, y: y))
          fiber.addLine(to: CGPoint(x: min(x + length, size.width), y: y + CGFloat((index % 3) - 1)))
          context.stroke(fiber, with: .color(Color.black.opacity(0.022)), lineWidth: 0.6)
        }
      }
      .allowsHitTesting(false)
    }
  }
}

private struct YearbookPolaroidPaper: View {
  var body: some View {
    YearbookPageTexture(base: Color(red: 0.975, green: 0.958, blue: 0.91), ruled: false)
  }
}

private struct YearbookCenterBinding: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color.black.opacity(0.32),
          Color.black.opacity(0.10),
          Color.white.opacity(0.22),
          Color.black.opacity(0.13),
          Color.black.opacity(0.36),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )

      Rectangle()
        .fill(Color.black.opacity(0.24))
        .frame(width: 1)

      HStack {
        Rectangle().fill(Color.white.opacity(0.24)).frame(width: 1)
        Spacer(minLength: 0)
        Rectangle().fill(Color.white.opacity(0.16)).frame(width: 1)
      }
      .padding(.horizontal, 2)
    }
    .shadow(color: Color.black.opacity(0.28), radius: 5)
    .allowsHitTesting(false)
  }
}

private struct YearbookPageHoles: View {
  var body: some View {
    GeometryReader { proxy in
      let spacing = proxy.size.height / 7
      VStack(spacing: max(8, spacing - 12)) {
        ForEach(0..<7, id: \.self) { _ in
          Circle()
            .fill(Color(red: 0.38, green: 0.31, blue: 0.22).opacity(0.72))
            .overlay {
              Circle().stroke(Color.white.opacity(0.46), lineWidth: 1)
            }
            .frame(width: 11, height: 11)
            .shadow(color: Color.black.opacity(0.22), radius: 1, x: 1, y: 1)
        }
      }
      .frame(maxHeight: .infinity)
    }
  }
}

private struct YearbookTapeStrip: View {
  let color: Color

  var body: some View {
    Rectangle()
      .fill(color.opacity(0.76))
      .overlay {
        Canvas { context, size in
          for index in 0..<8 {
            let x = size.width * CGFloat(index) / 8
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: min(size.width, x + 5), y: size.height))
            context.stroke(line, with: .color(Color.white.opacity(0.09)), lineWidth: 0.7)
          }
        }
      }
      .rotationEffect(.degrees(-1.5))
      .shadow(color: Color.black.opacity(0.10), radius: 1, y: 1)
      .allowsHitTesting(false)
  }
}

private struct YearbookPushpin: View {
  let color: Color

  var body: some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [Color.white.opacity(0.78), color, color.opacity(0.72)],
          center: .topLeading,
          startRadius: 1,
          endRadius: 11
        )
      )
      .frame(width: 16, height: 16)
      .overlay { Circle().stroke(Color.black.opacity(0.16), lineWidth: 0.7) }
      .shadow(color: Color.black.opacity(0.28), radius: 2, x: 2, y: 3)
      .allowsHitTesting(false)
  }
}

private struct YearbookPaperclip: View {
  var body: some View {
    Image(systemName: "paperclip")
      .font(.system(size: 31, weight: .medium))
      .foregroundStyle(Color(red: 0.30, green: 0.29, blue: 0.25))
      .rotationEffect(.degrees(-13))
      .shadow(color: Color.white.opacity(0.55), radius: 0.5, x: -1, y: -1)
      .shadow(color: Color.black.opacity(0.24), radius: 1.2, x: 1, y: 2)
      .allowsHitTesting(false)
  }
}

private struct YearbookPressedFlowers: View {
  var body: some View {
    ZStack(alignment: .bottom) {
      Capsule()
        .fill(Color.green.opacity(0.44))
        .frame(width: 2, height: 66)
        .rotationEffect(.degrees(9))
        .offset(x: 7)
      Capsule()
        .fill(Color.green.opacity(0.36))
        .frame(width: 2, height: 56)
        .rotationEffect(.degrees(-12))
        .offset(x: -8)
      pressedFlower(color: Color(red: 0.74, green: 0.43, blue: 0.47))
        .offset(x: 15, y: -43)
      pressedFlower(color: Color(red: 0.84, green: 0.58, blue: 0.55))
        .scaleEffect(0.82)
        .offset(x: -12, y: -29)
    }
    .opacity(0.78)
    .rotationEffect(.degrees(4))
    .allowsHitTesting(false)
  }

  private func pressedFlower(color: Color) -> some View {
    ZStack {
      ForEach(0..<6, id: \.self) { index in
        Capsule()
          .fill(color.opacity(0.78))
          .frame(width: 7, height: 20)
          .offset(y: -8)
          .rotationEffect(.degrees(Double(index) * 60))
      }
      Circle()
        .fill(Color(red: 0.60, green: 0.42, blue: 0.18))
        .frame(width: 8, height: 8)
    }
  }
}

private func stableYearbookRotation(_ identifier: String, placement: Int) -> Double {
  let checksum = identifier.utf8.reduce(UInt64(max(placement, 0) + 1)) {
    ($0 &* 31) &+ UInt64($1)
  }
  return Double(Int(checksum % 7) - 3) * 0.42
}

private struct YearbookPaperBackground: View {
  var body: some View {
    ZStack {
      Color(red: 0.13, green: 0.115, blue: 0.095)
      LinearGradient(
        colors: [
          Color(red: 0.25, green: 0.22, blue: 0.18),
          Color(red: 0.12, green: 0.105, blue: 0.09),
          Color(red: 0.20, green: 0.175, blue: 0.14),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Canvas { context, size in
        for y in stride(from: 8.0, through: size.height, by: 11.0) {
          var grain = Path()
          grain.move(to: CGPoint(x: 0, y: y))
          grain.addCurve(
            to: CGPoint(x: size.width, y: y + 2),
            control1: CGPoint(x: size.width * 0.32, y: y - 2),
            control2: CGPoint(x: size.width * 0.68, y: y + 4)
          )
          context.stroke(grain, with: .color(Color.white.opacity(0.012)), lineWidth: 0.7)
        }
      }
      .allowsHitTesting(false)
    }
  }
}

private struct YearbookSkeletonGrid: View {
  var body: some View {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
      ForEach(0..<4, id: \.self) { _ in
        VStack(alignment: .leading, spacing: 10) {
          MIRATheme.Color.mediaPlaceholderRaised
            .aspectRatio(0.82, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 5))
          Capsule().fill(MIRATheme.Color.mediaPlaceholder).frame(width: 105, height: 16)
          Capsule().fill(MIRATheme.Color.mediaPlaceholderRaised).frame(width: 78, height: 10)
        }
        .padding(10)
        .background(MIRATheme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
    }
    .padding(14)
    .redacted(reason: .placeholder)
  }
}

private struct YearbookFilterSheet: View {
  @Binding var selectedIntent: MIRAYearbookIntent?
  @Binding var city: String
  @Binding var language: String
  @Binding var interest: String
  @Binding var ageMinimum: String
  @Binding var ageMaximum: String
  let onApply: () -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Browse Yearbook")
          .font(.system(size: 25, weight: .bold, design: .serif))
        Spacer()
        Button { dismiss() } label: {
          Image(systemName: "xmark")
            .frame(width: 44, height: 44)
        }
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          filterLabel("Show me")
          VStack(spacing: 2) {
            filterRow(title: "Everyone", icon: "person.2", intent: nil)
            ForEach(MIRAYearbookIntent.allCases) { intent in
              filterRow(title: intent.title, icon: intent == .dating ? "heart" : "person.crop.square", intent: intent)
            }
          }
          .padding(12)
          .background(YearbookFilterPaper(ruled: true))
          .rotationEffect(.degrees(-0.35))
          .shadow(color: Color.black.opacity(0.12), radius: 5, x: 1, y: 3)

          filterLabel("Optional details")
          VStack(spacing: 10) {
            filterField("City", icon: "building.2", text: $city)
            filterField("Language", icon: "character.bubble", text: $language)
            filterField("Interest or hobby", icon: "sparkles", text: $interest)

            HStack(spacing: 10) {
              filterField("Min age", icon: "person", text: $ageMinimum, keyboard: .numberPad)
              filterField("Max age", icon: "person", text: $ageMaximum, keyboard: .numberPad)
            }
          }
          .padding(12)
          .background(YearbookFilterPaper(ruled: false))
          .rotationEffect(.degrees(0.25))
          .shadow(color: Color.black.opacity(0.10), radius: 5, x: -1, y: 3)

          Button("Clear all filters") {
            selectedIntent = nil
            city = ""
            language = ""
            interest = ""
            ageMinimum = ""
            ageMaximum = ""
          }
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
        }
      }
      .scrollIndicators(.hidden)

      Button {
        onApply()
        dismiss()
      } label: {
        Text("Apply")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(Color.white)
          .frame(maxWidth: .infinity)
          .frame(height: 52)
          .background(MIRATheme.Color.forest)
          .clipShape(Capsule())
      }
      .buttonStyle(.miraPress)
    }
    .padding(22)
    .background {
      YearbookPageTexture(
        base: Color(red: 0.965, green: 0.945, blue: 0.895),
        ruled: false
      )
      .ignoresSafeArea()
    }
  }

  private func filterLabel(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(Color.black.opacity(0.62))
      .textCase(.uppercase)
      .tracking(0.7)
  }

  private func filterField(
    _ title: String,
    icon: String,
    text: Binding<String>,
    keyboard: UIKeyboardType = .default
  ) -> some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .foregroundStyle(MIRATheme.Color.textMuted)
        .frame(width: 20)
      TextField(title, text: text)
        .keyboardType(keyboard)
        .textInputAutocapitalization(keyboard == .numberPad ? .never : .words)
    }
    .padding(.horizontal, 13)
    .frame(minHeight: 46)
    .background(Color.white.opacity(0.48))
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(Color.black.opacity(0.09), lineWidth: 0.7)
    }
  }

  private func filterRow(title: String, icon: String, intent: MIRAYearbookIntent?) -> some View {
    Button {
      selectedIntent = intent
    } label: {
      HStack(spacing: 12) {
        Image(systemName: icon).frame(width: 24)
        Text(title).font(.system(size: 15, weight: .semibold))
        Spacer()
        Image(systemName: selectedIntent == intent ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selectedIntent == intent ? MIRATheme.Color.forest : MIRATheme.Color.textMuted)
      }
      .foregroundStyle(Color.black.opacity(0.82))
      .frame(height: 44)
    }
    .buttonStyle(.miraPress)
  }
}

private struct YearbookFilterPaper: View {
  let ruled: Bool

  var body: some View {
    YearbookPageTexture(
      base: Color(red: 0.985, green: 0.972, blue: 0.928),
      ruled: ruled
    )
    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .stroke(Color.black.opacity(0.10), lineWidth: 0.7)
    }
    .overlay(alignment: .top) {
      YearbookTapeStrip(color: Color(red: 0.76, green: 0.67, blue: 0.49))
        .frame(width: 54, height: 14)
        .offset(y: -7)
    }
  }
}

@MainActor
private final class YearbookProfileDetailModel: ObservableObject {
  @Published var profile: MIRAYearbookProfile
  @Published var isLoading = false
  @Published var isWorking = false
  @Published var errorMessage: String?
  let api: MIRAAPIClient

  init(api: MIRAAPIClient, profile: MIRAYearbookProfile) {
    self.api = api
    self.profile = profile
  }

  func refresh() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let response: MIRAYearbookProfileResponse = try await api.get("/yearbook/profiles/\(profile.userId)")
      if let refreshed = response.profile { profile = refreshed }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func updateConnection() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let response: MIRAYearbookActionResponse
      switch profile.connectionStatus {
      case "request_received":
        guard let requestID = profile.connectionRequestId, !requestID.isEmpty else {
          errorMessage = "This friend request is no longer available."
          return
        }
        response = try await api.post("/friends/accept/\(requestID)", body: EmptyYearbookBody())
      case "request_sent":
        guard let requestID = profile.connectionRequestId, !requestID.isEmpty else {
          errorMessage = "This pending request is no longer available."
          return
        }
        response = try await api.delete("/friends/request/\(requestID)")
      case "connected":
        response = try await api.delete("/friends/\(profile.userId)")
      default:
        response = try await api.post("/friends/request/\(profile.userId)", body: EmptyYearbookBody())
      }
      await refresh()
      if let detail = response.detail, !detail.isEmpty { errorMessage = detail }
    } catch { errorMessage = error.localizedDescription }
  }

  func toggleInterest() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let response: MIRAYearbookActionResponse
      if profile.interestSent {
        response = try await api.delete("/yearbook/profiles/\(profile.userId)/interest")
      } else {
        response = try await api.post("/yearbook/profiles/\(profile.userId)/interest", body: EmptyYearbookBody())
      }
      await refresh()
      if response.mutual == true { errorMessage = "You found each other. Say hi when you are ready." }
    } catch { errorMessage = error.localizedDescription }
  }

  func sign(message: String) async -> Bool {
    guard !isWorking else { return false }
    isWorking = true
    defer { isWorking = false }
    do {
      let _: MIRAYearbookActionResponse = try await api.post("/yearbook/profiles/\(profile.userId)/signatures", body: YearbookSignatureBody(message: message))
      await refresh()
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func block() async -> Bool {
    do {
      let _: MIRAYearbookActionResponse = try await api.post("/users/\(profile.userId)/block", body: EmptyYearbookBody())
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }
}

private struct EmptyYearbookBody: Encodable {}
private struct YearbookSignatureBody: Encodable { let message: String }
private struct YearbookSignatureReportBody: Encodable { let reason: String; let details: String }

private struct YearbookProfileDetailView: View {
  @StateObject private var model: YearbookProfileDetailModel
  @State private var showSignatureComposer = false
  @State private var showSignatures = false
  @State private var showChat = false
  @State private var showOptions = false
  @State private var showRemoveFriendConfirmation = false
  @State private var reportTarget: MIRAReportTarget?
  @State private var showReport = false
  @Environment(\.dismiss) private var dismiss
  private let currentUserID: String

  init(api: MIRAAPIClient, initialProfile: MIRAYearbookProfile, currentUserID: String) {
    _model = StateObject(wrappedValue: YearbookProfileDetailModel(api: api, profile: initialProfile))
    self.currentUserID = currentUserID
  }

  var body: some View {
    ZStack {
      YearbookPaperBackground().ignoresSafeArea()
      GeometryReader { proxy in
        let pageWidth = min(max(proxy.size.width - 8, 300), 430)

        ScrollView {
          profilePage(pageWidth: pageWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .toolbar(.hidden, for: .tabBar)
    .task { await model.refresh() }
    .sheet(isPresented: $showSignatureComposer) {
      YearbookSignatureComposer(name: model.profile.name, isWorking: model.isWorking) { message in
        await model.sign(message: message)
      }
      .presentationDetents([.height(390)])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showSignatures) {
      YearbookSignaturesView(profile: model.profile, api: model.api, currentUserID: currentUserID)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    .fullScreenCover(isPresented: $showChat) {
      ConversationNativeView(
        peerId: model.profile.userId,
        title: model.profile.name,
        api: model.api,
        currentUserId: currentUserID,
        initialAvatarURL: model.profile.profilePhoto
      )
    }
    .confirmationDialog("Profile options", isPresented: $showOptions, titleVisibility: .visible) {
      if model.profile.viewerIsOwner {
        Button("View signatures") { showSignatures = true }
      } else {
        Button(connectionTitle) {
          if model.profile.connectionStatus == "connected" {
            showRemoveFriendConfirmation = true
          } else {
            Task { await model.updateConnection() }
          }
        }
        if model.profile.interestAvailable == true {
          Button(model.profile.interestSent ? "Remove interest" : "Interested?") {
            Task { await model.toggleInterest() }
          }
        }
        Button("Report") {
          reportTarget = MIRAReportTarget(targetType: "user", targetId: model.profile.userId, ownerUserId: model.profile.userId, title: model.profile.name, subtitle: model.profile.handle)
          showReport = true
        }
        Button("Block", role: .destructive) {
          Task { if await model.block() { dismiss() } }
        }
      }
      Button("Cancel", role: .cancel) {}
    }
    .confirmationDialog("Remove friend?", isPresented: $showRemoveFriendConfirmation, titleVisibility: .visible) {
      Button("Remove Friend", role: .destructive) {
        Task { await model.updateConnection() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You can send a new friend request later.")
    }
    .sheet(isPresented: $showReport) {
      if let reportTarget {
        MIRAReportSheet(target: reportTarget, api: model.api, onSubmitted: { result in
          if result.blocked { dismiss() }
        }, onClose: { showReport = false })
      }
    }
    .alert("Yearbook", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
      Button("OK", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  private func profilePage(pageWidth: CGFloat) -> some View {
    let pageHeight = max(606, pageWidth * 1.54)

    return ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(red: 0.15, green: 0.115, blue: 0.075))
        .offset(x: -4, y: 7)

      YearbookPageTexture(base: yearbookCardColor(model.profile.theme), ruled: false)

      VStack(spacing: 9) {
        referenceIdentityHeader
          .frame(height: 176)

        HStack(alignment: .top, spacing: 9) {
          YearbookReferenceSection(title: "ABOUT ME", tapeColor: Color(red: 0.86, green: 0.72, blue: 0.44)) {
            Text(aboutMeText)
              .font(.custom("Noteworthy-Bold", size: 15, relativeTo: .body))
              .foregroundStyle(Color.black.opacity(0.82))
              .lineLimit(5)
              .minimumScaleFactor(0.78)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          YearbookReferenceSection(title: "DETAILS", tapeColor: Color(red: 0.82, green: 0.69, blue: 0.51)) {
            VStack(alignment: .leading, spacing: 3) {
              ForEach(referenceDetails.prefix(5)) { item in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                  Text(item.label)
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .frame(width: 43, alignment: .leading)
                  Text(item.value)
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                }
                .foregroundStyle(Color.black.opacity(0.79))
              }
            }
          }
        }
        .frame(height: 105)

        HStack(alignment: .top, spacing: 9) {
          YearbookReferenceSection(title: "INTERESTS", tapeColor: Color(red: 0.55, green: 0.70, blue: 0.82)) {
            HStack(spacing: 8) {
              ForEach(referenceInterests, id: \.self) { interest in
                VStack(spacing: 2) {
                  Image(systemName: yearbookInterestIcon(interest))
                    .font(.system(size: 14, weight: .medium))
                  Text(interest)
                    .font(.system(size: 7.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                }
                .frame(maxWidth: .infinity)
              }
            }
            .foregroundStyle(Color.black.opacity(0.78))
          }

          YearbookReferenceSection(title: promptTitle, tapeColor: Color(red: 0.87, green: 0.66, blue: 0.68)) {
            HStack(alignment: .bottom, spacing: 4) {
              Text(promptAnswer)
                .font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundStyle(Color.black.opacity(0.82))
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
              Image(systemName: "cup.and.saucer")
                .font(.system(size: 13, weight: .medium))
            }
          }
        }
        .frame(height: 78)

        HStack(alignment: .top, spacing: 9) {
          YearbookReferenceFavoriteCard(
            title: "FAVORITE SONG",
            value: favoriteSong,
            icon: "music.note",
            tapeColor: Color(red: 0.59, green: 0.70, blue: 0.48)
          )
          YearbookReferenceFavoriteCard(
            title: "FAVORITE PLACE",
            value: favoritePlace,
            icon: "mappin.and.ellipse",
            tapeColor: Color(red: 0.64, green: 0.61, blue: 0.73)
          )
        }
        .frame(height: 82)

        referenceActions
          .frame(height: 58)
      }
      .padding(.leading, 42)
      .padding(.trailing, 14)
      .padding(.top, 15)
      .padding(.bottom, 15)

      YearbookPageHoles()
        .frame(width: 18)
        .padding(.vertical, 18)
        .padding(.leading, 4)
        .allowsHitTesting(false)

      Button { dismiss() } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(Color.black.opacity(0.74))
          .frame(width: 34, height: 34)
          .background(Color.white.opacity(0.38))
          .clipShape(Circle())
      }
      .buttonStyle(.miraPress)
      .offset(x: 5, y: 7)
      .accessibilityLabel("Back")

      Button { showOptions = true } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(Color.black.opacity(0.76))
          .frame(width: 36, height: 29)
          .background(Color.white.opacity(0.40))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(Color.black.opacity(0.13), lineWidth: 0.8)
          }
      }
      .buttonStyle(.miraPress)
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.trailing, 13)
      .padding(.top, 10)
      .accessibilityLabel("Profile options")
    }
    .frame(width: pageWidth, height: pageHeight)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.black.opacity(0.28), lineWidth: 1.1)
    }
    .shadow(color: Color.black.opacity(0.44), radius: 20, x: 3, y: 12)
  }

  private var referenceIdentityHeader: some View {
    HStack(alignment: .top, spacing: 14) {
      ZStack(alignment: .topLeading) {
        MIRACachedImage(url: model.profile.profilePhoto, maxPixelSize: 900) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          ZStack {
            Color(red: 0.85, green: 0.82, blue: 0.74)
            Image(systemName: "person.crop.square")
              .font(.system(size: 40, weight: .light))
              .foregroundStyle(Color.black.opacity(0.30))
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .padding(8)
        .padding(.bottom, 11)
        .background(YearbookPolaroidPaper())
        .overlay { Rectangle().stroke(Color.black.opacity(0.14), lineWidth: 0.8) }
        .rotationEffect(.degrees(-1.8))
        .shadow(color: Color.black.opacity(0.20), radius: 5, x: 2, y: 4)

        YearbookPaperclip()
          .offset(x: 4, y: -15)
      }
      .frame(width: 137)

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text(model.profile.name)
            .font(.custom("Noteworthy-Bold", size: 34, relativeTo: .largeTitle))
            .foregroundStyle(Color.black.opacity(0.86))
            .lineLimit(2)
            .minimumScaleFactor(0.66)
          Image(systemName: "heart")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color(red: 0.78, green: 0.38, blue: 0.42))
        }

        if !model.profile.handle.isEmpty {
          Text(model.profile.handle)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.72))
        }

        if model.profile.age != nil || !model.profile.locationLine.isEmpty {
          HStack(spacing: 4) {
            if let age = model.profile.age { Text("\(age)") }
            if model.profile.age != nil && !model.profile.locationLine.isEmpty { Text("·") }
            if !model.profile.locationLine.isEmpty { Text(model.profile.locationLine) }
          }
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color.black.opacity(0.70))
          .lineLimit(2)
          .minimumScaleFactor(0.72)
        }

        Text(model.profile.intent.title)
          .font(.system(size: 10, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .padding(.horizontal, 9)
          .frame(height: 24)
          .background(Color(red: 0.70, green: 0.78, blue: 0.58).opacity(0.88))
          .clipShape(RoundedRectangle(cornerRadius: 4))

        Spacer(minLength: 0)

        YearbookPressedFlowers()
          .frame(width: 66, height: 65)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(.top, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  @ViewBuilder
  private var referenceActions: some View {
    if model.profile.viewerIsOwner {
      HStack(spacing: 9) {
        YearbookActionButton(title: "Signatures", subtitle: "View messages", icon: "signature") {
          showSignatures = true
        }
        YearbookActionButton(title: "Done", subtitle: "Close this page", icon: "checkmark", filled: true) {
          dismiss()
        }
      }
    } else {
      HStack(spacing: 9) {
        YearbookActionButton(title: "Sign Yearbook", subtitle: "Leave your mark", icon: "pencil.and.scribble") {
          showSignatureComposer = true
        }
        YearbookActionButton(title: "Say Hi", subtitle: "Send a message", icon: "paperplane.fill", filled: true) {
          showChat = true
        }
      }
    }
  }

  private var aboutMeText: String {
    model.profile.shortBio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private var referenceDetails: [YearbookDetailItem] {
    [
      YearbookDetailItem(label: "Height", value: model.profile.heightCm.map { "\($0) cm" } ?? ""),
      YearbookDetailItem(label: "Job", value: model.profile.job ?? ""),
      YearbookDetailItem(label: "Languages", value: (model.profile.languages ?? []).joined(separator: " · ")),
      YearbookDetailItem(label: "School", value: model.profile.school ?? ""),
      YearbookDetailItem(label: "From", value: model.profile.locationLine),
    ].filter { !$0.value.isEmpty }
  }

  private var referenceInterests: [String] {
    Array((model.profile.interests ?? model.profile.hobbies ?? []).prefix(4))
  }

  private var referencePrompt: MIRAYearbookPrompt? {
    let prompts = model.profile.prompts ?? []
    return prompts.first(where: { $0.promptKey == "most_likely_to" }) ?? prompts.first
  }

  private var promptTitle: String {
    (referencePrompt?.displayPrompt ?? "Most likely to...").uppercased()
  }

  private var promptAnswer: String {
    referencePrompt?.answer.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private var favoriteSong: String {
    model.profile.favorites?["song"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private var favoritePlace: String {
    model.profile.favorites?["place"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private func yearbookInterestIcon(_ interest: String) -> String {
    let value = interest.lowercased()
    if value.contains("photo") || value.contains("camera") { return "camera.fill" }
    if value.contains("travel") || value.contains("flight") { return "airplane" }
    if value.contains("music") { return "music.note" }
    if value.contains("coffee") || value.contains("cafe") { return "cup.and.saucer.fill" }
    if value.contains("art") { return "paintpalette.fill" }
    if value.contains("book") || value.contains("read") { return "book.closed.fill" }
    return "star.fill"
  }

  private var resolvedSectionOrder: [String] {
    let allowed = MIRAYearbookProfileDraft.defaultSectionOrder
    let requested = model.profile.sectionOrder ?? []
    let valid = requested.filter { allowed.contains($0) }
    return valid + allowed.filter { !valid.contains($0) }
  }

  @ViewBuilder
  private func profileSection(_ section: String) -> some View {
    switch section {
    case "about":
      if let bio = model.profile.shortBio, !bio.isEmpty {
        YearbookPaperSection(title: "ABOUT ME", color: Color.yellow.opacity(0.22)) {
          Text(bio)
            .font(.system(size: 17, weight: .regular, design: .serif))
            .foregroundStyle(Color.black.opacity(0.84))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    case "details":
      detailsGrid
    case "interests":
      if let interests = model.profile.interests, !interests.isEmpty {
        YearbookPaperSection(title: "INTERESTS", color: Color.blue.opacity(0.18)) {
          YearbookTagFlow(values: interests)
        }
      }
    case "prompts":
      if let prompts = model.profile.prompts, !prompts.isEmpty {
        ForEach(prompts) { prompt in
          YearbookPaperSection(title: prompt.displayPrompt.uppercased(), color: Color.pink.opacity(0.16)) {
            Text(prompt.answer)
              .font(.system(size: 17, weight: .medium, design: .serif))
              .foregroundStyle(Color.black.opacity(0.84))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    case "favorites":
      if let favorites = model.profile.favorites, !favorites.isEmpty {
        favoritesSection(favorites)
      }
    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private var detailsGrid: some View {
    let details = [
      YearbookDetailItem(label: "Age", value: model.profile.age.map(String.init) ?? ""),
      YearbookDetailItem(label: "Height", value: model.profile.heightCm.map { "\($0) cm" } ?? ""),
      YearbookDetailItem(label: "Job", value: model.profile.job ?? ""),
      YearbookDetailItem(label: "School", value: model.profile.school ?? ""),
      YearbookDetailItem(label: "Languages", value: (model.profile.languages ?? []).joined(separator: " / ")),
      YearbookDetailItem(label: "Mood", value: model.profile.currentMood ?? ""),
    ].filter { !$0.value.isEmpty }
    if !details.isEmpty {
      YearbookPaperSection(title: "DETAILS", color: Color.orange.opacity(0.14)) {
        VStack(spacing: 8) {
          ForEach(details) { item in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Text(item.label)
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .foregroundStyle(Color.black.opacity(0.57))
                .frame(width: 48, alignment: .leading)
              Text(item.value)
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(Color.black.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }
    }
  }

  private func favoritesSection(_ favorites: [String: String]) -> some View {
    YearbookPaperSection(title: "FAVORITES", color: Color.green.opacity(0.14)) {
      VStack(spacing: 10) {
        ForEach(favorites.keys.sorted(), id: \.self) { key in
          if let value = favorites[key] {
            HStack(alignment: .top, spacing: 10) {
              Image(systemName: favoriteIcon(key)).frame(width: 24)
                .foregroundStyle(Color.black.opacity(0.72))
              VStack(alignment: .leading, spacing: 2) {
                Text(key.replacingOccurrences(of: "_", with: " ").uppercased())
                  .font(.system(size: 10, weight: .bold))
                  .foregroundStyle(Color.black.opacity(0.48))
                Text(value)
                  .font(.system(size: 15, weight: .semibold, design: .serif))
                  .foregroundStyle(Color.black.opacity(0.84))
              }
              Spacer()
            }
          }
        }
      }
    }
  }

  private func favoriteIcon(_ key: String) -> String {
    switch key {
    case "song": return "music.note"
    case "place": return "mappin"
    case "food": return "fork.knife"
    case "movie": return "film"
    case "dream_job": return "briefcase"
    default: return "heart"
    }
  }

  private func signaturePreview(_ signatures: [MIRAYearbookSignature]) -> some View {
    Button { showSignatures = true } label: {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("SIGNED BY \(model.profile.signatureCount) PEOPLE")
            .font(.system(size: 13, weight: .bold, design: .serif))
            .tracking(0.7)
          Spacer()
          Image(systemName: "arrow.right")
        }
        ForEach(signatures.prefix(3)) { signature in
          HStack(spacing: 10) {
            YearbookSmallAvatar(url: signature.profilePhoto, size: 34)
            VStack(alignment: .leading, spacing: 1) {
              Text(signature.displayName?.isEmpty == false ? signature.displayName! : signature.username ?? "Captro member")
                .font(.system(size: 14, weight: .bold))
              if let message = signature.message, !message.isEmpty {
                Text(message).font(.system(size: 13)).lineLimit(1)
              }
            }
            Spacer()
          }
        }
      }
      .foregroundStyle(Color.black.opacity(0.84))
      .padding(17)
      .background(YearbookPageTexture(base: Color(red: 0.975, green: 0.95, blue: 0.88), ruled: true))
      .overlay { Rectangle().stroke(Color.black.opacity(0.12), lineWidth: 0.8) }
      .overlay(alignment: .top) {
        YearbookTapeStrip(color: Color(red: 0.76, green: 0.66, blue: 0.49))
          .frame(width: 54, height: 15)
          .offset(y: -8)
      }
      .rotationEffect(.degrees(0.35))
      .shadow(color: Color.black.opacity(0.13), radius: 5, y: 3)
    }
    .buttonStyle(.miraPress)
  }

  private var actionPanel: some View {
    VStack(spacing: 10) {
      if !model.profile.viewerIsOwner {
        HStack(spacing: 10) {
          YearbookActionButton(title: "Sign Yearbook", subtitle: "Leave your mark", icon: "pencil.and.scribble") {
            showSignatureComposer = true
          }
          YearbookActionButton(title: "Say Hi", subtitle: "Send a message", icon: "paperplane.fill", filled: true) {
            showChat = true
          }
        }

        HStack(spacing: 10) {
          YearbookActionButton(
            title: connectionTitle,
            subtitle: connectionSubtitle,
            icon: model.profile.connectionStatus == "connected" ? "checkmark" : "person.badge.plus"
          ) {
            if model.profile.connectionStatus == "connected" {
              showRemoveFriendConfirmation = true
            } else {
              Task { await model.updateConnection() }
            }
          }
          .disabled(model.isWorking)

          if model.profile.interestAvailable == true {
            YearbookActionButton(
              title: model.profile.interestMutual ? "Mutual" : (model.profile.interestSent ? "Interested" : "Interested?"),
              subtitle: model.profile.interestMutual ? "You found each other" : "Private unless mutual",
              icon: model.profile.interestSent ? "heart.fill" : "heart"
            ) {
              Task { await model.toggleInterest() }
            }
            .disabled(model.isWorking)
          }
        }
      }
    }
  }

  private var connectionTitle: String {
    switch model.profile.connectionStatus {
    case "connected": return "Friends"
    case "request_sent": return "Requested"
    case "request_received": return "Respond"
    default: return "Add Friend"
    }
  }

  private var connectionSubtitle: String {
    switch model.profile.connectionStatus {
    case "connected": return "Tap to remove"
    case "request_sent": return "Tap to cancel"
    case "request_received": return "Accept their request"
    default: return "Send a friend request"
    }
  }
}

private struct YearbookReferenceSection<Content: View>: View {
  let title: String
  let tapeColor: Color
  let content: Content

  init(title: String, tapeColor: Color, @ViewBuilder content: () -> Content) {
    self.title = title
    self.tapeColor = tapeColor
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.system(size: 9, weight: .bold, design: .serif))
        .tracking(0.5)
        .lineLimit(1)
        .minimumScaleFactor(0.66)
        .padding(.horizontal, 7)
        .frame(height: 19)
        .background(tapeColor.opacity(0.72))
        .rotationEffect(.degrees(-1.2))

      content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(YearbookPageTexture(base: Color(red: 0.968, green: 0.947, blue: 0.885), ruled: true))
    .overlay {
      Rectangle().stroke(Color.black.opacity(0.13), lineWidth: 0.8)
    }
    .rotationEffect(.degrees(stableYearbookRotation(title, placement: title.count)))
    .shadow(color: Color.black.opacity(0.13), radius: 3, x: 1, y: 2)
    .clipped()
  }
}

private struct YearbookReferenceFavoriteCard: View {
  let title: String
  let value: String
  let icon: String
  let tapeColor: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 8.5, weight: .bold, design: .serif))
        .tracking(0.4)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(tapeColor.opacity(0.72))
        .rotationEffect(.degrees(-0.9))

      HStack(spacing: 8) {
        ZStack {
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.black.opacity(0.78))
          Image(systemName: icon)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.90))
        }
        .frame(width: 39, height: 39)

        VStack(alignment: .leading, spacing: 3) {
          Text(value)
            .font(.system(size: 10.5, weight: .semibold, design: .serif))
            .foregroundStyle(Color.black.opacity(0.82))
            .lineLimit(2)
            .minimumScaleFactor(0.70)

          HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { index in
              Capsule()
                .fill(Color.black.opacity(0.48))
                .frame(width: 1.5, height: CGFloat(3 + (index * 7) % 10))
            }
          }
        }
        Spacer(minLength: 0)
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(YearbookPageTexture(base: Color(red: 0.968, green: 0.947, blue: 0.885), ruled: false))
    .overlay { Rectangle().stroke(Color.black.opacity(0.13), lineWidth: 0.8) }
    .rotationEffect(.degrees(stableYearbookRotation(title, placement: value.count)))
    .shadow(color: Color.black.opacity(0.13), radius: 3, x: 1, y: 2)
    .clipped()
  }
}

private struct YearbookPaperSection<Content: View>: View {
  let title: String
  let color: Color
  let content: Content

  init(title: String, color: Color, @ViewBuilder content: () -> Content) {
    self.title = title
    self.color = color
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      Text(title)
        .font(.system(size: 10, weight: .bold, design: .serif))
        .tracking(0.7)
        .lineLimit(2)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color)
        .rotationEffect(.degrees(-1.1))
      content
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(minHeight: 104, alignment: .topLeading)
    .background(YearbookPageTexture(base: Color(red: 0.965, green: 0.94, blue: 0.86), ruled: true))
    .overlay {
      Rectangle().stroke(Color.black.opacity(0.12), lineWidth: 0.8)
    }
    .overlay(alignment: .top) {
      YearbookTapeStrip(color: color.opacity(0.86))
        .frame(width: 46, height: 13)
        .offset(y: -7)
    }
    .rotationEffect(.degrees(stableYearbookRotation(title, placement: title.count)))
    .shadow(color: Color.black.opacity(0.13), radius: 4, x: 1, y: 3)
  }
}

private struct YearbookDetailItem: Identifiable {
  let label: String
  let value: String
  var id: String { label }
}

private struct YearbookTagFlow: View {
  let values: [String]
  private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

  var body: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
      ForEach(values, id: \.self) { value in
        Text(value)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.78))
          .lineLimit(1)
          .padding(.horizontal, 10)
          .frame(height: 31)
          .frame(maxWidth: .infinity)
          .background(Color.white.opacity(0.42))
          .clipShape(RoundedRectangle(cornerRadius: 5))
      }
    }
  }
}

private struct YearbookActionButton: View {
  let title: String
  let subtitle: String
  let icon: String
  var filled = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon).font(.system(size: 19, weight: .semibold))
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.system(size: 14, weight: .bold)).lineLimit(1)
          Text(subtitle).font(.system(size: 10, weight: .medium)).lineLimit(1).opacity(0.72)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 13)
      .frame(maxWidth: .infinity)
      .frame(height: 62)
      .foregroundStyle(filled ? Color.white : Color.black.opacity(0.84))
      .background {
        if filled {
          Color(red: 0.16, green: 0.15, blue: 0.13)
        } else {
          YearbookPageTexture(base: Color(red: 0.965, green: 0.935, blue: 0.86), ruled: false)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .overlay {
        RoundedRectangle(cornerRadius: 4).stroke(filled ? Color.clear : Color.black.opacity(0.14), lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
    }
    .buttonStyle(.miraPress)
  }
}

private struct YearbookSignatureComposer: View {
  let name: String
  let isWorking: Bool
  let onSubmit: (String) async -> Bool
  @Environment(\.dismiss) private var dismiss
  @State private var message = ""
  @State private var localWorking = false
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Sign \(name)'s Yearbook")
            .font(.system(size: 22, weight: .bold, design: .serif))
          Text("Leave a short mark. You can remove it later.")
            .font(.system(size: 13))
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
        Spacer()
        Button("Cancel") { dismiss() }
      }

      ZStack(alignment: .topLeading) {
        TextEditor(text: $message)
          .focused($focused)
          .scrollContentBackground(.hidden)
          .padding(10)
        if message.isEmpty {
          Text("Never change... or something only the two of you understand.")
            .font(.system(size: 16, design: .serif))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .padding(16)
            .allowsHitTesting(false)
        }
      }
      .frame(height: 142)
      .background(Color.yellow.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(alignment: .bottomTrailing) {
        Text("\(message.count)/160")
          .font(.caption)
          .foregroundStyle(MIRATheme.Color.textMuted)
          .padding(10)
      }
      .onChange(of: message) { _, value in
        if value.count > 160 { message = String(value.prefix(160)) }
      }

      Button {
        Task {
          localWorking = true
          let success = await onSubmit(message)
          localWorking = false
          if success { dismiss() }
        }
      } label: {
        Group {
          if localWorking || isWorking { ProgressView().tint(.white) }
          else { Text("Sign Yearbook").font(.system(size: 16, weight: .bold)) }
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(MIRATheme.Color.forest)
        .clipShape(Capsule())
      }
      .buttonStyle(.miraPress)
      .disabled(localWorking || isWorking)
    }
    .padding(22)
    .background(MIRATheme.Color.surface)
    .onAppear { focused = true }
  }
}

private struct YearbookSignaturesView: View {
  let profile: MIRAYearbookProfile
  let api: MIRAAPIClient
  let currentUserID: String
  @Environment(\.dismiss) private var dismiss
  @State private var signatures: [MIRAYearbookSignature]
  @State private var isLoading = false

  init(profile: MIRAYearbookProfile, api: MIRAAPIClient, currentUserID: String) {
    self.profile = profile
    self.api = api
    self.currentUserID = currentUserID
    _signatures = State(initialValue: profile.signatures ?? [])
  }

  var body: some View {
    NavigationStack {
      List {
        if isLoading && signatures.isEmpty {
          ProgressView().frame(maxWidth: .infinity)
        } else if signatures.isEmpty {
          MIRAEmptyState(title: "No signatures yet", message: "A signed Yearbook grows one real connection at a time.", systemImage: "pencil.and.scribble")
            .listRowBackground(Color.clear)
        } else {
          ForEach(signatures) { signature in
            HStack(alignment: .top, spacing: 12) {
              YearbookSmallAvatar(url: signature.profilePhoto, size: 42)
              VStack(alignment: .leading, spacing: 3) {
                Text(signature.displayName?.isEmpty == false ? signature.displayName! : signature.username ?? "Captro member")
                  .font(.system(size: 15, weight: .bold))
                if let message = signature.message, !message.isEmpty {
                  Text(message).font(.system(size: 14, design: .serif))
                }
              }
            }
            .swipeActions {
              if signature.signerUserId == currentUserID {
                Button("Remove", role: .destructive) { Task { await remove(signature) } }
              } else if profile.viewerIsOwner {
                Button("Hide", role: .destructive) { Task { await hide(signature) } }
                Button("Report") { Task { await report(signature) } }
                Button("Block", role: .destructive) { Task { await block(signature) } }
              }
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(YearbookPaperBackground())
      .navigationTitle("Signatures")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
      .task { await load() }
    }
  }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    let response: MIRAYearbookSignaturesResponse? = try? await api.get("/yearbook/profiles/\(profile.userId)/signatures")
    if let response { signatures = response.signatures }
  }

  private func remove(_ signature: MIRAYearbookSignature) async {
    let _: MIRAYearbookActionResponse? = try? await api.delete("/yearbook/profiles/\(profile.userId)/signatures/me")
    signatures.removeAll { $0.id == signature.id }
  }

  private func hide(_ signature: MIRAYearbookSignature) async {
    struct Body: Encodable { let status = "hidden" }
    let _: MIRAYearbookActionResponse? = try? await api.patch("/yearbook/signatures/\(signature.id)", body: Body())
    signatures.removeAll { $0.id == signature.id }
  }

  private func report(_ signature: MIRAYearbookSignature) async {
    let _: MIRAYearbookActionResponse? = try? await api.post("/yearbook/signatures/\(signature.id)/report", body: YearbookSignatureReportBody(reason: "harassment", details: "Reported from the Yearbook signature list."))
    signatures.removeAll { $0.id == signature.id }
  }

  private func block(_ signature: MIRAYearbookSignature) async {
    let _: MIRAYearbookActionResponse? = try? await api.post("/users/\(signature.signerUserId)/block", body: EmptyYearbookBody())
    signatures.removeAll { $0.signerUserId == signature.signerUserId }
  }
}

private struct YearbookSmallAvatar: View {
  let url: String?
  let size: CGFloat

  var body: some View {
    MIRACachedImage(url: url, maxPixelSize: size * 3) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      ZStack {
        MIRATheme.Color.mediaPlaceholderRaised
        Image(systemName: "person.fill").foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}

private struct YearbookEditorView: View {
  let api: MIRAAPIClient
  let currentUser: MIRAUser?
  let existingProfile: MIRAYearbookProfile?
  let onSaved: (MIRAYearbookProfile) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var draft: MIRAYearbookProfileDraft
  @State private var languagesText: String
  @State private var interestsText: String
  @State private var hobbiesText: String
  @State private var promptOne = ""
  @State private var promptTwo = ""
  @State private var ageText: String
  @State private var heightText: String
  @State private var profileUser: MIRAUser?
  @State private var showProfileEditor = false
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(api: MIRAAPIClient, currentUser: MIRAUser?, existingProfile: MIRAYearbookProfile?, onSaved: @escaping (MIRAYearbookProfile) -> Void) {
    self.api = api
    self.currentUser = currentUser
    self.existingProfile = existingProfile
    self.onSaved = onSaved
    let value = existingProfile.map { MIRAYearbookProfileDraft.from($0, user: currentUser) } ?? MIRAYearbookProfileDraft.empty(from: currentUser)
    _draft = State(initialValue: value)
    _languagesText = State(initialValue: value.languages.joined(separator: ", "))
    _interestsText = State(initialValue: value.interests.joined(separator: ", "))
    _hobbiesText = State(initialValue: value.hobbies.joined(separator: ", "))
    _promptOne = State(initialValue: value.prompts.first(where: { $0.promptKey == "most_likely_to" })?.answer ?? "")
    _promptTwo = State(initialValue: value.prompts.first(where: { $0.promptKey == "little_joy" })?.answer ?? "")
    _ageText = State(initialValue: value.age.map(String.init) ?? "")
    _heightText = State(initialValue: value.heightCm.map(String.init) ?? "")
    _profileUser = State(initialValue: currentUser)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          editorPreview
          intentSection
          aboutSection
          detailsSection
          interestsSection
          favoritesSection
          promptsSection
          sectionOrderSection
          themeSection
          privacySection
        }
        .padding(16)
        .padding(.bottom, 28)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(YearbookPaperBackground())
      .navigationTitle("Edit Yearbook")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await save() }
          } label: {
            if isSaving { ProgressView() } else { Text("Done").fontWeight(.bold) }
          }
          .disabled(isSaving)
        }
      }
      .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
        Button("OK", role: .cancel) { errorMessage = nil }
      } message: { Text(errorMessage ?? "") }
      .fullScreenCover(isPresented: $showProfileEditor) {
        EditProfileNativeView(user: profileUser, api: api, onCancel: {
          showProfileEditor = false
        }) { updated in
          profileUser = updated
          showProfileEditor = false
        }
      }
    }
  }

  private var editorPreview: some View {
    HStack(spacing: 14) {
      YearbookSmallAvatar(url: profileUser?.profileImage, size: 76)
      VStack(alignment: .leading, spacing: 5) {
        Text(profileUser?.displayName ?? "Your page")
          .font(.system(size: 24, weight: .bold, design: .serif))
        Text("This is one Captro identity. Your login and username stay the same.")
          .font(.system(size: 12))
          .foregroundStyle(MIRATheme.Color.textSecondary)
        Button("Change profile photo") { showProfileEditor = true }
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.forest)
      }
      Spacer()
    }
    .padding(16)
    .background(yearbookCardColor(MIRAYearbookTheme(rawValue: draft.themeId) ?? .classicYearbook))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .shadow(color: Color.black.opacity(0.08), radius: 10, y: 5)
  }

  private var intentSection: some View {
    editorSection("I'M LOOKING FOR") {
      Picker("Discovery intent", selection: $draft.discoveryIntent) {
        ForEach(MIRAYearbookIntent.allCases) { intent in Text(intent.title).tag(intent.rawValue) }
      }
      .pickerStyle(.navigationLink)

      if draft.discoveryIntent == MIRAYearbookIntent.dating.rawValue || draft.discoveryIntent == MIRAYearbookIntent.friendsAndDating.rawValue {
        Toggle("Enable private mutual interest", isOn: $draft.datingEnabled)
        Text("Dating is available only to adults 18+. Interest stays private unless both people choose it.")
          .font(.caption)
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
    }
  }

  private var aboutSection: some View {
    editorSection("ABOUT ME") {
      TextField("Current mood", text: $draft.currentMood)
      TextField("A short introduction", text: $draft.shortBio, axis: .vertical)
        .lineLimit(3...6)
    }
  }

  private var detailsSection: some View {
    editorSection("DETAILS") {
      HStack {
        TextField("Age", text: $ageText)
          .keyboardType(.numberPad)
        Divider()
        TextField("Height (cm)", text: $heightText)
          .keyboardType(.numberPad)
      }
      TextField("City", text: $draft.city)
      TextField("Country", text: $draft.country)
      TextField("Job", text: $draft.job)
      TextField("School", text: $draft.school)
    }
  }

  private var interestsSection: some View {
    editorSection("INTERESTS") {
      TextField("Languages, separated by commas", text: $languagesText)
      TextField("Interests, separated by commas", text: $interestsText)
      TextField("Hobbies, separated by commas", text: $hobbiesText)
    }
  }

  private var favoritesSection: some View {
    editorSection("FAVORITES") {
      favoriteField("Favorite song", key: "song")
      favoriteField("Favorite place", key: "place")
      favoriteField("Favorite food", key: "food")
      favoriteField("Favorite movie", key: "movie")
      favoriteField("Dream job", key: "dream_job")
      favoriteField("Fun fact", key: "fun_fact")
    }
  }

  private var promptsSection: some View {
    editorSection("YEARBOOK PROMPTS") {
      TextField("Most likely to...", text: $promptOne, axis: .vertical).lineLimit(2...4)
      TextField("A small thing I love...", text: $promptTwo, axis: .vertical).lineLimit(2...4)
      Text("A few good answers feel more personal than a long questionnaire.")
        .font(.caption)
        .foregroundStyle(MIRATheme.Color.textSecondary)
    }
  }

  private var themeSection: some View {
    editorSection("PROFILE THEME") {
      Picker("Theme", selection: $draft.themeId) {
        ForEach(MIRAYearbookTheme.allCases) { theme in Text(theme.title).tag(theme.rawValue) }
      }
      .pickerStyle(.navigationLink)
    }
  }

  private var sectionOrderSection: some View {
    editorSection("PAGE ORDER") {
      Text("Move the parts that matter most to the top of your page.")
        .font(.caption)
        .foregroundStyle(MIRATheme.Color.textSecondary)

      ForEach(Array(normalizedSectionOrder.enumerated()), id: \.element) { index, section in
        HStack(spacing: 12) {
          Image(systemName: "line.3.horizontal")
            .foregroundStyle(MIRATheme.Color.textMuted)
          Text(sectionTitle(section))
            .font(.system(size: 14, weight: .semibold))
          Spacer()
          Button { moveSection(at: index, offset: -1) } label: {
            Image(systemName: "chevron.up").frame(width: 34, height: 34)
          }
          .disabled(index == 0)
          Button { moveSection(at: index, offset: 1) } label: {
            Image(systemName: "chevron.down").frame(width: 34, height: 34)
          }
          .disabled(index == normalizedSectionOrder.count - 1)
        }
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(minHeight: 42)
      }
    }
  }

  private var normalizedSectionOrder: [String] {
    let allowed = MIRAYearbookProfileDraft.defaultSectionOrder
    let valid = draft.sectionOrder.filter { allowed.contains($0) }
    return valid + allowed.filter { !valid.contains($0) }
  }

  private func sectionTitle(_ section: String) -> String {
    switch section {
    case "about": return "About me"
    case "details": return "Details"
    case "interests": return "Interests"
    case "prompts": return "Yearbook prompts"
    case "favorites": return "Favorites"
    default: return section.capitalized
    }
  }

  private func moveSection(at index: Int, offset: Int) {
    var order = normalizedSectionOrder
    let target = index + offset
    guard order.indices.contains(index), order.indices.contains(target) else { return }
    order.swapAt(index, target)
    draft.sectionOrder = order
  }

  private var privacySection: some View {
    editorSection("WHO CAN SEE WHAT") {
      privacyRow("Name", field: "display_name")
      privacyRow("Photo", field: "profile_photo")
      privacyRow("Age", field: "age")
      privacyRow("City and country", field: "city")
      privacyRow("Job", field: "job")
      privacyRow("School", field: "school")
      privacyRow("Languages", field: "languages")
      privacyRow("Interests", field: "interests")
      privacyRow("Favorites", field: "favorites")
      privacyRow("Prompts", field: "prompts")
      Toggle("Show my Yearbook page", isOn: Binding(get: { draft.status == "active" }, set: { draft.status = $0 ? "active" : "hidden" }))
    }
  }

  private func editorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 13) {
      Text(title)
        .font(.system(size: 12, weight: .bold, design: .serif))
        .tracking(0.8)
        .foregroundStyle(MIRATheme.Color.textSecondary)
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay { RoundedRectangle(cornerRadius: 10).stroke(MIRATheme.Color.hairline, lineWidth: 1) }
  }

  private func favoriteField(_ title: String, key: String) -> some View {
    TextField(title, text: Binding(
      get: { draft.favorites[key] ?? "" },
      set: { value in
        if value.isEmpty { draft.favorites.removeValue(forKey: key) }
        else { draft.favorites[key] = value }
      }
    ))
  }

  private func privacyRow(_ title: String, field: String) -> some View {
    HStack {
      Text(title).font(.system(size: 14, weight: .medium))
      Spacer()
      Picker(title, selection: Binding(
        get: { draft.fieldVisibility[field] ?? "private" },
        set: { draft.fieldVisibility[field] = $0 }
      )) {
        ForEach(MIRAYearbookVisibility.allCases) { value in
          Label(value.title, systemImage: value.systemImage).tag(value.rawValue)
        }
      }
      .labelsHidden()
    }
    .frame(minHeight: 40)
  }

  private func splitList(_ value: String, max limit: Int) -> [String] {
    var seen = Set<String>()
    var items: [String] = []
    for rawValue in value.split(separator: ",") {
      guard items.count < limit else { break }
      let item = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !item.isEmpty, seen.insert(item.lowercased()).inserted else { continue }
      items.append(item)
    }
    return items
  }

  private func save() async {
    draft.age = Int(ageText.trimmingCharacters(in: .whitespacesAndNewlines))
    draft.heightCm = Int(heightText.trimmingCharacters(in: .whitespacesAndNewlines))
    if draft.datingEnabled && (draft.age ?? 0) < 18 {
      errorMessage = "Dating can only be enabled for adults age 18 or older."
      return
    }
    isSaving = true
    defer { isSaving = false }
    draft.languages = splitList(languagesText, max: 12)
    draft.interests = splitList(interestsText, max: 20)
    draft.hobbies = splitList(hobbiesText, max: 20)
    draft.sectionOrder = normalizedSectionOrder
    draft.prompts = [
      MIRAYearbookPromptDraft(promptKey: "most_likely_to", answer: promptOne.trimmingCharacters(in: .whitespacesAndNewlines), position: 0),
      MIRAYearbookPromptDraft(promptKey: "little_joy", answer: promptTwo.trimmingCharacters(in: .whitespacesAndNewlines), position: 1),
    ].filter { !$0.answer.isEmpty }
    do {
      let response: MIRAYearbookProfileResponse = try await api.put("/yearbook/me", body: draft)
      guard let profile = response.profile else {
        errorMessage = "The server saved an incomplete Yearbook page. Please try again."
        return
      }
      onSaved(profile)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private func yearbookCardColor(_ theme: MIRAYearbookTheme) -> Color {
  switch theme {
  case .classicYearbook: return MIRATheme.Color.surface
  case .notebook: return Color(red: 0.97, green: 0.96, blue: 0.90)
  case .y2k: return Color(red: 0.91, green: 0.94, blue: 0.98)
  case .film: return Color(red: 0.94, green: 0.91, blue: 0.84)
  case .minimal: return MIRATheme.Color.surfaceRaised
  case .vintage: return Color(red: 0.93, green: 0.87, blue: 0.75)
  case .scrapbook: return Color(red: 0.96, green: 0.91, blue: 0.83)
  }
}
