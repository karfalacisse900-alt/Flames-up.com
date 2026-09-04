import SwiftUI

struct CaptroEventEditorFields: View {
  @Binding var draft: CaptroEventDraft
  var showsLegacyPriceAndAttendance = true

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Toggle("Date and time", isOn: $draft.hasSchedule)
      if draft.hasSchedule {
        DatePicker("Starts", selection: $draft.startsAt, displayedComponents: [.date, .hourAndMinute])
        Toggle("End time", isOn: $draft.hasEndTime)
        if draft.hasEndTime {
          DatePicker("Ends", selection: $draft.endsAt, displayedComponents: [.date, .hourAndMinute])
        }
        Picker("Time zone", selection: $draft.timeZone) {
          ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { zone in
            Text(zone.replacingOccurrences(of: "_", with: " ")).tag(zone)
          }
        }
        .pickerStyle(.menu)
      }
      Divider()
      field("Venue", text: $draft.venueName)
      field("Public venue address", text: $draft.address)
      field("City", text: $draft.city)
      if showsLegacyPriceAndAttendance {
        Divider()
        Toggle("Entry price", isOn: $draft.hasPrice)
        if draft.hasPrice {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            TextField("0.00", text: $draft.price)
              .keyboardType(.decimalPad)
              .accessibilityLabel("Entry price")
            Picker("Currency", selection: $draft.currency) {
              ForEach(Locale.commonISOCurrencyCodes, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu)
          }
        }
        Toggle("Allow people to join", isOn: $draft.attendanceEnabled)
      }
      if let error = draft.validationError {
        Text(error).font(.system(size: 13)).foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .font(.system(size: 15))
    .tint(MIRATheme.Color.forest)
    .environment(\.timeZone, TimeZone(identifier: draft.timeZone) ?? .current)
  }

  private func field(_ title: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.system(size: 12)).foregroundStyle(MIRATheme.Color.textMuted)
      TextField(title, text: text, axis: .vertical).lineLimit(1...3)
        .accessibilityLabel(title)
    }
  }
}

struct CaptroEventEditSheet: View {
  @ObservedObject var model: PostDetailModel
  @Environment(\.dismiss) private var dismiss
  @State private var draft: CaptroEventDraft
  @State private var isSaving = false
  @State private var error: String?

  init(model: PostDetailModel) {
    self.model = model
    _draft = State(initialValue: CaptroEventDraft(event: model.post.detail?.event))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text(model.post.titleText).font(.system(size: 22, weight: .bold))
          CaptroEventEditorFields(draft: $draft)
          if let error { Text(error).font(.system(size: 14)).foregroundStyle(MIRATheme.Color.textMuted) }
        }.padding(20)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(MIRATheme.Color.surface)
      .navigationTitle("Edit event")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task {
              isSaving = true
              defer { isSaving = false }
              do { try await model.updateEvent(draft.input); dismiss() }
              catch { self.error = "Couldn't save event details. Your edits are still here. Please try again." }
            }
          }.disabled(isSaving || draft.validationError != nil)
        }
      }
    }
    .tint(MIRATheme.Color.forest)
    .interactiveDismissDisabled(isSaving)
  }
}
