import Foundation

enum TaskStatus: String, CaseIterable, Sendable {
    case backlog, doing, done

    var title: String {
        switch self {
        case .backlog: return "Backlog"
        case .doing:   return "In Progress"
        case .done:    return "Done"
        }
    }

    var next: TaskStatus? {
        switch self {
        case .backlog: return .doing
        case .doing:   return .done
        case .done:    return nil
        }
    }

    var previous: TaskStatus? {
        switch self {
        case .backlog: return nil
        case .doing:   return .backlog
        case .done:    return .doing
        }
    }
}

struct BoardUser: Identifiable, Hashable, Sendable {
    let id: UUID
    let email: String
    let name: String

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? String(email.prefix(2)).uppercased() : letters.joined().uppercased()
    }
}

struct BoardTask: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var status: TaskStatus
    var important: Bool
    var assigneeID: UUID?
    var position: Double
    var createdAt: Date
}
