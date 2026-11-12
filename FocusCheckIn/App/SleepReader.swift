import HealthKit

@MainActor
final class SleepReader {
    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: [sleepType])
    }

    func sleep(before date: Date) async throws -> SleepObservation? {
        let range = HKQuery.predicateForSamples(
            withStart: date.addingTimeInterval(-24 * 3600),
            end: date
        )
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map {
            HKQuery.predicateForCategorySamples(with: .equalTo, value: $0.rawValue)
        }
        let values = NSCompoundPredicate(orPredicateWithSubpredicates: asleep)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [range, values])
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: []
        )
        let samples = try await query.result(for: store)
        return SleepObservation.aggregate(samples.map { DateInterval(start: $0.startDate, end: $0.endDate) }, before: date)
    }
}
