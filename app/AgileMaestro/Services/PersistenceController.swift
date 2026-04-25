import CoreData
import os

/// Manages the Core Data stack for AgileMaestro.
///
/// Uses NSPersistentContainer backed by the AgileMaestro.xcdatamodeld schema.
/// The schema is currently empty and serves as a placeholder for future
/// caching or preferences entities.
final class PersistenceController: Sendable {

    // MARK: - Shared Instances

    /// Singleton for production use.
    static let shared = PersistenceController()

    /// In-memory instance for SwiftUI previews and unit tests.
    static let preview = PersistenceController(inMemory: true)

    // MARK: - Properties

    let container: NSPersistentContainer

    // MARK: - Init

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "AgileMaestro")

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions = [description]
        }

        container.loadPersistentStores { _, error in
            if let error {
                // In production, a failure here is unrecoverable.
                // Log the fault and crash so the issue surfaces during development.
                Logger.persistence.fault("Core Data store failed to load: \(error)")
                fatalError("Core Data store failed to load: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
