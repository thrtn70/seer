import AppKit
import SeerSpikeCore

@MainActor
final class SpikeCoordinator {
    private let tap = KeystrokeTap()
    private let overlay = OverlayPanel()
    private let client = CompletionClient()

    private var debounce: Task<Void, Never>?
    private var inflight: Task<Void, Never>?
    private var current: CaretCapture?
    private var remainingChunks: [String] = []
    private var lastFirstTokenMs: Double = 0

    private let kTab: Int64 = 48
    private let kEsc: Int64 = 53

    func start() {
        tap.onKeyDown = { [weak self] code, flags in
            guard let self else { return false }
            if !self.remainingChunks.isEmpty {
                if code == self.kTab {
                    let whole = flags.contains(.maskShift)
                    self.accept(whole: whole)
                    return true
                }
                if code == self.kEsc {
                    self.dismiss()
                    return true
                }
                self.dismiss()
            }
            self.scheduleSuggest()
            return false
        }
        tap.start()
        NSLog("[seer] coordinator started")
    }

    private func scheduleSuggest() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            await self?.requestSuggestion()
        }
    }

    private func requestSuggestion() async {
        inflight?.cancel()
        guard let cap = AXCapture.capture(), !cap.isSecure, let rect = cap.caretRect else {
            dismiss(); return
        }
        let before = cap.textBeforeCaret
        guard before.count >= 2 else { dismiss(); return }
        current = cap

        let started = DispatchTime.now()
        var firstTokenLogged = false

        inflight = Task { [weak self] in
            guard let self else { return }
            var accumulated = ""
            for await token in self.client.stream(prompt: before) {
                if Task.isCancelled { return }
                if !firstTokenLogged {
                    let ms = Double(DispatchTime.now().uptimeNanoseconds &- started.uptimeNanoseconds) / 1_000_000
                    self.lastFirstTokenMs = ms
                    NSLog("[seer] first-token %.1f ms", ms)
                    firstTokenLogged = true
                }
                accumulated += token
                self.remainingChunks = WordTokenizer.wordChunks(accumulated)   // ready to accept mid-stream
                self.overlay.show(text: accumulated, at: rect, font: cap.font)
            }
        }
    }

    private func accept(whole: Bool) {
        guard !remainingChunks.isEmpty, let cap = current else { return }
        inflight?.cancel()   // freeze the suggestion so the stream stops mutating remainingChunks
        let toInsert: String
        if whole {
            toInsert = remainingChunks.joined()
            remainingChunks = []
        } else {
            toInsert = remainingChunks.removeFirst()
        }
        Inserter.insert(toInsert, tap: tap)
        if remainingChunks.isEmpty {
            overlay.hide()
        } else {
            // Re-anchor AFTER the paste has landed (Inserter resumes the tap at +0.12s),
            // otherwise the caret rect is still at the pre-paste position and the overlay flickers.
            let remaining = remainingChunks.joined()
            let font = cap.font
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
                guard let self, !self.remainingChunks.isEmpty else { return }
                if let rect = AXCapture.capture()?.caretRect {
                    self.overlay.show(text: remaining, at: rect, font: font)
                }
            }
        }
    }

    private func dismiss() {
        inflight?.cancel()
        remainingChunks = []
        current = nil
        overlay.hide()
    }
}
