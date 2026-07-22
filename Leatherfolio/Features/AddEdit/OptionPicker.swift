import SwiftUI

/// A picker row backed by catalog options with an "Other…" escape hatch.
/// - Empty `options` → renders a plain free-text field (seed missing/degraded).
/// - Non-empty → wheel/menu picker with None + options + "Other…"; choosing
///   "Other…" reveals a free-text field bound to the same selection.
struct OptionPicker: View {
    let title: String
    let options: [String]
    @Binding var selection: String   // "" = unset
    @State private var useFreeText = false

    private static let otherTag = "__other__"

    var body: some View {
        if options.isEmpty {
            TextField(title, text: $selection)
                .accessibilityLabel(title)
        } else {
            Picker(title, selection: pickerBinding) {
                Text("None").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
                Text("Other…").tag(Self.otherTag)
            }
            if showsFreeText {
                TextField("Custom \(title.lowercased())", text: $selection)
                    .accessibilityLabel("Custom \(title)")
            }
        }
    }

    private var showsFreeText: Bool {
        useFreeText || (!selection.isEmpty && !options.contains(selection))
    }

    private var pickerBinding: Binding<String> {
        Binding(
            get: {
                if useFreeText { return Self.otherTag }
                if selection.isEmpty { return "" }
                return options.contains(selection) ? selection : Self.otherTag
            },
            set: { newValue in
                if newValue == Self.otherTag {
                    useFreeText = true
                    if options.contains(selection) { selection = "" }
                } else {
                    useFreeText = false
                    selection = newValue
                }
            }
        )
    }
}
