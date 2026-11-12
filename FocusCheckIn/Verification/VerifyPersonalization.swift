import Foundation

@main
struct VerifyPersonalization {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Calendar.current.startOfDay(for: .now).addingTimeInterval(12 * 3600)
        let successFolder = directory.appending(path: "success")
        let success = FocusHistory(directory: successFolder)
        let fatigue = FocusHistory(directory: directory.appending(path: "fatigue"))
        precondition(!success.failed && !fatigue.failed)

        let hour: TimeInterval = 3600
        func forecast(_ history: FocusHistory, deviation: Double? = nil) -> Personalization.Forecast {
            history.model.forecast(base: 0.7, minutes: 45, energy: .high, sleepDeviation: deviation)
        }
        @discardableResult
        func add(_ feedback: SessionFeedback, to history: FocusHistory, on date: Date, hours: Double = 6) -> FocusSession {
            let sleep = SleepObservation(hours: hours, endingAt: date.addingTimeInterval(-hour))
            let deviation = history.sleepDeviation(for: sleep, before: date)
            let session = FocusSession(startedAt: date, plannedMinutes: 45, energy: .high, sleep: sleep,
                                       sleepDeviation: deviation, forecast: forecast(history, deviation: deviation))
            history.start(session)
            let elapsed = SessionFeedback.stoppedEarly.contains(feedback) ? 20.0 : 60.0
            history.finish(session, now: date.addingTimeInterval(elapsed * 60))
            history.record(feedback, for: session, now: date.addingTimeInterval(hour))
            precondition(!history.failed && history.active == nil)
            return session
        }

        for index in 0..<7 {
            let date = now.addingTimeInterval(Double(index - 10) * 24 * hour)
            let completed = add(.couldContinue, to: success, on: date)
            let stopped = add(.tired, to: fatigue, on: date)
            precondition(completed.actualMinutes == 45 && stopped.actualMinutes == 20)
            precondition(success.suggestsExtension(minutes: 45, energy: .high) == (index >= 2))
            precondition(!success.suggestsExtension(minutes: 45, energy: .medium))
            precondition(!success.suggestsExtension(minutes: 56, energy: .high))
            precondition(!success.suggestsExtension(minutes: .max, energy: .high))
            if index < 5 {
                precondition(completed.personalProbability == 0.7 && stopped.personalProbability == 0.7)
                precondition(completed.sleepDeviation == nil)
            } else {
                precondition(completed.personalProbability! > 0.7 && stopped.personalProbability! < 0.7)
                precondition(completed.sleepDeviation == 0 && stopped.sleepDeviation == 0)
            }
        }

        let successScore = forecast(success).personal
        let fatigueScore = forecast(fatigue).personal
        precondition(successScore > 0.7 && fatigueScore < 0.7)
        precondition(success.pilotScores!.personal < success.pilotScores!.base)
        precondition(fatigue.pilotScores!.personal < fatigue.pilotScores!.base)
        let session = add(.interrupted, to: success, on: now.addingTimeInterval(-3 * 24 * hour))
        precondition(abs(forecast(success).personal - successScore) < 0.00001)
        precondition(!success.suggestsExtension(minutes: 45, energy: .high))
        precondition(success.pilotScores?.count == 7)
        success.record(.interrupted, for: session)
        precondition(success.sessions.count == 8)
        success.record(.tired, for: session)
        success.record(.tired, for: session)
        let reopened = FocusHistory(directory: successFolder)
        precondition(reopened.sessions.count == 8 && reopened.pilotScores?.count == 8)
        precondition(reopened.sessions.first?.feedback == .tired)

        let blockedFolder = directory.appending(path: "retry")
        try Data().write(to: blockedFolder)
        let retry = FocusHistory(directory: blockedFolder)
        precondition(retry.failed)
        try FileManager.default.removeItem(at: blockedFolder)
        retry.reload()
        precondition(!retry.failed)

        let reference = FocusHistory(directory: directory.appending(path: "sleep"))
        for index in 0..<5 {
            let date = now.addingTimeInterval(Double(index - 11) * 24 * hour)
            add(.rightLength, to: reference, on: date)
        }
        for index in 0..<6 {
            let date = now.addingTimeInterval(Double(index - 6) * 24 * hour)
            let rested = index.isMultiple(of: 2)
            add(rested ? .rightLength : .tired, to: reference, on: date, hours: rested ? 8 : 4)
        }
        precondition(forecast(reference, deviation: 2).withSleep > forecast(reference, deviation: -2).withSleep)
        precondition(forecast(reference).withSleep == forecast(reference).personal)
        let examples = (0..<5).map { _ in
            Personalization.Example(minutes: 45, energy: .high, sleepDeviation: nil, base: 0.7, outcome: 1, date: now)
        }
        let fresh = Personalization.fit(examples, now: now)
        let older = Personalization.fit(examples, now: now.addingTimeInterval(30 * 24 * hour))
        precondition(fresh.forecast(base: 0.7, minutes: 45, energy: .high, sleepDeviation: nil).personal >
                     older.forecast(base: 0.7, minutes: 45, energy: .high, sleepDeviation: nil).personal)

        let sleep = SleepObservation.aggregate([
            DateInterval(start: now.addingTimeInterval(-25 * hour), end: now.addingTimeInterval(-23 * hour)),
            DateInterval(start: now.addingTimeInterval(-9 * hour), end: now.addingTimeInterval(-3 * hour)),
            DateInterval(start: now.addingTimeInterval(-6 * hour), end: now.addingTimeInterval(-2 * hour)),
            DateInterval(start: now.addingTimeInterval(-hour), end: now.addingTimeInterval(hour)),
        ], before: now)
        precondition(sleep?.hours == 9 && SleepObservation.aggregate([], before: now) == nil)
        let percent = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(1))
        print("Stima iniziale 70%. Completamenti: \(successScore.formatted(percent)). Stop per stanchezza: \(fatigueScore.formatted(percent)).")
        print("Persistenza, aggiornamenti senza duplicati, sonno, estensione e Brier: OK.")
    }
}
