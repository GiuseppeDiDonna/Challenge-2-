struct DurationEstimate: Identifiable {
    static let allowedMinutes = 5...180

    let minutes: Int
    let probability: Double

    var id: Int { minutes }

    static func candidates(around minutes: Int) -> [Int] {
        [minutes - 10, minutes, minutes + 10].filter(allowedMinutes.contains)
    }
}
