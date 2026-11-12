import Foundation

enum Personalization {
    struct Forecast {
        let base: Double
        let personal: Double
        let withSleep: Double
    }

    struct Example {
        let minutes: Int
        let energy: FocusEnergy
        let sleepDeviation: Double?
        let base: Double
        let outcome: Double
        let date: Date
    }

    struct Model {
        let personal: [Double]?
        let withSleep: [Double]?

        func forecast(base: Double, minutes: Int, energy: FocusEnergy, sleepDeviation: Double?) -> Forecast {
            let features = Personalization.features(minutes: minutes, energy: energy, sleepDeviation: sleepDeviation)
            let adjusted = Personalization.correct(base, weights: personal, features: features)
            let sleepAdjusted = sleepDeviation.map { _ in
                Personalization.correct(base, weights: withSleep, features: features)
            }
            return Forecast(base: base, personal: adjusted, withSleep: sleepAdjusted ?? adjusted)
        }
    }

    static let minimumOutcomes = 5
    static let minimumNights = 5

    static func fit(_ examples: [Example], now: Date) -> Model {
        guard examples.count >= minimumOutcomes else { return Model(personal: nil, withSleep: nil) }
        let withoutSleep = solve(examples, now: now, includeSleep: false)
        let hasSleepExamples = examples.contains { $0.sleepDeviation != nil }
        return Model(
            personal: withoutSleep,
            withSleep: hasSleepExamples ? solve(examples, now: now, includeSleep: true) ?? withoutSleep : withoutSleep
        )
    }

    private static func solve(_ examples: [Example], now: Date, includeSleep: Bool) -> [Double]? {
        let dimension = 5
        let penalty = 4.0
        let inputs = examples.map { example in
            let age = max(0, now.timeIntervalSince(example.date))
            let weight = exp2(-age / (30 * 86400))
            let x = features(minutes: example.minutes, energy: example.energy,
                             sleepDeviation: includeSleep ? example.sleepDeviation : nil)
            return (x: x, offset: logOdds(example.base), weight: weight, outcome: example.outcome)
        }
        // p(1-p) is at most 1/4. This bound gives a stable step for the penalized loss.
        let curvature = inputs.reduce(penalty) { sum, row in
            sum + 0.25 * row.weight * dot(row.x, row.x)
        }
        guard curvature.isFinite, curvature > 0 else { return nil }
        var weights = Array(repeating: 0.0, count: dimension)
        for _ in 0..<512 {
            var gradient = weights.map { penalty * $0 }
            for row in inputs {
                let residual = row.weight * (sigmoid(row.offset + dot(weights, row.x)) - row.outcome)
                for index in weights.indices {
                    gradient[index] += residual * row.x[index]
                }
            }
            guard gradient.allSatisfy(\.isFinite) else { return nil }
            if gradient.allSatisfy({ abs($0) < 0.00001 }) { return weights }
            for index in weights.indices {
                weights[index] -= gradient[index] / curvature
            }
        }
        return nil
    }

    private static func features(minutes: Int, energy: FocusEnergy, sleepDeviation: Double?) -> [Double] {
        [1, (Double(minutes) - 45) / 60, energy == .low ? 1 : 0, energy == .high ? 1 : 0,
         max(-4, min(4, sleepDeviation ?? 0)) / 2]
    }

    private static func correct(_ base: Double, weights: [Double]?, features: [Double]) -> Double {
        guard let weights else { return base }
        return sigmoid(logOdds(base) + dot(weights, features))
    }

    private static func logOdds(_ p: Double) -> Double {
        let bounded = max(0.000001, min(0.999999, p))
        return log(bounded / (1 - bounded))
    }

    private static func dot(_ x: [Double], _ y: [Double]) -> Double {
        zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private static func sigmoid(_ z: Double) -> Double {
        1 / (1 + exp(-z))
    }
}
