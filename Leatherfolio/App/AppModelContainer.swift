import SwiftData

enum AppConfig {
    /// CloudKit sync is OFF until Apple Developer signing exists.
    /// When flipping this on, change `cloudKitDatabase: .none` below to
    /// `.automatic` and add the iCloud capability — that is the whole flip,
    /// because the schema obeys every CloudKit rule already.
    static let cloudKitEnabled = false
}

@MainActor
enum AppModelContainer {
    /// The app's on-disk container. Tests use make(inMemory: true) instead.
    static let shared: ModelContainer = {
        do {
            return try make(inMemory: false)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    static func make(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([Item.self, Photo.self, Tag.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
