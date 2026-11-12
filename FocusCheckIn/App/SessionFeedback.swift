import Foundation

enum SessionFeedback: String, Identifiable {
    case rightLength, couldContinue, tooLong, tired, taskFinished, interrupted

    static let atDeadline: [Self] = [.rightLength, .couldContinue, .tooLong]
    static let stoppedEarly: [Self] = [.tired, .taskFinished, .interrupted]

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .rightLength: "Durata giusta"
        case .couldContinue: "Avrei continuato"
        case .tooLong: "Durata troppo lunga"
        case .tired: "Per stanchezza"
        case .taskFinished: "Avevo finito il compito"
        case .interrupted: "Per un imprevisto"
        }
    }

    var outcome: Double? {
        switch self {
        case .rightLength, .couldContinue: 1
        case .tooLong, .tired: 0
        case .taskFinished, .interrupted: nil
        }
    }
}
