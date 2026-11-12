import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class FocusHistory {
    private let directory: URL
    @ObservationIgnored private var container: ModelContainer?
    private var context: ModelContext? { container?.mainContext }
    private(set) var sessions: [FocusSession] = []
    private(set) var model = Personalization.fit([], now: .now)
    private(set) var failed = false

    init(directory: URL) {
        self.directory = directory
        reload()
    }

    var active: FocusSession? {
        sessions.first { $0.feedbackCode == nil }
    }

    func reload(now: Date = .now) {
        do {
            if container == nil {
                container = try openStore()
            }
            let descriptor = FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            sessions = try context?.fetch(descriptor) ?? []
            model = Personalization.fit(examples, now: now)
            failed = false
        } catch {
            failed = true
            model = Personalization.fit([], now: now)
        }
    }

    func start(_ session: FocusSession) {
        guard let context, !failed, active == nil else { return }
        context.insert(session)
        save()
    }

    func finish(_ session: FocusSession, now: Date = .now) {
        guard session.endedAt == nil, session.feedbackCode == nil else { return }
        let end = max(session.startedAt, min(now, session.deadline))
        session.endedAt = end
        session.actualMinutes = end.timeIntervalSince(session.startedAt) / 60
        save()
    }

    func record(_ feedback: SessionFeedback, for session: FocusSession, now: Date = .now) {
        guard session.feedbackChoices.contains(feedback) else { return }
        if session.feedbackCode == feedback.rawValue { return }
        session.feedbackCode = feedback.rawValue
        session.feedbackAt = now
        save()
    }

    func sleepDeviation(for sleep: SleepObservation?, before date: Date) -> Double? {
        guard let sleep else { return nil }
        var byNight: [String: Double] = [:]
        for session in sessions where session.startedAt < date {
            if let night = session.sleepNight, let hours = session.sleepHours,
               night != sleep.night, byNight[night] == nil {
                byNight[night] = hours
            }
        }
        let sorted = byNight.values.sorted()
        guard sorted.count >= Personalization.minimumNights else { return nil }
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return sleep.hours - median
    }

    func suggestsExtension(minutes: Int, energy: FocusEnergy) -> Bool {
        guard DurationEstimate.allowedMinutes.contains(minutes),
              DurationEstimate.allowedMinutes.contains(minutes + 10) else { return false }
        let recent = sessions.lazy.filter {
            $0.energyCode == energy.rawValue && abs($0.plannedMinutes - minutes) <= 10 && $0.feedbackCode != nil
        }.prefix(3)
        return recent.count == 3 && recent.allSatisfy { $0.feedback == .couldContinue }
    }

    var pilotScores: (count: Int, base: Double, personal: Double, withSleep: Double)? {
        var count = 0
        var base = 0.0
        var personal = 0.0
        var sleep = 0.0
        for session in sessions {
            guard let outcome = session.feedback?.outcome, let p0 = session.baseProbability,
                  let p1 = session.personalProbability, let p2 = session.sleepProbability else { continue }
            count += 1
            base += pow(p0 - outcome, 2)
            personal += pow(p1 - outcome, 2)
            sleep += pow(p2 - outcome, 2)
        }
        guard count > 0 else { return nil }
        return (count, base / Double(count), personal / Double(count), sleep / Double(count))
    }

    private var examples: [Personalization.Example] {
        sessions.compactMap { session in
            guard let energy = FocusEnergy(rawValue: session.energyCode), let outcome = session.feedback?.outcome,
                  let base = session.baseProbability else { return nil }
            return .init(minutes: session.plannedMinutes, energy: energy, sleepDeviation: session.sleepDeviation,
                         base: base, outcome: outcome, date: session.startedAt)
        }
    }

    private func openStore() throws -> ModelContainer {
        var folder = directory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let configuration = ModelConfiguration(url: folder.appending(path: "history.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: FocusSession.self, configurations: configuration)
        container.mainContext.autosaveEnabled = false
        return container
    }

    private func save() {
        guard let context else { return }
        do {
            try context.save()
            reload()
        } catch {
            context.rollback()
            failed = true
        }
    }
}
