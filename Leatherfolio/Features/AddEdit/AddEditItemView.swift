import SwiftUI
import SwiftData
import PhotosUI

/// One form for both add (item == nil) and edit (item != nil).
struct AddEditItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model: AddEditItemModel
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var showingSaveError = false

    init(item: Item?) {
        _model = State(initialValue: AddEditItemModel(item: item))
    }

    var body: some View {
        NavigationStack {
            Form {
                photosSection
                basicsSection
                flagsSection
                costsSection
                acquiredSection
                notesSection
            }
            .navigationTitle(model.isEditing ? "Edit Item" : "New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!model.canSave)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in
                    model.newPhotoDatas.append(data)
                }
                .ignoresSafeArea()
            }
            .alert("Couldn't save item", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Something went wrong writing to the library. Please try again.")
            }
            .onChange(of: selectedPickerItems) {
                Task { await loadPickedPhotos() }
            }
        }
    }

    // MARK: Sections

    private var photosSection: some View {
        Section("Photos") {
            if !model.newPhotoDatas.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.newPhotoDatas.enumerated()), id: \.offset) { _, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            PhotosPicker(selection: $selectedPickerItems,
                         maxSelectionCount: 5,
                         matching: .images) {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
        }
    }

    private var basicsSection: some View {
        Section("Details") {
            TextField("Name", text: $model.name)
            Picker("Category", selection: $model.category) {
                ForEach(ItemCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            // Phase 2 injection point: when CatalogSeed provides options,
            // these two fields become cascading pickers. Empty options mean
            // free-text — all of Phase 1.
            if model.sizeOptions.isEmpty {
                TextField("Size", text: $model.sizeText)
            } else {
                Picker("Size", selection: $model.sizeText) {
                    Text("None").tag("")
                    ForEach(model.sizeOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }
            if model.colorOptions.isEmpty {
                TextField("Color", text: $model.colorText)
            } else {
                Picker("Color", selection: $model.colorText) {
                    Text("None").tag("")
                    ForEach(model.colorOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }
            Picker("Leather", selection: $model.leatherType) {
                Text("None").tag(LeatherType?.none)
                ForEach(LeatherType.allCases) { type in
                    Text(type.rawValue).tag(LeatherType?.some(type))
                }
            }
            Picker("Condition", selection: $model.condition) {
                Text("None").tag(ItemCondition?.none)
                ForEach(ItemCondition.allCases) { condition in
                    Text(condition.rawValue).tag(ItemCondition?.some(condition))
                }
            }
        }
    }

    private var flagsSection: some View {
        Section("Rating & Flags") {
            HStack {
                Text("Rating")
                Spacer()
                RatingControl(rating: $model.rating)
            }
            Toggle("Unicorn 🦄", isOn: $model.isUnicorn)
            Toggle("Favorite", isOn: $model.favorite)
            Toggle("Wishlist", isOn: $model.isWishlist)
        }
    }

    private var costsSection: some View {
        Section("Costs & Value") {
            currencyRow("My cost", text: $model.myCostText)
            currencyRow("Retail cost", text: $model.retailCostText)
            currencyRow("Estimated value", text: $model.estimatedValueText)
        }
    }

    private func currencyRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .multilineTextAlignment(.trailing)
                // .decimalPad rather than .numberPad: currency entry needs
                // the decimal-separator key. Parsed into Decimal via
                // DecimalParsing.decimal(from:) at save time.
                .keyboardType(.decimalPad)
                .frame(maxWidth: 120)
        }
    }

    private var acquiredSection: some View {
        Section {
            Toggle("Date acquired", isOn: $model.hasDateAcquired.animation())
            if model.hasDateAcquired {
                DatePicker("Acquired on", selection: $model.dateAcquired,
                           displayedComponents: .date)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $model.notes)
                .frame(minHeight: 96)
        }
    }

    // MARK: Actions

    private func save() {
        do {
            try model.save(in: modelContext)
            dismiss()
        } catch {
            showingSaveError = true
        }
    }

    private func loadPickedPhotos() async {
        for pickerItem in selectedPickerItems {
            if let data = try? await pickerItem.loadTransferable(type: Data.self) {
                model.newPhotoDatas.append(data)
            }
        }
        selectedPickerItems = []
    }
}
