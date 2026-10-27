import Foundation
import SwiftData

extension ModelContext {
    /// Lecture qui journalise l'erreur au lieu de l'avaler ; vide en cas d'échec.
    func fetchOrLog<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do {
            return try fetch(descriptor)
        } catch {
            Journal.store.error("Lecture de \(String(describing: T.self), privacy: .public) impossible : \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Nombre d'objets, 0 en cas d'échec (erreur journalisée).
    func fetchCountOrLog<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Int {
        do {
            return try fetchCount(descriptor)
        } catch {
            Journal.store.error("Comptage de \(String(describing: T.self), privacy: .public) impossible : \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    /// Enregistre les changements en attente, s'il y en a ; journalise l'échec.
    func saveOrLog() {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            Journal.store.error("Enregistrement impossible : \(error.localizedDescription, privacy: .public)")
        }
    }
}
