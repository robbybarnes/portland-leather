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

    init(item: Item? = nil, model: AddEditItemModel? = nil) {
        if let model {
            _model = State(initialValue: model)
        } else {
            _model = State(initialValue: AddEditItemModel(item: item))
        }
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
            .onChange(of: model.category) { model.categoryDidChange() }

            Picker("Line", selection: lineSelection) {
                Text("None").tag(String?.none)
                ForEach(model.lineOptions) { line in
                    Text(line.name).tag(String?.some(line.name))
                }
            }
            OptionPicker(title: "Size", options: model.sizeOptions, selection: $model.sizeText)
            OptionPicker(title: "Color", options: model.colorOptions, selection: $model.colorText)
            leatherTypeRow

            Picker("Condition", selection: $model.condition) {
                Text("None").tag(ItemCondition?.none)
                ForEach(ItemCondition.allCases) { condition in
                    Text(condition.rawValue).tag(ItemCondition?.some(condition))
                }
            }
        }
    }

    private var lineSelection: Binding<String?> {
        Binding(
            get: { model.selectedLineName },
            set: { newName in model.selectLine(newName.flatMap { model.catalog.line(named: $0) }) }
        )
    }

    @ViewBuilder private var leatherTypeRow: some View {
        let options = model.leatherTypeOptions
        Picker("Leather", selection: $model.leatherType) {
            Text("None").tag(LeatherType?.none)
            ForEach(options.isEmpty ? LeatherType.allCases : options + [.other]) { lt in
                Text(lt.rawValue).tag(LeatherType?.some(lt))
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
