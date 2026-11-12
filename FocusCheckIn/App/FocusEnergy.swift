import Foundation

enum FocusEnergy: String, CaseIterable, Identifiable {
    case low = "bassa"
    case medium = "media"
    case high = "alta"

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .low: "Bassa"
        case .medium: "Media"
        case .high: "Alta"
        }
    }
}
