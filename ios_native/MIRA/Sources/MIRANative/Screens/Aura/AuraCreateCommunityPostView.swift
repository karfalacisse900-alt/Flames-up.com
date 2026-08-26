import PhotosUI
import SwiftUI
import UIKit

/// Aura's focused community composer. It deliberately supports only the two
/// social objects adopted by the product: Small Post and Meetup.
public struct AuraCreateCommunityPostView: View {
  let api: MIRAAPIClient
  let currentUser: MIRAUser
  let onFinished: () -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase

  @State private var mode: AuraCommunityPostMode = .smallPost
  @State private var title = ""
  @State private var bodyText = ""
  @State private var category: AuraSmallPostCategory = .question
  @State private var audience: AuraCommunityAudience = .public
  @State private var allowReplies = true
  @State private var neighborhood = ""
  @State private var startsAt = Date().addingTimeInterval(3_600)
  @State private var endsAt = Date().addingTimeInterval(9_000)
  @State private var entryType: AuraMeetupEntryType = .free
  @State private var entryAmountAUR = ""
  @State private var maxPeople = 12
  @State private var selectedPlace: MIRAExactPostPlace?
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var selectedPhoto: MIRAPickedMedia?
  @State private var selectedPhotoImage: UIImage?
  @State private var isLoadingPhoto = false
  @State private var isPublishing = false
  @State private var isShowingPlacePicker = false
  @State private var hasRestoredDraft = false
  @State private var savedDraftMessage: String?
  @State private var errorMessage: String?
  @State private var clientRequestId = UUID().uuidString
  @FocusState private var focusedField: ComposerField?

  private enum ComposerField: Hashable {
    case title
    case body
    case neighborhood
    case amount
  }

