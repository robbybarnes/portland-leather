import Foundation
import SwiftData

enum AppConfig {
    /// CloudKit sync is OFF until Apple Developer signing exists.
    /// When flipping this on, add the iCloud capability; the model
    /// configuration below already derives its database mode from this flag.
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

    static func configuration(
        inMemory: Bool,
        storeURL: URL? = nil
    ) -> ModelConfiguration {
        configuration(
            schema: makeSchema(),
            inMemory: inMemory,
            storeURL: storeURL)
    }

    static func make(
        inMemory: Bool,
        storeURL: URL? = nil
    ) throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = configuration(
            schema: schema,
            inMemory: inMemory,
            storeURL: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makeSchema() -> Schema {
        Schema([Item.self, Photo.self, Tag.self])
    }

    private static func configuration(
        schema: Schema,
        inMemory: Bool,
        storeURL: URL?
    ) -> ModelConfiguration {
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase =
            AppConfig.cloudKitEnabled ? .automatic : .none
        if let storeURL {
            precondition(!inMemory, "A custom store URL is only valid for an on-disk container")
            return ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: cloudKitDatabase)
        }
        return ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKitDatabase)
    }
}
