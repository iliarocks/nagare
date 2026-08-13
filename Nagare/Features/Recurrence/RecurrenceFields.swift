import SwiftUI

struct RecurrenceFields: View {
    @Binding var state: RecurrenceFormState

    let itemType: RecurrenceItemType
    let referenceDate: Date
    let showsToggle: Bool

    init(
        state: Binding<RecurrenceFormState>,
        itemType: RecurrenceItemType,
        referenceDate: Date,
        showsToggle: Bool = true
    ) {
        _state = state
        self.itemType = itemType
        self.referenceDate = referenceDate
        self.showsToggle = showsToggle
    }

    var body: some View {
        Section {
            if showsToggle {
                Toggle(
                    "Repeat",
                    isOn: Binding(
                        get: { state.isEnabled },
                        set: { enabled in
                            state.setEnabled(
                                enabled,
                                for: itemType,
                                referenceDate: referenceDate
                            )
                        }
                    )
                )
            }

            if state.isEnabled {
                if itemType == .todo {
                    Picker(
                        "Timing",
                        selection: Binding(
                            get: { state.mode },
                            set: { mode in
                                state.selectMode(
                                    mode,
                                    for: itemType,
                                    referenceDate: referenceDate
                                )
                            }
                        )
                    ) {
                        ForEach(RecurrenceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                intervalControl

                Picker(
                    "Period",
                    selection: Binding(
                        get: { state.unit },
                        set: { unit in
                            state.selectUnit(
                                unit,
                                referenceDate: referenceDate
                            )
                        }
                    )
                ) {
                    ForEach(RecurrenceUnit.allCases) { unit in
                        Text(unit.pluralTitle.capitalized).tag(unit)
                    }
                }

                if state.mode == .absolute && state.unit == .week {
                    weeklyAnchors
                }

                if state.mode == .absolute && state.unit == .month {
                    monthlyAnchors
                }
            }
        }
    }

    @ViewBuilder
    private var intervalControl: some View {
#if os(macOS)
        LabeledContent("Every") {
            HStack(spacing: 10) {
                Button {
                    state.interval = max(1, state.interval - 1)
                } label: {
                    Label("Decrease Interval", systemImage: "minus")
                        .labelStyle(.iconOnly)
                }
                .disabled(state.interval == 1)

                Text(state.interval, format: .number)
                    .monospacedDigit()
                    .frame(minWidth: 24)
                    .accessibilityLabel("Every \(state.interval)")

                Button {
                    state.interval = min(999, state.interval + 1)
                } label: {
                    Label("Increase Interval", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .disabled(state.interval == 999)
            }
            .buttonStyle(.borderless)
        }
#else
        Stepper(value: $state.interval, in: 1...999) {
            LabeledContent("Every") {
                Text(state.interval, format: .number)
                    .monospacedDigit()
            }
        }
#endif
    }

    private var weeklyAnchors: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Days")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                ForEach(Array(Self.weekdays.enumerated()), id: \.offset) {
                    anchor,
                    label in
                    anchorButton(
                        label,
                        anchor: anchor,
                        accessibilityLabel: Self.weekdayNames[anchor]
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var monthlyAnchors: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Days of month")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 7),
                    count: 7
                ),
                spacing: 7
            ) {
                ForEach(0..<31, id: \.self) { anchor in
                    anchorButton(
                        "\(anchor + 1)",
                        anchor: anchor,
                        accessibilityLabel: "Day \(anchor + 1)"
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func anchorButton(
        _ label: String,
        anchor: Int,
        accessibilityLabel: String
    ) -> some View {
        let isSelected = state.anchors.contains(anchor)
        return Button {
            state.toggleAnchor(anchor)
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static let weekdays = ["M", "T", "W", "T", "F", "S", "S"]
    private static let weekdayNames = [
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday"
    ]
}
