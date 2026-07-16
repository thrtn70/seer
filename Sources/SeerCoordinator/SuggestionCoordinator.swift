import AppKit
import SeerModel
import SeerSupport
import SeerCapture
import SeerInference
import SeerOverlay
import SeerInput
import SeerInsertion

@MainActor
public final class SuggestionCoordinator {
    private let tap = KeystrokeTap()
    private let engine: any InferenceEngine
    private let captureProvider: @MainActor () -> CaptureContext?
    let inserter: TextInserting
    private let resolvedFont = OverlayFont.resolve(FontDescriptorInput(name: nil, size: nil))
    private let focusObserver = FocusObserver()

    private var inline: InlineRenderer?
    private var pillRenderer: PillRenderer?
    private var currentMode: RenderMode?

    private var state: AcceptState = .idle
    private var current: Suggestion?
    private var debounceTask: Task<Void, Never>?
    private var inflightTask: Task<Void, Never>?
    private var didShutdown = false

    public private(set) var isEnabled = true
    public private(set) var pausedBundles: Set<String> = []
    public var onStateChanged: (() -> Void)?

    private let knownBad: Set<String> = ["com.tinyspeck.slackmacgap", "com.microsoft.VSCode", "com.github.atom"]
    private let assembler = PromptAssembler()
    private let reanchorDelay: TimeInterval

    public init(engine: any InferenceEngine,
                inserter: TextInserting? = nil,
                capture: @escaping @MainActor () -> CaptureContext? = { CaptureService.capture() },
                reanchorDelay: TimeInterval = 0.13) {
        self.engine = engine
        self.captureProvider = capture
        self.inserter = inserter ?? PasteInserter()
        self.reanchorDelay = reanchorDelay
    }

    // MARK: - Test seams (internal)
    var testState: AcceptState { state }
    var testCurrent: Suggestion? { current }
    var testInserter: TextInserting { inserter }
    func _test_setShowing(_ s: Suggestion, mode: RenderMode) {
        current = s; currentMode = mode; state = .showing
        _ = renderer(for: mode)
    }
    func _test_requestSuggestion() async { await requestSuggestion() }

    // MARK: - Lifecycle
    public func start() async {
        await engine.warmUp()
        tap.onKeyDown = { [weak self] code, flags in
            guard let self else { return false }
            return MainActor.assumeIsolated {
                if PanicChord.matches(keyCode: code, flags: flags) { self.panic(); return true }
                return self.handleKey(code: code, hasShift: flags.contains(.maskShift))
            }
        }
        tap.start()
        focusObserver.onInvalidate = { [weak self] in self?.dismiss() }
        focusObserver.start()
    }

    public var tapIsRunning: Bool { tap.isRunning }

    public func shutdown() {
        guard !didShutdown else { return }
        didShutdown = true
        debounceTask?.cancel(); inflightTask?.cancel()
        focusObserver.stop()
        tap.stop()
        inline?.clear(); pillRenderer?.clear()
        engine.shutdownIfPossible()
    }

    // MARK: - Enable / pause control surface
    public func setEnabled(_ on: Bool) {
        isEnabled = on
        if !on { dismiss() }
        onStateChanged?()
    }
    public func setPaused(_ paused: Bool, bundleID: String) {
        if paused { pausedBundles.insert(bundleID); dismiss() } else { pausedBundles.remove(bundleID) }
        onStateChanged?()
    }
    public func isPaused(bundleID: String) -> Bool { pausedBundles.contains(bundleID) }
    /// Panic (⌃⌥⌘., §4.10): toggle Seer's global on/off. Turning off dismisses any visible
    /// suggestion and cancels inflight inference; turning on re-enables suggestions.
    /// Does NOT interrupt an in-flight insertion (the paste's own timer is independent).
    public func panic() { setEnabled(!isEnabled) }

    // MARK: - Synchronous key handling (called on the main run loop, <1 ms)
    func handleKey(code: Int64, hasShift: Bool) -> Bool {
        switch KeyDecision.action(state: state, keyCode: code, hasShift: hasShift) {
        case .passThrough:
            if state == .idle && isEnabled { scheduleSuggest() }
            return false
        case .dismiss:
            dismiss(); return true
        case .typeOverDismiss:
            dismiss()
            if isEnabled { scheduleSuggest() }
            return false
        case .accept(let kind):
            beginAccept(kind); return true
        }
    }

