import AppKit
import SeerModel
import SeerPersonalization
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
    private var resolvedFont = OverlayFont.resolve(FontDescriptorInput(name: nil, size: nil))
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
    /// Fired after `setEnabled`/`setPaused` change state. Reached from the panic chord inside
    /// the key tap (onKeyDown → panic → setEnabled), so like the callbacks below: called
    /// synchronously in the key-tap path; keep it fast and do not call back into the
    /// coordinator. Observers that fan out to UI must gate on the UI actually being visible.
    public var onStateChanged: (() -> Void)?
    /// Fired after an accept inserts text, with the number of words inserted (§8 stats).
    /// Called synchronously in the key-tap accept path; keep it fast and do not call
    /// back into the coordinator.
    public var onAccept: ((_ wordCount: Int) -> Void)?
    /// Fired at most once per suggestion request, when ghost text first becomes displayable.
    /// Measures post-debounce request → first render (capture + gate + prompt + engine TTFD).
    /// Called synchronously on the main actor; keep it fast and do not call back into the coordinator.
    public var onSuggestionLatency: ((_ milliseconds: Double) -> Void)?
    /// Fired once per suggestion LIFECYCLE (not per Tab): partial word-accepts accumulate and
    /// flush as one sample when the suggestion ends — accept-all, dismissal, or focus change.
    /// Per-word samples would flood the corpus with 1-word "sentences" and bias the brevity
    /// axis (and auto-temperature) toward maximum. Called synchronously in the key-tap path;
    /// keep it fast and do not call back into the coordinator (§7.1 accept-only capture).
    public var onLearn: ((AcceptedSample) -> Void)?

    private let knownBad: Set<String> = ["com.tinyspeck.slackmacgap", "com.microsoft.VSCode", "com.github.atom"]
    /// Explicit 0.2, not `SamplingParams()` (whose default temperature is 0.3): this is the
    /// shipped hot-path behavior, now user-tunable via Settings (design spec §7.4 bounds).
    private var samplingParams = SamplingParams(temperature: 0.2, maxTokens: 24)
    /// §7.4 as amended: when ON, temperature derives from the PINNED brevity tone (falls back
    /// to the manual value below the learning thresholds). Default OFF — the Phase-11 slider
    /// stays authoritative until the user opts in.
    private var autoTemperature = false
    /// Rebuilt only at pin time: byte-stable per focus session (§7.5) so the ChatML prefix
    /// stays the KV-cache anchor across keystrokes.
    private var assembler = PromptAssembler()
    private let profileCache: ProfileCache?
    /// The style pinned for the current focus session. Cleared ONLY by focus invalidation —
    /// never by dismiss(): every accept publishes a fresh snapshot, so clearing on dismiss
    /// would re-render the descriptor mid-typing → prefix bytes change → full re-prefill
    /// spike after every accept.
    private struct PinnedStyle {
        let bundleID: String
        let system: String?       // nil ⇒ neutral (cold start)
        let brevity: Double?      // pinned regardless of the auto-temp toggle (B3 reads it)
    }
    private var pinnedStyle: PinnedStyle?
    /// Context of the most recent successful request — the learning signal's provenance.
    /// Overwritten per request, snapshotted into `pendingLearn` at first accept; never read
    /// for rendering (staleness is fine, the pending snapshot is what flushes).
    private var currentContext: CaptureContext?
    private struct PendingLearn {
        let bundleID: String
        let focusedSubrole: String?
        let beforeCaret: String
        var accepted = ""
    }
    private var pendingLearn: PendingLearn?
    private let reanchorDelay: TimeInterval

    public init(engine: any InferenceEngine,
                inserter: TextInserting? = nil,
                capture: @escaping @MainActor () -> CaptureContext? = { CaptureService.capture() },
                reanchorDelay: TimeInterval = 0.13,
                profileCache: ProfileCache? = nil) {
        self.engine = engine
        self.captureProvider = capture
        self.inserter = inserter ?? PasteInserter()
        self.reanchorDelay = reanchorDelay
        self.profileCache = profileCache
    }

    // MARK: - Test seams (internal)
    var testState: AcceptState { state }
    var testCurrent: Suggestion? { current }
    var testInserter: TextInserting { inserter }
    func _test_setShowing(_ s: Suggestion, mode: RenderMode, ctx: CaptureContext? = nil) {
        current = s; currentMode = mode; state = .showing
        currentContext = ctx
        _ = renderer(for: mode)
    }
    func _test_requestSuggestion() async { await requestSuggestion() }
    /// Awaits whatever `inflightTask` currently references (possibly a previous request's
    /// cancelled task, or nil on a fresh coordinator) — a drain point, not "my request".
    func _test_awaitInflight() async { await inflightTask?.value }
    func _test_invalidateFocus() { invalidateFocusSession() }
    var testResolvedFont: ResolvedFont { resolvedFont }
    var testPillExists: Bool { pillRenderer != nil }
    /// Lets a test hold the renderer alive past the coordinator dropping it, to assert on the
    /// panel state `setOverlayFont` left behind.
    var testInlineRenderer: InlineRenderer? { inline }

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
        focusObserver.onInvalidate = { [weak self] in self?.invalidateFocusSession() }
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
    /// Live-apply new generation parameters; captured per-request, so this takes effect
    /// from the next suggestion. In-flight streams keep their old params (harmless).
    public func setSamplingParams(_ params: SamplingParams) { samplingParams = params }
    /// Live-apply the "Auto (match my style)" toggle; like sampling params, takes effect
    /// from the next request.
    public func setAutoTemperature(_ on: Bool) { autoTemperature = on }
    /// Settings display hint: the auto temperature the CURRENT EFFECTIVE global tone would
    /// produce (§7.7 pins applied). The effective value uses the pinned per-session tone
    /// (may lag until the next focus change) — the Suggestions pane documents that
    /// divergence rather than hiding it.
    public var autoTemperatureDisplayHint: Double? {
        profileCache?.snapshot?.effectiveGlobal.map { ToneMapping.autoTemperature(brevity: $0.brevity) }
    }
    /// Live-apply a new ghost-text font. Order matters: dismiss() FIRST, then drop the
    /// lazily-created renderers so the next render rebuilds them with the new font.
    /// dismiss() is load-bearing twice over — don't weaken it to a bare
    /// `inline?.clear(); pillRenderer?.clear()`:
    ///   • it orders both ghost panels out — dropping a renderer while its NSPanel is still
    ///     ordered in deallocates a visible window;
    ///   • it cancels the inflight stream, which captures the renderer strongly — a resumed
    ///     loop would call update() and re-order-in a panel the coordinator no longer holds,
    ///     orphaning a ghost window that can never be cleared.
    /// Takes primitives so callers (SeerAgent) don't need a SeerOverlay dependency.
    public func setOverlayFont(name: String?, size: Double?) {
        dismiss()
        resolvedFont = OverlayFont.resolve(FontDescriptorInput(name: name, size: size))
        inline = nil
        pillRenderer = nil
        currentMode = nil
    }
    /// Replay persisted settings into a freshly built coordinator — the one call SeerAgent's
    /// startup makes, so a new tunable is wired here rather than in untested AppKit glue.
    ///
    /// Call this BEFORE `MenuController.attach(_:)`: `setEnabled`/`setPaused` each fire
    /// `onStateChanged`, and once attached that observer persists state — a mid-replay persist
    /// would write a partial `pausedBundles` set back over the settings being replayed.
    ///
    /// Additive for paused bundles (it never un-pauses), matching the startup contract: the
    /// coordinator is fresh, so the tuning's set is the resulting set.
    public func apply(_ tuning: CoordinatorTuning) {
        setEnabled(tuning.enabled)
        for bundleID in tuning.pausedBundles { setPaused(true, bundleID: bundleID) }
        setSamplingParams(tuning.sampling)
        setAutoTemperature(tuning.autoTemperature)
        setOverlayFont(name: tuning.fontName, size: tuning.fontSize)
    }

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
        let clock = LatencyClock()
        inflightTask?.cancel()
        guard let ctx = captureProvider() else { dismiss(); return }
        let before = String(ctx.textBeforeCaret.suffix(500))
        guard TriggerGate.shouldRequest(textBeforeCaret: before) else { dismiss(); return }
        guard AppPolicy.shouldSuggest(enabled: isEnabled, pausedBundles: pausedBundles, bundleID: ctx.bundleID)
        else { dismiss(); return }
        let mode = modeFor(ctx)
        let r = renderer(for: mode)
        r.setPlacement(mode)
        let style = pin(for: ctx.bundleID)
        currentContext = ctx
        let prompt = assembler.assemble(textBeforeCaret: before)
        var params = samplingParams
        if autoTemperature, let brevity = style.brevity {
            params.temperature = ToneMapping.autoTemperature(brevity: brevity)
        }
        let prefixHash = ctx.prefixHash
        inflightTask = Task { [weak self, engine] in
            var accumulated = ""
            var latencyReported = false
            do {
                for try await piece in engine.stream(prompt: prompt, params: params, cacheKey: nil) {
                    if Task.isCancelled { return }
                    guard let self else { return }
                    accumulated += piece
                    self.current = Suggestion(text: accumulated,
                                              chunks: WordTokenizer.wordChunks(accumulated),
                                              forPrefixHash: prefixHash)
                    if !GhostText.displayable(accumulated).isEmpty {
                        self.state = .showing
                        if !latencyReported {
                            latencyReported = true
                            self.onSuggestionLatency?(clock.elapsedMilliseconds())
                        }
                    }
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
        onAccept?(WordTokenizer.wordCount(of: toInsert))
        if pendingLearn == nil, let ctx = currentContext {
            pendingLearn = PendingLearn(bundleID: ctx.bundleID,
                                        focusedSubrole: ctx.focusedSubrole,
                                        beforeCaret: String(ctx.textBeforeCaret.suffix(AcceptedSample.beforeCaretCap)))
        }
        pendingLearn?.accepted += toInsert
        finishAccept(remaining: remaining, forPrefixHash: sug.forPrefixHash)
    }
    private func finishAccept(remaining: [String], forPrefixHash: UInt64) {
        if remaining.isEmpty {
            flushPendingLearn()
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
        flushPendingLearn()
        inflightTask?.cancel(); debounceTask?.cancel()
        current = nil; state = .idle
        inline?.clear(); pillRenderer?.clear()
    }

    /// One sample per suggestion lifecycle. The secure-subrole guard is §6 defense in depth —
    /// upstream capture is already fail-closed (CaptureService returns nil), and the store's
    /// reducer re-checks after us.
    private func flushPendingLearn() {
        guard let pending = pendingLearn else { return }
        pendingLearn = nil
        guard pending.focusedSubrole != ProfileReducer.secureSubrole else { return }
        guard !pending.accepted.isEmpty else { return }
        onLearn?(AcceptedSample(bundleID: pending.bundleID,
                                focusedSubrole: pending.focusedSubrole,
                                completion: pending.accepted,
                                beforeCaret: pending.beforeCaret,
                                timestamp: Date()))
    }

    // MARK: - Focus-session style pin (§7.5)
    /// Returns the pin for this bundleID, building one if there is none or if the focus
    /// session moved to another app before the AX/app-activation notification arrived
    /// (Cmd-Tab-and-type-immediately race — ctx.bundleID is the authority, not the observer).
    @discardableResult
    private func pin(for bundleID: String) -> PinnedStyle {
        if let existing = pinnedStyle, existing.bundleID == bundleID { return existing }
        let snapshot = profileCache?.snapshot
        let system = snapshot.flatMap { StyleDescriptor.render(snapshot: $0, bundleID: bundleID) }
        let newPin = PinnedStyle(bundleID: bundleID,
                                 system: system,
                                 brevity: snapshot?.tone(for: bundleID)?.brevity)
        pinnedStyle = newPin
        assembler = PromptAssembler(system: system ?? PromptAssembler.defaultSystem)
        return newPin
    }

    private func invalidateFocusSession() {
        pinnedStyle = nil
        dismiss()
    }

    /// Profile-reset escape hatch (§7.7): drop accumulated-but-unflushed learning and end
    /// the focus session so the next request re-pins from the freshly reset snapshot. Order
    /// is load-bearing: pendingLearn must clear BEFORE invalidateFocusSession() — its
    /// dismiss() otherwise flushes the buffer through onLearn, resurrecting a sample into
    /// the store the caller is resetting. Callers invoke this again after the reset publish
    /// lands (a keystroke in between can re-pin from the stale cache).
    public func prepareForProfileReset() {
        pendingLearn = nil
        invalidateFocusSession()
    }
}
