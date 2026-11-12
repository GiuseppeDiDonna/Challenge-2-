import CoreML
import SwiftUI

struct FocusCheckInView: View {
    private enum Field: Hashable { case duration, sleep }

    let history: FocusHistory
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("readsSleepFromHealth") private var readsSleepFromHealth = false
    @State private var minutes: Int? = 45
    @State private var energy: FocusEnergy?
    @State private var manualSleepHours: Double?
    @State private var healthSleep: SleepObservation?
    @State private var sleepReader = SleepReader()
    @State private var requestingHealth = false
    @State private var healthMessage: LocalizedStringResource?
    @State private var starting = false
    @State private var classifier: Result<FocusDurationClassifier, any Error>?
    @State private var estimates: [DurationEstimate] = []
    @State private var predictionFailed = false
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                if history.failed {
                    Section {
                        Label("Impossibile accedere allo storico locale.", systemImage: "exclamationmark.circle")
                        Button("Riprova", action: refreshHistory)
                    }
                }
                if let session = history.active {
                    FocusSessionView(session: session, history: history)
                } else {
                    setup
                    predictions
                }
                if let scores = history.pilotScores {
                    Section {
                        DisclosureGroup("Verifica del pilot") {
                            LabeledContent("Sessioni valutate", value: scores.count.formatted())
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Sessioni valutate")
                                .accessibilityValue(scores.count.formatted())
                                .accessibilityIdentifier("pilotSessionCount")
                            LabeledContent("Brier · Modello di partenza", value: scores.base.formatted(.number.precision(.fractionLength(3))))
                            LabeledContent("Brier · Durata ed energia", value: scores.personal.formatted(.number.precision(.fractionLength(3))))
                            LabeledContent("Brier · Con il sonno", value: scores.withSleep.formatted(.number.precision(.fractionLength(3))))
                        }
                    }
                }
            }
            .navigationTitle("Focus Check-in")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("Fine", action: dismissKeyboard)
                }
            }
        }
        .task {
            refreshHistory()
            await refreshSleep()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            refreshHistory()
            Task { await refreshSleep() }
        }
        .onChange(of: minutes, updateEstimates)
        .onChange(of: energy, updateEstimates)
        .onChange(of: manualSleepHours, updateEstimates)
        .onChange(of: history.active?.sessionID, updateEstimates)
    }

    private var setup: some View {
        Section("Sessione") {
            TextField("Durata in minuti", value: $minutes, format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .duration)
                .accessibilityIdentifier("plannedMinutes")
            Picker("Energia iniziale", selection: $energy) {
                Text("Seleziona").tag(nil as FocusEnergy?)
                ForEach(FocusEnergy.allCases) { level in
                    Text(level.title).tag(Optional(level))
                }
            }
            .accessibilityIdentifier("initialEnergy")
            TextField("Ore di sonno (facoltativo)", value: $manualSleepHours, format: .number)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .sleep)
            if !hasValidSleep {
                Text("Inserisci un valore tra 0 e 24 ore.")
                    .foregroundStyle(.secondary)
            } else if let healthSleep, manualSleepHours == nil {
                LabeledContent("Sonno da Salute", value: healthSleep.hours.formatted(.number.precision(.fractionLength(1))) + " h")
            }
            if sleepReader.isAvailable {
                if readsSleepFromHealth {
                    Button("Disattiva lettura da Salute", action: disableHealth)
                } else {
                    Button("Leggi il sonno da Salute", action: enableHealth)
                        .disabled(requestingHealth)
                }
                if let healthMessage {
                    Text(healthMessage).foregroundStyle(.secondary)
                }
            }
            if let minutes, let energy, history.suggestsExtension(minutes: minutes, energy: energy) {
                Button("Prova 10 minuti in più") { self.minutes = minutes + 10 }
            }
            Button("Inizia sessione", action: beginSession)
                .disabled(!hasValidDuration || !hasValidSleep || energy == nil || history.failed || starting || requestingHealth)
        }
        .disabled(starting)
    }

    private var predictions: some View {
        Section {
            if !hasValidDuration {
                Text("Inserisci una durata tra 5 e 180 minuti.")
                    .foregroundStyle(.secondary)
            } else if energy == nil {
                Text("Seleziona l’energia per vedere le stime.")
                    .foregroundStyle(.secondary)
            } else if predictionFailed {
                Label("Impossibile calcolare la stima.", systemImage: "exclamationmark.circle")
            } else {
                ForEach(estimates) { estimate in
                    LabeledContent {
                        Text(estimate.probability, format: .percent.precision(.fractionLength(1)))
                            .monospacedDigit()
                    } label: {
                        if estimate.minutes == minutes {
                            Text("\(estimate.minutes) min · Durata scelta")
                                .fontWeight(.semibold)
                        } else {
                            Text("\(estimate.minutes) min")
                        }
                    }
                    .accessibilityIdentifier("estimate-\(estimate.minutes)")
                }
            }
        } header: {
            Text("Probabilità che la durata sia gestibile")
        } footer: {
            if history.model.personal != nil {
                Text("Stime adattate al tuo storico.")
            } else {
                Text("Stime basate su sessioni simulate.")
            }
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
    }

    private var hasValidDuration: Bool {
        guard let minutes else { return false }
        return DurationEstimate.allowedMinutes.contains(minutes)
    }

    private var hasValidSleep: Bool {
        guard let manualSleepHours else { return true }
        return manualSleepHours.isFinite && (0...24).contains(manualSleepHours)
    }

    private func sleepObservation(at date: Date) -> SleepObservation? {
        if let manualSleepHours, hasValidSleep {
            return SleepObservation(hours: manualSleepHours, endingAt: date)
        }
        return readsSleepFromHealth ? healthSleep : nil
    }

    private func enableHealth() {
        guard !requestingHealth else { return }
        requestingHealth = true
        Task {
            defer { requestingHealth = false }
            do {
                try await sleepReader.requestAccess()
                readsSleepFromHealth = true
                await refreshSleep()
            } catch {
                healthMessage = "Impossibile accedere a Salute. Puoi inserire le ore manualmente."
            }
        }
    }

    private func disableHealth() {
        readsSleepFromHealth = false
        healthSleep = nil
        healthMessage = nil
        updateEstimates()
    }

    private func refreshSleep() async {
        guard readsSleepFromHealth, sleepReader.isAvailable else { return }
        let result = try? await sleepReader.sleep(before: .now)
        guard readsSleepFromHealth else { return }
        healthSleep = result
        healthMessage = result == nil ? "Nessun dato di sonno disponibile." : nil
        updateEstimates()
    }

    private func refreshHistory() {
        history.reload()
        if let session = history.active, session.endedAt == nil, session.deadline <= .now {
            history.finish(session)
        }
        updateEstimates()
    }

    private func beginSession() {
        guard !starting, let minutes, hasValidDuration, hasValidSleep, let energy else { return }
        dismissKeyboard()
        starting = true
        Task {
            defer { starting = false }
            let start = Date.now
            let sleep: SleepObservation?
            if manualSleepHours == nil, readsSleepFromHealth, sleepReader.isAvailable {
                sleep = try? await sleepReader.sleep(before: start)
            } else {
                sleep = sleepObservation(at: start)
            }
            let deviation = history.sleepDeviation(for: sleep, before: start)
            let prediction = try? forecast(minutes: minutes, energy: energy, deviation: deviation)
            history.start(FocusSession(startedAt: start, plannedMinutes: minutes, energy: energy,
                                       sleep: sleep, sleepDeviation: deviation, forecast: prediction))
            if history.active != nil { manualSleepHours = nil }
        }
    }

    private func updateEstimates() {
        estimates = []
        predictionFailed = false
        guard let energy, let minutes, hasValidDuration else { return }

        let now = Date.now
        let deviation = history.sleepDeviation(for: sleepObservation(at: now), before: now)
        do {
            estimates = try DurationEstimate.candidates(around: minutes).map { candidate in
                let prediction = try forecast(minutes: candidate, energy: energy, deviation: deviation)
                return DurationEstimate(minutes: candidate, probability: prediction.withSleep)
            }
        } catch {
            predictionFailed = true
        }
    }

    private func forecast(minutes: Int, energy: FocusEnergy, deviation: Double?) throws -> Personalization.Forecast {
        let loadedClassifier = classifier ?? Result {
            try FocusDurationClassifier(configuration: MLModelConfiguration())
        }
        classifier = loadedClassifier
        let prediction = try loadedClassifier.get().prediction(
            minuti_pianificati: Double(minutes),
            energia_iniziale: energy.rawValue
        )
        guard let probability = prediction.durata_gestibileProbability["si"],
              probability.isFinite, (0...1).contains(probability) else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        return history.model.forecast(base: probability, minutes: minutes, energy: energy, sleepDeviation: deviation)
    }
}