    // MARK: - Renderer selection (ported from probe)
    private func renderer(for mode: RenderMode) -> any SuggestionRenderer {
        switch mode {
        case .inline:
            if case .pill? = currentMode { pillRenderer?.clear() }
            currentMode = mode
            if inline == nil { inline = InlineRenderer(resolvedFont: resolvedFont) }
            return inline!
        case .pill:
            if case .inline? = currentMode { inline?.clear() }
            currentMode = mode
            if pillRenderer == nil { pillRenderer = PillRenderer(resolvedFont: resolvedFont) }
            return pillRenderer!
        }
    }

    private func modeFor(_ ctx: CaptureContext) -> RenderMode {
        FallbackDetector.renderMode(
            caretRect: ctx.caretRect, hasSelectedRange: ctx.caretRect != nil,
            bundleID: ctx.bundleID, knownBadBundles: knownBad,
            mousePoint: NSEvent.mouseLocation, windowTopAnchor: nil)
    }

    // MARK: - Suggest (body completed in 1D-11)
    private func scheduleSuggest() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            await self?.requestSuggestion()
        }
    }
    private func requestSuggestion() async {
        inflightTask?.cancel()
        guard let ctx = captureProvider() else { dismiss(); return }
        let before = String(ctx.textBeforeCaret.suffix(500))
        guard TriggerGate.shouldRequest(textBeforeCaret: before) else { dismiss(); return }
        guard AppPolicy.shouldSuggest(enabled: isEnabled, pausedBundles: pausedBundles, bundleID: ctx.bundleID)
        else { dismiss(); return }
        let mode = modeFor(ctx)
        let r = renderer(for: mode)
        r.setPlacement(mode)
        let prompt = assembler.assemble(textBeforeCaret: before)
        let params = SamplingParams(temperature: 0.2, maxTokens: 24)
        let prefixHash = ctx.prefixHash
        inflightTask = Task { [weak self, engine] in
            var accumulated = ""
            do {
                for try await piece in engine.stream(prompt: prompt, params: params, cacheKey: nil) {
                    if Task.isCancelled { return }
                    guard let self else { return }
                    accumulated += piece
                    self.current = Suggestion(text: accumulated,
                                              chunks: WordTokenizer.wordChunks(accumulated),
                                              forPrefixHash: prefixHash)
                    if !GhostText.displayable(accumulated).isEmpty { self.state = .showing }
                    r.update(text: accumulated)
                }
            } catch {
                FileHandle.standardError.write(Data("[seer] stream error: \(error)\n".utf8))
            }
        }
    }

    // MARK: - Accept (re-anchor completed in 1D-12)
    private func beginAccept(_ kind: AcceptKind) {
        guard state == .showing, let sug = current, !sug.chunks.isEmpty else { return }
        inflightTask?.cancel()
        state = .accepting
        let (toInsert, remaining) = AcceptComputation.apply(chunks: sug.chunks, kind: kind)
        guard !toInsert.isEmpty else { dismiss(); return }
        inserter.insert(toInsert, gate: tap)
        finishAccept(remaining: remaining, forPrefixHash: sug.forPrefixHash)
    }
    private func finishAccept(remaining: [String], forPrefixHash: UInt64) {
        if remaining.isEmpty {
            current = nil; inline?.clear(); pillRenderer?.clear(); state = .idle
            return
        }
        let remainingText = remaining.joined()
        current = Suggestion(text: remainingText, chunks: remaining, forPrefixHash: forPrefixHash)
        // Re-anchor AFTER the paste lands (PasteStrategy resumed the tap at +0.12s), else the
        // caret rect is still pre-paste and the overlay flickers. Stays .accepting until then.
        DispatchQueue.main.asyncAfter(deadline: .now() + reanchorDelay) { [weak self] in
            guard let self, self.state == .accepting, let cur = self.current, !cur.chunks.isEmpty else { return }
            if let ctx = self.captureProvider(), ctx.caretRect != nil {
                let mode = self.modeFor(ctx)
                let r = self.renderer(for: mode)
                r.setPlacement(mode)
                r.update(text: cur.text)
                self.state = .showing
            } else {
                self.dismiss()
            }
        }
    }

    // MARK: - Dismiss
    private func dismiss() {
        inflightTask?.cancel(); debounceTask?.cancel()
        current = nil; state = .idle
        inline?.clear(); pillRenderer?.clear()
    }
}
