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
    @State private var importTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?

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
            .disabled(isInteractionBusy)
            .navigationTitle(model.isEditing ? "Edit Item" : "New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isInteractionBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!model.canSave || isInteractionBusy)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { result in
                    switch result {
                    case .success(let data):
                        model.queueCameraPhoto(data)
                    case .failure:
                        model.photoImportErrorMessage =
                            "The camera photo couldn't be imported. Your item details and other photos are unchanged."
                    }
                }
                .ignoresSafeArea()
            }
            .alert("Couldn't save item", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Something went wrong writing to the library. Please try again.")
            }
            .alert("Couldn't import photo", isPresented: importErrorPresented) {
                Button("OK", role: .cancel) {
                    model.photoImportErrorMessage = nil
                }
            } message: {
                Text(model.photoImportErrorMessage ?? "The selected photo couldn't be imported.")
            }
            .onChange(of: selectedPickerItems) {
                let items = selectedPickerItems
                guard !items.isEmpty else { return }
                selectedPickerItems = []
                startImport(using: items.map { pickerItem in
                    {
                        guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                            throw PhotoImportLoadError.noData
                        }
                        return data
                    }
                })
            }
            .task {
                await model.lookupUPCIfNeeded()
            }
            .interactiveDismissDisabled(isInteractionBusy)
        }
    }

    // MARK: Sections

    private var photosSection: some View {
        Section("Photos") {
            if !model.visibleExistingPhotos.isEmpty || !model.queuedPhotos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.visibleExistingPhotos) { draft in
                            ExistingPhotoEditorCard(model: model, draft: draft)
                        }
                        ForEach(model.queuedPhotos) { draft in
                            QueuedPhotoEditorCard(model: model, draft: draft)
                        }
                    }
                }
            }
            PhotosPicker(selection: $selectedPickerItems,
                         maxSelectionCount: 5,
                         matching: .images) {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
            .disabled(isInteractionBusy || totalPhotoCount >= 5)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
                .disabled(isInteractionBusy || totalPhotoCount >= 5)
            }
            if model.isImporting {
                HStack {
                    ProgressView()
                    Text("Importing photos…")
                        .foregroundStyle(.secondary)
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

    private var totalPhotoCount: Int {
        model.visibleExistingPhotos.count + model.queuedPhotos.count
    }

    private var isInteractionBusy: Bool {
        importTask != nil || saveTask != nil || model.isBusy
    }

    private var importErrorPresented: Binding<Bool> {
        Binding(
            get: { model.photoImportErrorMessage != nil },
            set: { if !$0 { model.photoImportErrorMessage = nil } })
    }

    private func save() {
        guard saveTask == nil, importTask == nil else { return }
        saveTask = Task { @MainActor in
            do {
                _ = try await model.save(in: modelContext)
                saveTask = nil
                dismiss()
            } catch {
                saveTask = nil
                showingSaveError = true
            }
        }
    }

    private func startImport(using loaders: [PhotoDataLoader]) {
        guard importTask == nil, saveTask == nil else { return }
        importTask = Task { @MainActor in
            await model.importPhotos(using: loaders)
            importTask = nil
        }
    }
}

private enum PhotoImportLoadError: Error {
    case noData
}

private struct ExistingPhotoEditorCard: View {
    @Bindable var model: AddEditItemModel
    let draft: ExistingPhotoDraft
    @State private var image: UIImage?

    var body: some View {
        photoEditorCard(
            id: draft.id,
            caption: Binding(
                get: { model.caption(for: draft.id) },
                set: { model.updateCaption($0, for: draft.id) }),
            isPrimary: model.primaryPhotoID == draft.id,
            remove: { model.removeExistingPhoto(id: draft.id) })
        .task(id: draft.id) {
            let requestedPhotoID = draft.id
            guard let photo = model.existingPhoto(for: requestedPhotoID) else {
                guard !Task.isCancelled,
                      model.visibleExistingPhotos.contains(where: { $0.id == requestedPhotoID }),
                      model.existingPhoto(for: requestedPhotoID) == nil else { return }
                image = nil
                return
            }
            let loadedImage = await ImageStore.shared.thumbnail(for: requestedPhotoID) {
                photo.imageData
            }
            guard !Task.isCancelled,
                  model.visibleExistingPhotos.contains(where: { $0.id == requestedPhotoID }),
                  model.existingPhoto(for: requestedPhotoID)?.id == requestedPhotoID else { return }
            image = loadedImage
        }
    }

    private func photoEditorCard(
        id: UUID,
        caption: Binding<String>,
        isPrimary: Bool,
        remove: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            editorImage(image)
            TextField("Caption", text: caption)
                .textFieldStyle(.roundedBorder)
                .frame(width: 124)
            HStack {
                Button {
                    model.choosePrimary(photoID: id)
                } label: {
                    Image(systemName: isPrimary ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct QueuedPhotoEditorCard: View {
    @Bindable var model: AddEditItemModel
    let draft: QueuedPhoto
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            editorImage(image)
            TextField("Caption", text: Binding(
                get: { model.caption(for: draft.id) },
                set: { model.updateCaption($0, for: draft.id) }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 124)
            HStack {
                Button {
                    model.choosePrimary(photoID: draft.id)
                } label: {
                    Image(systemName: model.primaryPhotoID == draft.id ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) {
                    model.removeQueuedPhoto(id: draft.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .task(id: draft.id) {
            let requestedPhotoID = draft.id
            let requestedData = draft.data
            let loadedImage = await ImageStore.shared.displayImage(
                from: requestedData,
                maxDimension: ImageStore.thumbnailMaxDimension)
            guard !Task.isCancelled,
                  model.queuedPhotos.first(where: { $0.id == requestedPhotoID })?.data
                    == requestedData else { return }
            image = loadedImage
        }
    }
}

@ViewBuilder
private func editorImage(_ image: UIImage?) -> some View {
    if let image {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 124, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    } else {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.secondarySystemBackground))
            .frame(width: 124, height: 96)
            .overlay { ProgressView() }
    }
}
