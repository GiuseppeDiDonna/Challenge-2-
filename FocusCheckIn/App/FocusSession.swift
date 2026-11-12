import Foundation
import SwiftData

@Model
final class FocusSession {
    @Attribute(.unique) var sessionID: UUID
    var startedAt: Date
    var plannedMinutes: Int
    var energyCode: String
    var sleepHours: Double?
    var sleepNight: String?
    var sleepDeviation: Double?
    var endedAt: Date?
    var actualMinutes: Double?
    var feedbackCode: String?
    var feedbackAt: Date?
    var baseProbability: Double?
    var personalProbability: Double?
    var sleepProbability: Double?

    init(startedAt: Date, plannedMinutes: Int, energy: FocusEnergy, sleep: SleepObservation?, sleepDeviation: Double?,
         forecast: Personalization.Forecast?) {
        self.sessionID = UUID()
        self.startedAt = startedAt
        self.plannedMinutes = plannedMinutes
        energyCode = energy.rawValue
        sleepHours = sleep?.hours
        sleepNight = sleep?.night
        self.sleepDeviation = sleepDeviation
        baseProbability = forecast?.base
        personalProbability = forecast?.personal
        sleepProbability = forecast?.withSleep
    }

    var deadline: Date {
        startedAt.addingTimeInterval(Double(plannedMinutes) * 60)
    }

    var feedback: SessionFeedback? {
        feedbackCode.flatMap(SessionFeedback.init(rawValue:))
    }

    var feedbackChoices: [SessionFeedback] {
        guard let endedAt else { return [] }
        return endedAt < deadline ? SessionFeedback.stoppedEarly : SessionFeedback.atDeadline
    }
}
