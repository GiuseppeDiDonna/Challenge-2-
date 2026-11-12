import CoreML
import CreateML
import CryptoKit
import Foundation
import TabularData

let durationColumn = "minuti_pianificati"
let energyColumn = "energia_iniziale"
let targetColumn = "durata_gestibile"
let energies = ["bassa", "media", "alta"]
let labels = ["si", "no"]
let splitSeed = 42

struct TrainingError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

struct Session {
    let minutes: Double
    let energy: String
    let label: String
}

func table(_ sessions: [Session]) -> DataFrame {
    var frame = DataFrame()
    frame.append(column: Column(name: durationColumn, contents: sessions.map(\.minutes)))
    frame.append(column: Column(name: energyColumn, contents: sessions.map(\.energy)))
    frame.append(column: Column(name: targetColumn, contents: sessions.map(\.label)))
    return frame
}

func readSessions(from url: URL) throws -> [Session] {
    let frame = try DataFrame(
        contentsOfCSVFile: url,
        types: [durationColumn: .double, energyColumn: .string, targetColumn: .string]
    )
    guard Set(frame.columns.map(\.name)) == Set([durationColumn, energyColumn, targetColumn]) else {
        throw TrainingError("Il CSV deve contenere le tre colonne previste.")
    }
    let durations = frame[durationColumn, Double.self]
    let inputEnergies = frame[energyColumn, String.self]
    let outcomes = frame[targetColumn, String.self]
    return try (0..<frame.rows.count).map { index in
        guard let minutes = durations[index], minutes.isFinite, minutes > 0,
              let energy = inputEnergies[index], energies.contains(energy),
              let label = outcomes[index], labels.contains(label)
        else {
            throw TrainingError("Riga \(index + 2): durata, energia o etichetta non valida.")
        }
        return Session(minutes: minutes, energy: energy, label: label)
    }
}

func split(_ sessions: [Session]) throws -> (train: [Int], test: [Int]) {
    let ordered = sessions.indices.map { index in
        (index: index, rank: SHA256.hash(data: Data("\(splitSeed):\(index)".utf8)))
    }.sorted { $0.rank.lexicographicallyPrecedes($1.rank) }
    var train: [Int] = []
    var test: [Int] = []
    for label in labels {
        let indices = ordered.map(\.index).filter { sessions[$0].label == label }
        guard indices.count >= 2 else {
            throw TrainingError("Servono almeno due righe per la classe «\(label)».")
        }
        let testCount = max(1, Int((Double(indices.count) * 0.2).rounded()))
        train.append(contentsOf: indices.dropFirst(testCount))
        test.append(contentsOf: indices.prefix(testCount))
    }
    // Preserve the shuffled order instead of passing class-grouped rows to validation.
    let testSet = Set(test)
    let shuffledIndices = ordered.map(\.index)
    guard train.count + test.count == sessions.count, Set(train).isDisjoint(with: testSet) else {
        throw TrainingError("Suddivisione del dataset non valida.")
    }
    return (shuffledIndices.filter { !testSet.contains($0) }, test.sorted())
}

func predict(_ model: MLModel, minutes: Double, energy: String) throws -> (label: String, probability: Double) {
    let description = model.modelDescription
    guard let labelName = description.predictedFeatureName,
          let probabilitiesName = description.predictedProbabilitiesName
    else {
        throw TrainingError("Il modello non espone le uscite di classificazione.")
    }
    let input = try MLDictionaryFeatureProvider(dictionary: [durationColumn: minutes, energyColumn: energy])
    let prediction = try model.prediction(from: input)
    guard let label = prediction.featureValue(for: labelName)?.stringValue, labels.contains(label),
          let probability = prediction.featureValue(for: probabilitiesName)?.dictionaryValue["si"]?.doubleValue,
          probability.isFinite, (0...1).contains(probability)
    else {
        throw TrainingError("Il modello non ha restituito una probabilità valida per «si».")
    }
    return (label, probability)
}

func run() throws {
    guard CommandLine.arguments.count == 3,
          CommandLine.arguments[2].hasSuffix(".mlmodel")
    else {
        throw TrainingError("Uso: swift Train.swift <dataset.csv> <modello.mlmodel>")
    }
    let input = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    let sessions = try readSessions(from: input)
    let indices = try split(sessions)
    let training = indices.train.map { sessions[$0] }
    let testing = indices.test.map { sessions[$0] }
    let classifier = try MLLogisticRegressionClassifier(
        trainingData: table(training),
        targetColumn: targetColumn,
        featureColumns: [durationColumn, energyColumn]
    )

    // Evaluate the exported Core ML model through the same runtime used by the app.
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let exported = temporary.appending(path: output.lastPathComponent)
    try classifier.write(to: exported, metadata: MLModelMetadata(
        author: "Focus Check-in",
        shortDescription: "Stima della gestibilità di una sessione di focus da dati sintetici.",
        version: "synthetic-v1"
    ))
    let compiled = try MLModel.compileModel(at: exported)
    defer { try? FileManager.default.removeItem(at: compiled) }
    let model = try MLModel(contentsOf: compiled)
    guard Set(model.modelDescription.inputDescriptionsByName.keys) == Set([durationColumn, energyColumn]) else {
        throw TrainingError("Gli input del modello esportato non corrispondono al CSV.")
    }

    let prevalence = Double(training.filter { $0.label == "si" }.count) / Double(training.count)
    var confusion: [String: [String: Int]] = [:]
    var brier = 0.0
    var baselineBrier = 0.0
    for session in testing {
        let prediction = try predict(model, minutes: session.minutes, energy: session.energy)
        confusion[session.label, default: [:]][prediction.label, default: 0] += 1
        let outcome = session.label == "si" ? 1.0 : 0.0
        brier += pow(prediction.probability - outcome, 2)
        baselineBrier += pow(prevalence - outcome, 2)
    }

    let splitDigest = SHA256.hash(data: Data(indices.test.map(String.init).joined(separator: ",").utf8))
    print("Addestramento: \(training.count), test: \(testing.count). Seme: \(splitSeed).")
    print("SHA-256 degli indici del test: \(splitDigest.map { String(format: "%02x", $0) }.joined())")
    print("Confusione (reale \\ predetto): si / no")
    for label in labels {
        print("\(label): \(confusion[label]?["si"] ?? 0) / \(confusion[label]?["no"] ?? 0)")
    }
    print(String(format: "Brier modello: %.6f; Brier baseline (p = %.4f): %.6f",
                 brier / Double(testing.count), prevalence, baselineBrier / Double(testing.count)))
    for energy in energies {
        for minutes in [5, 15, 25, 35, 45, 55, 90, 170, 180] {
            let probability = try predict(model, minutes: Double(minutes), energy: energy).probability
            print(String(format: "%3d min, %@: p(si) = %.8f", minutes, energy, probability))
        }
    }

    try Data(contentsOf: exported).write(to: output, options: .atomic)
    print("Modello esportato: \(output.path)")
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("Errore: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
