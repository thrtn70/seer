import AppKit
import SeerCapture
import SeerInference
import SeerModel
import SeerOverlay
import SeerSupport

@MainActor
final class OverlayProbe {
    let demo: Bool
    let pill: Bool

    // 1C uses system 13pt (matches the live-verified Phase-0 path).
    // TODO(1D): wire kAXFontNameAttribute/kAXFontSizeAttribute from CaptureService here.
    let resolvedFont = OverlayFont.resolve(FontDescriptorInput(name: nil, size: nil))

    var inline: InlineRenderer?
    var pillRenderer: PillRenderer?
    var captureTimer: Timer?
    var demoTimer: Timer?
    var inflight: Task<Void, Never>?
    var engine: LlamaCppEngine?
    var didShutdown = false

    var lastRect: CGRect?
    var lastPrefixHash: UInt64?
    var currentMode: RenderMode?

    // demo state
    var demoIdx = 0
    var demoAccumulated = ""
    let demoChunks = [" Hello", ",", " world", " from", " Seer", " ghost", " text"]

    let knownBad: Set<String> = ["com.tinyspeck.slackmacgap", "com.microsoft.VSCode", "com.github.atom"]

    init(demo: Bool, pill: Bool) { self.demo = demo; self.pill = pill }

    func start() {
        if demo { startDemo() } else { startLive() }
    }

    // MARK: - Renderer selection

    func renderer(for mode: RenderMode) -> any SuggestionRenderer {
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

    // MARK: - Demo mode (no engine, no AX; renders a canned stream at the mouse)

    func startDemo() {
        print("[overlay] DEMO mode — canned ghost text follows the mouse pointer. Ctrl-C to quit.")
        let timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickDemo() }
        }
        RunLoop.main.add(timer, forMode: .common)
        demoTimer = timer
    }

    private func tickDemo() {
        let mode = demoMode()
        let r = renderer(for: mode)
        r.setPlacement(mode)
        if demoIdx >= demoChunks.count {   // loop: pause, clear, restart
            demoAccumulated = ""
            demoIdx = 0
            r.clear()
            return
        }
        demoAccumulated += demoChunks[demoIdx]
        demoIdx += 1
        r.update(text: demoAccumulated)
    }

    private func demoMode() -> RenderMode {
        let mouse = NSEvent.mouseLocation
        if pill { return .pill(mouse) }
        return .inline(CGRect(x: mouse.x, y: mouse.y, width: 2, height: 18))  // synthetic caret
    }

    // MARK: - Live mode (poll capture → stream → render)

    func startLive() {
        guard Permissions.hasAccessibility(prompt: true) else {
            FileHandle.standardError.write(Data(
                ("[overlay] Accessibility NOT granted. Grant it for this binary in System Settings → "
                + "Privacy & Security → Accessibility, then relaunch.\n").utf8))
            exit(2)
        }
        let loaded: LlamaCppEngine
        do {
            let modelPath = try ModelLocator.resolve(filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf")
            loaded = try LlamaCppEngine(modelPath: modelPath)
        } catch {
            FileHandle.standardError.write(Data("[overlay] FAILED to load model: \(error)\n".utf8))
            exit(2)
        }
        engine = loaded
        Task { await loaded.warmUp() }
        print("[overlay] Ready. Focus TextEdit and type — gray ghost text appears at the caret. Ctrl-C to quit.")

        let timer = Timer.scheduledTimer(withTimeInterval: CaretTracker.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickLive() }
        }
        RunLoop.main.add(timer, forMode: .common)
        captureTimer = timer
    }

    private func tickLive() {
        guard let ctx = CaptureService.capture() else {
            if lastRect != nil || lastPrefixHash != nil {
                inline?.clear(); pillRenderer?.clear()
                inflight?.cancel()
                lastRect = nil; lastPrefixHash = nil
            }
            return
        }
        let mode = FallbackDetector.renderMode(
            caretRect: ctx.caretRect, hasSelectedRange: ctx.caretRect != nil,
            bundleID: ctx.bundleID, knownBadBundles: knownBad,
            mousePoint: NSEvent.mouseLocation, windowTopAnchor: nil)

        // Content changed ⇒ restart the stream for the new context.
        if ctx.prefixHash != lastPrefixHash {
            lastPrefixHash = ctx.prefixHash
            startStream(context: ctx, mode: mode)
        }
        // Placement changed past the dead-zone ⇒ re-anchor.
        if CaretTracker.shouldMove(from: lastRect, to: ctx.caretRect) {
            lastRect = ctx.caretRect
            renderer(for: mode).setPlacement(mode)
        }
    }

    private func startStream(context ctx: CaptureContext, mode: RenderMode) {
        inflight?.cancel()
        guard let engine else { return }
        let r = renderer(for: mode)
        r.setPlacement(mode)
        let before = String(ctx.textBeforeCaret.suffix(500))
        // Only generate with real word context — avoids completing tiny/empty stubs.
        guard before.count >= 3, before.contains(where: { $0.isLetter }) else { r.clear(); return }
        let prompt = PromptAssembler().assemble(textBeforeCaret: before)
        let params = SamplingParams(temperature: 0.2, maxTokens: 24)   // modest; lower entrenches loops
        inflight = Task { [engine] in   // inherits @MainActor; renderer.update runs on main
            var accumulated = ""
            do {
                for try await piece in engine.stream(prompt: prompt, params: params, cacheKey: nil) {
                    if Task.isCancelled { return }
                    accumulated += piece
                    r.update(text: accumulated)
                }
            } catch {
                FileHandle.standardError.write(Data("[overlay] stream error: \(error)\n".utf8))
            }
        }
    }

    // MARK: - Shutdown (exactly once)

    func shutdown() {
        guard !didShutdown else { return }
        didShutdown = true
        inflight?.cancel()
        captureTimer?.invalidate()
        demoTimer?.invalidate()
        inline?.clear()
        pillRenderer?.clear()
        engine?.shutdown()
    }
}