  public init(
    api: MIRAAPIClient,
    currentUser: MIRAUser,
    onFinished: @escaping () -> Void
  ) {
    self.api = api
    self.currentUser = currentUser
    self.onFinished = onFinished
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          modePicker
          mediaSection

          if mode == .smallPost {
            smallPostFields
          } else {
            meetupFields
          }

          previewSection

          if let message = savedDraftMessage {
            Label(message, systemImage: "checkmark.circle.fill")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(MIRATheme.Color.forest)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
          }

          publishButton
          saveDraftButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 34)
      }
      .background(MIRATheme.Color.paperCanvas.ignoresSafeArea())
      .navigationTitle("Create Post")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(MIRATheme.Color.paperCanvas, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .interactiveDismissDisabled(isPublishing)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismissComposer()
          } label: {
            Image(systemName: "chevron.left")
              .font(.headline)
          }
          .disabled(isPublishing)
          .accessibilityLabel("Close")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Post") {
            Task { await publish() }
          }
          .fontWeight(.bold)
          .foregroundStyle(MIRATheme.Color.auraViolet)
          .disabled(isPublishing || isLoadingPhoto)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { focusedField = nil }
        }
      }
      .sheet(isPresented: $isShowingPlacePicker) {
        PostLocationPickerSheet(api: api, selectedPlace: $selectedPlace, onClose: nil)
      }
      .task { restoreDraftIfAvailable() }
      .onChange(of: selectedPhotoItem) { _, item in
        guard let item else { return }
        Task { await loadMedia(item) }
      }
      .onChange(of: selectedPlace) { _, place in
        guard let place else { return }
        if neighborhood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          neighborhood = place.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
      }
      .onChange(of: startsAt) { _, date in
        if endsAt <= date {
          endsAt = date.addingTimeInterval(5_400)
        }
      }
      .onChange(of: mode) { _, _ in
        errorMessage = nil
        savedDraftMessage = nil
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .background, hasRestoredDraft, !isPublishing else { return }
        saveDraft(silent: true)
      }
    }
  }

  private var modePicker: some View {
    Picker("Post type", selection: $mode) {
      ForEach(AuraCommunityPostMode.allCases) { value in
        Text(value.title).tag(value)
      }
    }
    .pickerStyle(.segmented)
    .tint(MIRATheme.Color.auraViolet)
    .accessibilityHint("Choose Small Post or Meetup")
  }

  private var mediaSection: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack {
        Text(mode == .meetup ? "Cover Photo or Video" : "Add Photo or Video")
          .font(.headline)
        Text(mode == .meetup ? "Required" : "Optional")
          .font(.caption.weight(.semibold))
          .foregroundStyle(mode == .meetup ? MIRATheme.Color.auraViolet : MIRATheme.Color.textMuted)
        Spacer()
        if selectedPhoto != nil {
          Button("Remove", role: .destructive) {
            selectedPhotoItem = nil
            selectedPhoto = nil
            selectedPhotoImage = nil
          }
          .font(.caption.weight(.semibold))
        }
      }

      if let image = selectedPhotoImage {
        ZStack {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: mode == .meetup ? 170 : 136)
            .clipped()

          if selectedPhoto?.kind == .video {
            Image(systemName: "play.fill")
              .font(.system(size: 22, weight: .black))
              .foregroundStyle(MIRATheme.Color.paperSurface)
              .frame(width: 50, height: 50)
              .background(MIRATheme.Color.inkBorder.opacity(0.86), in: Circle())
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(MIRATheme.Color.paperSurfaceMuted)
          VStack(spacing: 8) {
            if isLoadingPhoto {
              ProgressView()
            } else {
              Image(systemName: selectedPhoto?.kind == .video ? "video.fill" : "photo.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(MIRATheme.Color.auraViolet)
              Text(mediaHelperText)
                .font(.subheadline)
                .foregroundStyle(MIRATheme.Color.textSecondary)
                .multilineTextAlignment(.center)
            }
          }
          .padding()
        }
        .frame(height: mode == .meetup ? 152 : 116)
      }

      PhotosPicker(
        selection: $selectedPhotoItem,
        matching: .any(of: [.images, .videos]),
        preferredItemEncoding: .current
      ) {
        Label(selectedPhoto == nil ? "Add Photo or Video" : "Change Media", systemImage: "photo.on.rectangle.angled")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(MIRATheme.Color.auraViolet)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(MIRATheme.Color.auraViolet, lineWidth: 1.2)
          }
      }
      .buttonStyle(.plain)
      .disabled(isLoadingPhoto || isPublishing)
    }
    .padding(14)
    .physicalAuraCard()
  }

  private var smallPostFields: some View {
    VStack(spacing: 14) {
      textFieldsCard(
        titlePlaceholder: "Title",
        bodyPlaceholder: "Share something with your community",
        bodyLimit: 600
      )
      categoryCard
      placeAndAudienceCard
    }
  }

  private var meetupFields: some View {
    VStack(spacing: 14) {
      textFieldsCard(
        titlePlaceholder: "Meetup title",
        bodyPlaceholder: "Describe what people will do and what they should know",
        bodyLimit: 1_200
      )
      meetupDetailsCard
      peopleCard
    }
  }

  private func textFieldsCard(
    titlePlaceholder: String,
    bodyPlaceholder: String,
    bodyLimit: Int
  ) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "textformat")
          .frame(width: 22)
        TextField(titlePlaceholder, text: $title)
          .focused($focusedField, equals: .title)
          .textInputAutocapitalization(.sentences)
          .onChange(of: title) { _, value in
            if value.count > 180 { title = String(value.prefix(180)) }
          }
      }
      .padding(14)

      Divider().padding(.horizontal, 14)

      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "bubble.left")
          .frame(width: 22)
          .padding(.top, 4)
        ZStack(alignment: .topLeading) {
          if bodyText.isEmpty {
            Text(bodyPlaceholder)
              .foregroundStyle(MIRATheme.Color.textMuted)
              .padding(.top, 8)
              .allowsHitTesting(false)
          }
          TextEditor(text: $bodyText)
            .focused($focusedField, equals: .body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 104)
            .onChange(of: bodyText) { _, value in
              if value.count > bodyLimit { bodyText = String(value.prefix(bodyLimit)) }
            }
        }
      }
      .padding(14)

      Text("\(bodyText.count)/\(bodyLimit)")
        .font(.caption2)
        .foregroundStyle(MIRATheme.Color.textMuted)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
    .physicalAuraCard()
  }

  private var categoryCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Category", systemImage: "tag")
        .font(.subheadline.weight(.semibold))

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 9)], alignment: .leading, spacing: 9) {
        ForEach(AuraSmallPostCategory.allCases) { value in
          Button {
            category = value
          } label: {
            Label(value.title, systemImage: value.symbol)
              .font(.caption.weight(.semibold))
              .foregroundStyle(category == value ? .white : MIRATheme.Color.textPrimary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 9)
              .background(category == value ? MIRATheme.Color.auraViolet : MIRATheme.Color.paperSurface, in: Capsule())
              .overlay {
                Capsule().stroke(category == value ? MIRATheme.Color.auraViolet : MIRATheme.Color.hairline, lineWidth: 1)
              }
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(
            category == value ? AccessibilityTraits.isSelected : AccessibilityTraits()
          )
        }
      }
    }
    .padding(14)
    .physicalAuraCard()
  }

  private var placeAndAudienceCard: some View {
    VStack(spacing: 0) {
      detailButton(
        symbol: "mappin.and.ellipse",
        label: "Location (optional)",
        value: selectedPlace?.displayName ?? "Add place"
      ) {
        isShowingPlacePicker = true
      }

      Divider().padding(.leading, 48)

      HStack(spacing: 12) {
        Image(systemName: "globe")
          .frame(width: 22)
        Text("Audience")
          .font(.subheadline)
        Spacer()
        Picker("Audience", selection: $audience) {
          ForEach(AuraCommunityAudience.allCases) { value in
            Text(value.title).tag(value)
          }
        }
        .labelsHidden()
      }
      .padding(14)

      Divider().padding(.leading, 48)

      Toggle(isOn: $allowReplies) {
        Label("Allow replies", systemImage: "bubble.left")
          .font(.subheadline)
      }
      .tint(MIRATheme.Color.auraViolet)
      .padding(14)
    }
    .physicalAuraCard()
  }

  private var meetupDetailsCard: some View {
    VStack(spacing: 0) {
      detailButton(
        symbol: "mappin.and.ellipse",
        label: "Place",
        value: selectedPlace?.displayName ?? "Choose place"
      ) {
        isShowingPlacePicker = true
      }

      Divider().padding(.leading, 48)

      HStack(spacing: 12) {
        Image(systemName: "building.2")
          .frame(width: 22)
        TextField("Neighborhood", text: $neighborhood)
          .focused($focusedField, equals: .neighborhood)
          .textInputAutocapitalization(.words)
          .onChange(of: neighborhood) { _, value in
            if value.count > 100 { neighborhood = String(value.prefix(100)) }
          }
      }
      .padding(14)

      Divider().padding(.leading, 48)

      HStack(spacing: 12) {
        Image(systemName: "calendar")
          .frame(width: 22)
        Text("Starts")
          .font(.subheadline)
        Spacer()
        DatePicker("Starts", selection: $startsAt, displayedComponents: [.date, .hourAndMinute])
          .labelsHidden()
      }
      .padding(14)

      Divider().padding(.leading, 48)

      HStack(spacing: 12) {
        Image(systemName: "clock")
          .frame(width: 22)
        Text("Ends")
          .font(.subheadline)
        Spacer()
        DatePicker("Ends", selection: $endsAt, in: startsAt..., displayedComponents: [.date, .hourAndMinute])
          .labelsHidden()
      }
      .padding(14)

      Divider().padding(.leading, 48)

      VStack(alignment: .leading, spacing: 10) {
        Label("Entry", systemImage: "ticket")
          .font(.subheadline)
        Picker("Entry", selection: $entryType) {
          Text("Free").tag(AuraMeetupEntryType.free)
          Text("AUR").tag(AuraMeetupEntryType.aur)
        }
        .pickerStyle(.segmented)
        .tint(MIRATheme.Color.auraViolet)

        if entryType == .aur {
          HStack {
            TextField("Exact AUR amount", text: $entryAmountAUR)
              .focused($focusedField, equals: .amount)
              .keyboardType(.decimalPad)
              .onChange(of: entryAmountAUR) { _, value in
                entryAmountAUR = sanitizedAURInput(value)
              }
            Text("AUR")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(MIRATheme.Color.auraViolet)
          }
          .padding(11)
          .background(MIRATheme.Color.auraVioletSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
      }
      .padding(14)
    }
    .physicalAuraCard()
  }

  private var peopleCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Max People", systemImage: "person.2")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text("\(maxPeople)")
          .font(.headline)
          .foregroundStyle(MIRATheme.Color.auraViolet)
      }
      Stepper("Maximum participants", value: $maxPeople, in: 2...500)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .trailing)
      Text("Aura enforces meetup capacity when people join; this preview does not invent participants.")
        .font(.caption)
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .physicalAuraCard()
  }

  private var previewSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Preview")
        .font(.subheadline.weight(.bold))

      if mode == .meetup {
        meetupPreview
      } else {
        smallPostPreview
      }
    }
  }

  private var smallPostPreview: some View {
    HStack(alignment: .top, spacing: 11) {
      RemoteAvatar(url: currentUser.profileImage, size: 34)
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(currentUserHandle)
            .font(.subheadline.weight(.bold))
          Text(category.title.uppercased())
            .font(.caption2.weight(.black))
            .foregroundStyle(MIRATheme.Color.auraViolet)
          Spacer()
        }
        Text(cleanTitle.isEmpty ? "Your Small Post title" : cleanTitle)
          .font(.headline)
          .foregroundStyle(cleanTitle.isEmpty ? MIRATheme.Color.textMuted : MIRATheme.Color.textPrimary)
          .lineLimit(2)
        if !cleanBody.isEmpty {
          Text(cleanBody)
            .font(.subheadline)
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .lineLimit(3)
        }
        if let place = selectedPlace?.displayName {
          Label(place, systemImage: "mappin")
            .font(.caption)
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
      }
      if let image = selectedPhotoImage {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: 74, height: 74)
          .clipped()
          .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          .overlay {
            if selectedPhoto?.kind == .video {
              Image(systemName: "play.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(MIRATheme.Color.paperSurface)
                .frame(width: 30, height: 30)
                .background(MIRATheme.Color.inkBorder.opacity(0.86), in: Circle())
            }
          }
      }
    }
    .padding(14)
    .physicalAuraCard()
  }

  private var meetupPreview: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let image = selectedPhotoImage {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(maxWidth: .infinity)
          .frame(height: 135)
          .clipped()
          .overlay {
            if selectedPhoto?.kind == .video {
              Image(systemName: "play.fill")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(MIRATheme.Color.paperSurface)
                .frame(width: 48, height: 48)
                .background(MIRATheme.Color.inkBorder.opacity(0.86), in: Circle())
            }
          }
      } else {
        ZStack {
          MIRATheme.Color.paperSurfaceMuted
          Image(systemName: "photo")
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
        .frame(height: 104)
      }

      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text(cleanTitle.isEmpty ? "Your Meetup title" : cleanTitle)
            .font(.headline)
            .foregroundStyle(cleanTitle.isEmpty ? MIRATheme.Color.textMuted : MIRATheme.Color.textPrimary)
            .lineLimit(2)
          Spacer()
          Text(previewEntryLabel)
            .font(.caption.weight(.black))
            .foregroundStyle(MIRATheme.Color.auraViolet)
        }
        Text([selectedPlace?.displayName, cleanNeighborhood].compactMap { value in
          guard let value, !value.isEmpty else { return nil }
          return value
        }.joined(separator: " · "))
          .font(.caption)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
        Text("\(startsAt.formatted(date: .abbreviated, time: .shortened)) · up to \(maxPeople) people")
          .font(.caption)
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
      .padding(13)
    }
    .physicalAuraCard()
  }

  private func detailButton(
    symbol: String,
    label: String,
    value: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .frame(width: 22)
        Text(label)
          .font(.subheadline)
        Spacer()
        Text(value)
          .font(.subheadline)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .padding(14)
    }
    .buttonStyle(.plain)
  }

  private var publishButton: some View {
    Button {
      Task { await publish() }
    } label: {
      HStack(spacing: 9) {
        if isPublishing { ProgressView().tint(.white) }
        Text(isPublishing ? "Publishing…" : "Publish Post")
          .font(.headline)
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 15)
      .background(MIRATheme.Color.auraViolet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(MIRATheme.Color.inkBorder, lineWidth: 1.5)
      }
      .shadow(color: MIRATheme.Color.hardShadow, radius: 0, x: 0, y: 4)
      .padding(.bottom, 4)
    }
    .buttonStyle(.plain)
    .disabled(isPublishing || isLoadingPhoto)
    .opacity(isPublishing || isLoadingPhoto ? 0.6 : 1)
  }

  private var saveDraftButton: some View {
    Button {
      saveDraft(silent: false)
    } label: {
      Text("Save Draft")
        .font(.headline)
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(MIRATheme.Color.paperSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(MIRATheme.Color.inkBorder, lineWidth: 1.35)
        }
        .shadow(color: MIRATheme.Color.hardShadow, radius: 0, x: 0, y: 3)
        .padding(.bottom, 3)
    }
    .buttonStyle(.plain)
    .disabled(isPublishing || isLoadingPhoto)
  }

  private var currentUserHandle: String {
    if MIRAUsernameRules.isValidPublicUsername(currentUser.username) {
      return "@\(MIRAUsernameRules.normalized(currentUser.username))"
    }
    return currentUser.displayName
  }

  private var cleanTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var cleanBody: String {
    bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var cleanNeighborhood: String {
    neighborhood.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var previewEntryLabel: String {
    guard entryType == .aur else { return "FREE" }
    let clean = entryAmountAUR.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? "AUR" : "\(clean) AUR"
  }

  private var mediaHelperText: String {
    if selectedPhoto?.kind == .video {
      return "Video selected. Aura will upload and check it before publishing."
    }
    return mode == .meetup
      ? "Choose a photo or video that shows the meetup"
      : "A photo or short video can help people discover your post"
  }

  @MainActor
  private func loadMedia(_ item: PhotosPickerItem) async {
    isLoadingPhoto = true
    errorMessage = nil
    savedDraftMessage = nil
    defer { isLoadingPhoto = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
        throw MIRAAPIError.emptyResponse
      }
      let details = pickedMediaKind(from: item.supportedContentTypes, fallbackData: data)
      let preview: UIImage?
      if details.0 == .image {
        preview = UIImage(data: data)
      } else {
        preview = await MIRANativeMediaEditorRenderer.videoThumbnail(from: data, fileName: details.1)
      }
      selectedPhoto = MIRAPickedMedia(
        data: data,
        kind: details.0,
        fileName: details.1,
        mimeType: details.2
      )
      selectedPhotoImage = preview
    } catch {
      selectedPhotoItem = nil
      selectedPhoto = nil
      selectedPhotoImage = nil
      errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "The selected photo or video could not be loaded."
    }
  }

  @MainActor
  private func publish() async {
    focusedField = nil
    errorMessage = nil
    savedDraftMessage = nil

    let validation = validateForPublish()
    guard validation == nil else {
      errorMessage = validation
      return
    }

    isPublishing = true
    defer { isPublishing = false }

    do {
      var uploadedURL: String?
      var mediaAssetId: String?
      var mediaDimension: MIRAMediaDimension?
      if let selectedPhoto {
        let uploader = MIRAMediaUploadService(api: api, target: .feedPost)
        mediaDimension = await selectedPhoto.mediaDimension()
        let upload = try await uploader.uploadResult(selectedPhoto)
        uploadedURL = upload.url
        mediaAssetId = upload.mediaAssetId
      }

      let entryAtoms: String?
      if mode == .meetup, entryType == .aur {
        entryAtoms = String(try AuraAmountCodec.atoms(fromAUR: entryAmountAUR))
      } else {
        entryAtoms = nil
      }

      let body = AuraCommunityPostCreateBody(
        title: cleanTitle,
        content: cleanBody,
        image: uploadedURL,
        images: uploadedURL.map { [$0] } ?? [],
        mediaTypes: uploadedURL == nil ? [] : [selectedPhoto?.kind.rawValue ?? "image"],
        mediaDimensions: mediaDimension.map { [$0] } ?? [],
        mediaAssetIds: mediaAssetId.map { [$0] },
        location: selectedPlace?.addressText ?? selectedPlace?.displayName,
        displayCity: selectedPlace?.city,
        displayRegion: selectedPlace?.region,
        displayCountry: selectedPlace?.country,
        displayLocationLabel: broadLocationLabel,
        displayLocationSource: selectedPlace == nil ? "none" : "apple_mapkit",
        displayLocationVisibility: selectedPlace == nil ? "hidden" : "public",
        postType: mode.rawValue,
        placeId: selectedPlace?.providerPlaceId,
        placeName: selectedPlace?.displayName,
        placeProvider: selectedPlace?.provider,
        placeProviderId: selectedPlace?.providerPlaceId,
        placeFormattedAddress: selectedPlace?.addressText,
        placeCategory: selectedPlace?.category,
        placeCity: selectedPlace?.city,
        placeRegion: selectedPlace?.region,
        placeCountry: selectedPlace?.country,
        placeLat: selectedPlace?.latitude,
        placeLng: selectedPlace?.longitude,
        primaryCategory: mode == .smallPost ? category.rawValue : "meetup",
        communityCategory: mode == .smallPost ? category.rawValue : nil,
        allowReplies: mode == .smallPost ? allowReplies : true,
        audience: mode == .smallPost ? audience.rawValue : AuraCommunityAudience.public.rawValue,
        meetupNeighborhood: mode == .meetup ? cleanNeighborhood : nil,
        meetupStartsAt: mode == .meetup ? iso8601(startsAt) : nil,
        meetupEndsAt: mode == .meetup ? iso8601(endsAt) : nil,
        meetupEntryType: mode == .meetup ? entryType.rawValue : nil,
        meetupEntryAmountAtoms: entryAtoms,
        meetupMaxPeople: mode == .meetup ? maxPeople : nil,
        visibility: mode == .smallPost && audience == .friends ? "friends" : "public",
        clientRequestId: clientRequestId
      )

      let _: AuraCommunityPost = try await api.post("/posts", body: body)
      try? AuraCommunityDraftStore.clear()
      clientRequestId = UUID().uuidString
      onFinished()
    } catch {
      errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "This post could not be published."
      saveDraft(silent: true)
    }
  }

  private func validateForPublish() -> String? {
    if mode == .smallPost {
      if cleanTitle.isEmpty, cleanBody.isEmpty, selectedPhoto == nil {
        return "Add a title, some text, a photo, or a video to your Small Post."
      }
    } else {
      if cleanTitle.isEmpty { return "Add a meetup title." }
      if cleanBody.isEmpty { return "Add a meetup description." }
      if selectedPhoto == nil { return "Choose a cover photo or video for this meetup." }
      if selectedPlace == nil { return "Choose the meetup place from Apple Maps." }
      if cleanNeighborhood.isEmpty { return "Add the meetup neighborhood." }
      if endsAt <= startsAt { return "The meetup end time must be after its start time." }
      if entryType == .aur {
        do {
          _ = try AuraAmountCodec.atoms(fromAUR: entryAmountAUR)
        } catch {
          return "Enter a positive AUR amount with no more than 8 decimal places."
        }
      }
    }
    return nil
  }

  private func saveDraft(silent: Bool) {
    let draft = AuraCommunityDraft(
      mode: mode,
      title: title,
      bodyText: bodyText,
      category: category,
      audience: audience,
      allowReplies: allowReplies,
      neighborhood: neighborhood,
      startsAt: startsAt,
      endsAt: endsAt,
      entryType: entryType,
      entryAmountAUR: entryAmountAUR,
      maxPeople: maxPeople,
      placeProvider: selectedPlace?.provider,
      placeProviderId: selectedPlace?.providerPlaceId,
      placeName: selectedPlace?.displayName,
      placeFormattedAddress: selectedPlace?.addressText,
      placeLatitude: selectedPlace?.latitude,
      placeLongitude: selectedPlace?.longitude,
      placeCategory: selectedPlace?.category,
      placeCity: selectedPlace?.city,
      placeRegion: selectedPlace?.region,
      placeCountry: selectedPlace?.country,
      hasPhoto: selectedPhoto != nil,
      mediaKind: selectedPhoto?.kind.rawValue,
      mediaFileName: selectedPhoto?.fileName,
      mediaMimeType: selectedPhoto?.mimeType
    )

    do {
      try AuraCommunityDraftStore.save(draft, photoData: selectedPhoto?.data)
      if !silent {
        savedDraftMessage = "Draft saved securely on this iPhone."
        errorMessage = nil
      }
    } catch {
      if !silent {
        errorMessage = "The draft could not be saved on this iPhone."
        savedDraftMessage = nil
      }
    }
  }

  private func restoreDraftIfAvailable() {
    guard !hasRestoredDraft else { return }
    hasRestoredDraft = true
    do {
      guard let (draft, photoData) = try AuraCommunityDraftStore.load() else { return }
      mode = draft.mode
      title = draft.title
      bodyText = draft.bodyText
      category = draft.category
      audience = draft.audience
      allowReplies = draft.allowReplies
      neighborhood = draft.neighborhood
      startsAt = draft.startsAt
      endsAt = max(draft.endsAt, draft.startsAt.addingTimeInterval(900))
      entryType = draft.entryType
      entryAmountAUR = draft.entryAmountAUR
      maxPeople = min(500, max(2, draft.maxPeople))

      if let placeName = draft.placeName {
        selectedPlace = MIRAExactPostPlace(
          provider: draft.placeProvider ?? "apple_mapkit",
          providerPlaceId: draft.placeProviderId,
          name: placeName,
          formattedAddress: draft.placeFormattedAddress,
          latitude: draft.placeLatitude,
          longitude: draft.placeLongitude,
          category: draft.placeCategory,
          city: draft.placeCity,
          region: draft.placeRegion,
          country: draft.placeCountry
        )
      }

      if let photoData, draft.hasPhoto {
        let detected = pickedMediaKind(from: [], fallbackData: photoData)
        let restoredKind = draft.mediaKind.flatMap(MIRAPickedMediaKind.init(rawValue:)) ?? detected.0
        let savedFileName = draft.mediaFileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let savedMimeType = draft.mediaMimeType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let restoredMedia = MIRAPickedMedia(
          data: photoData,
          kind: restoredKind,
          fileName: savedFileName.isEmpty ? detected.1 : savedFileName,
          mimeType: savedMimeType.isEmpty ? detected.2 : savedMimeType
        )
        selectedPhoto = restoredMedia
        if restoredKind == .image {
          selectedPhotoImage = UIImage(data: photoData)
        } else {
          Task { @MainActor in
            selectedPhotoImage = await MIRANativeMediaEditorRenderer.videoThumbnail(
              from: restoredMedia.data,
              fileName: restoredMedia.fileName
            )
          }
        }
      }
      savedDraftMessage = "Draft restored."
    } catch {
      errorMessage = "The saved draft could not be restored."
    }
  }

  private func dismissComposer() {
    guard !isPublishing else { return }
    if !cleanTitle.isEmpty || !cleanBody.isEmpty || selectedPhoto != nil {
      saveDraft(silent: true)
    }
    dismiss()
  }

  private var broadLocationLabel: String? {
    let parts = [selectedPlace?.city, selectedPlace?.region, selectedPlace?.country]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }

  private func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private func sanitizedAURInput(_ value: String) -> String {
    let filtered = value.filter { $0.isNumber || $0 == "." }
    let pieces = filtered.split(separator: ".", omittingEmptySubsequences: false)
    guard pieces.count > 1 else { return String(filtered.prefix(20)) }
    let whole = String(pieces[0].prefix(20))
    let fraction = String(pieces.dropFirst().joined().prefix(8))
    return "\(whole).\(fraction)"
  }
}
