# Focus Check-in

La demo iPhone stima la probabilità che una durata di focus sia gestibile. Con 45 minuti ed energia media, per esempio, confronta 35, 45 e 55 minuti. All’inizio usa il modello Core ML addestrato su sessioni simulate. Dopo cinque sessioni con un esito noto, corregge le stime con il tuo storico.

## Avvio su iPhone

1. Apri [FocusCheckIn.xcodeproj](FocusCheckIn.xcodeproj) in Xcode e seleziona lo schema **FocusCheckIn**.
2. Scegli un simulatore iPhone con iOS 26 o successivo e avvia con **Run**.
3. Scegli durata ed energia. Puoi inserire le ore di sonno, leggerle da **Salute** con il tuo consenso, oppure lasciare il campo vuoto. Se le inserisci a mano, quel valore ha la precedenza.
4. Tocca **Inizia sessione**. Alla scadenza, oppure dopo **Termina prima**, rispondi con un tocco. Se chiudi l’app, alla riapertura ritrovi il timer o la domanda in sospeso.
5. Dopo tre risposte consecutive **Avrei continuato** su sessioni con la stessa energia e durata entro dieci minuti da quella scelta, l’app può proporti dieci minuti in più. Tocca la proposta per cambiare la durata e premi **Inizia sessione** quando sei pronto.

Le sessioni restano in un archivio SwiftData sul dispositivo, escluso dai backup e senza sincronizzazione. Gli imprevisti e i compiti finiti prima restano nello storico con esito indeterminato. Il peso di una sessione nel calcolo si dimezza ogni 30 giorni. Quando sono disponibili cinque notti precedenti distinte, l’app confronta il sonno della sessione con la mediana di quelle notti. Se il sonno manca, usa durata ed energia.

## Verifica della personalizzazione

- Usa **Product → Test** sul simulatore per controllare le stime iniziali, i limiti di durata, la scadenza, lo stop anticipato e la ripresa del timer e del feedback.
- Per la prova su iPhone, scegli il tuo Team in **Signing & Capabilities**, usa un identificativo compatibile con il Team e verifica che HealthKit sia abilitato. Avvia l’app su un iPhone con sonno registrato in Salute nelle ultime 24 ore. Tocca **Leggi il sonno da Salute**, consenti la lettura e controlla il totale mostrato. Disattiva la lettura nell’app e prova anche il campo manuale.
- Per il pilot sull’iPhone, espandi **Verifica del pilot** dopo una sessione con esito noto. Un Brier score più basso indica un errore minore. L’app salva le tre probabilità all’avvio di ogni sessione, prima del feedback, e le confronta sulle stesse sessioni. Nelle prime sessioni le varianti possono coincidere, perché lo storico è ancora insufficiente.

Esegui questo comando dalla cartella principale della challenge per verificare sul Mac l’aggiornamento delle stime, il salvataggio senza duplicati, il calcolo del sonno e la proposta di estensione.

```sh
xcrun --sdk macosx swiftc -swift-version 6 \
  FocusCheckIn/App/{DurationEstimate,FocusEnergy,SessionFeedback,FocusSession,SleepObservation,Personalization,FocusHistory}.swift \
  FocusCheckIn/Verification/VerifyPersonalization.swift -o /tmp/verify-focus-personalization
/tmp/verify-focus-personalization
```

## Rigenerazione del modello su Mac

Esegui dalla cartella principale della challenge, con Xcode selezionato come toolchain.

```sh
swift FocusCheckIn/Training/Train.swift \
  focus-sessioni-sintetiche.csv \
  FocusCheckIn/App/FocusDurationClassifier.mlmodel
```

Lo script convalida il CSV, usa il seme 42 per separare le classi in 240 righe di addestramento e 60 di test, quindi addestra `MLLogisticRegressionClassifier`. Verifica il file esportato caricandolo con Core ML. Stampa l’hash degli indici di test, la matrice di confusione, il Brier score e alcune stime da confrontare con l’app. Al prossimo build, Xcode rigenera l’interfaccia Swift dal file Core ML.

Per ripetere la verifica senza sostituire il modello dell’app, passa un secondo percorso di output con estensione `.mlmodel` e confronta l’hash del test con quello dell’esecuzione precedente.

## Preparazione delle risposte del Google Modulo

Esporta le risposte del modulo. Conserva l’export originale con i timestamp e produci una tabella con le tre colonne `minuti_pianificati`, `energia_iniziale` e `durata_gestibile`. Normalizza *Low*, *Medium* e *High* in `bassa`, `media` e `alta`.

| Esito italiano | Esito inglese | Etichetta |
| --- | --- | --- |
| Completata, durata giusta | I finished, and the length felt right | `si` |
| Completata, avrei continuato | I finished and could have kept going | `si` |
| Completata, durata troppo lunga | I finished, but it felt too long | `no` |
| Terminata prima per stanchezza | I stopped early · I felt tired | `no` |
| Terminata prima per imprevisto o compito concluso | I stopped early · Something unexpected came up / I finished the task | Escludi dall’addestramento |

I minuti effettivi aiutano a interpretare un’interruzione. Il classificatore Core ML riceve solo i minuti previsti e l’energia dichiarata prima della sessione. Per un futuro addestramento del classificatore di partenza, usa i timestamp per tenere da parte le sessioni del modulo più recenti e confronta, sulle stesse righe, la versione con la sola durata e quella con durata ed energia. La personalizzazione nell’app usa invece il feedback raccolto dal timer sul singolo dispositivo.
