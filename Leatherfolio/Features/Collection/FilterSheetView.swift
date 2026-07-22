import SwiftUI

/// Filter sheet. Enum pickers list all cases; Color/Size pickers list
/// FilterOptions (seed values plus distinct values in the collection).
struct FilterSheetView: View {
    @Binding var filter: ItemFilter
    let options: FilterOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    Picker("Category", selection: $filter.category) {
                        Text("Any").tag(ItemCategory?.none)
                        ForEach(ItemCategory.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Leather", selection: $filter.leatherType) {
                        Text("Any").tag(LeatherType?.none)
                        ForEach(LeatherType.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Color", selection: $filter.color) {
                        Text("Any").tag(String?.none)
                        ForEach(options.colors, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Picker("Size", selection: $filter.size) {
                        Text("Any").tag(String?.none)
                        ForEach(options.sizes, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Picker("Condition", selection: $filter.condition) {
                        Text("Any").tag(ItemCondition?.none)
                        ForEach(ItemCondition.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                }
                Section("Flags") {
                    Toggle("Favorites only", isOn: $filter.favoritesOnly)
                    Toggle("Unicorns only", isOn: $filter.unicornsOnly)
                }
                Section("Rating") {
                    Stepper(value: $filter.minRating, in: 0...5) {
                        Text(filter.minRating == 0
                             ? "Any rating"
                             : "At least \(filter.minRating) star\(filter.minRating == 1 ? "" : "s")")
                    }
                }
                Section {
                    Button("Clear All Filters", role: .destructive) { filter.clearFilters() }
                        .disabled(filter.activeFilterCount == 0)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
