import Foundation
import SeerInference
import SeerModel
import SeerSupport

// Phase 1A: in-process Metal inference, no subprocess.
//
//   (no args)   Task 6 smoke: stream one completion, assert >=1 token, exit 0.
//   --bench     Task 7 definition-of-done: prove prefix-reuse correctness and that warm
//               (incremental-decode) time-to-first-token is sub-100 ms and beats cold
//               (full-prefill) TTFT through one shared engine instance.

let modelFilename = "qwen2.5-1.5b-instruct-q4_k_m.gguf"

if CommandLine.arguments.contains("--help") {
    print("""
    SeerBench — in-process llama.cpp streaming.
    Usage:
      swift run -c release SeerBench           # smoke: stream one completion
      swift run -c release SeerBench --bench   # TTFT reuse benchmark (Phase 1A DoD)
    """)
    exit(0)
}

// MARK: - Shared helpers

func loadEngine() -> LlamaCppEngine {
    do {
        let modelPath = try ModelLocator.resolve(filename: modelFilename)
        FileHandle.standardError.write(Data("Loading model (\(modelPath))…\n".utf8))
        return try LlamaCppEngine(modelPath: modelPath)
    } catch {
        FileHandle.standardError.write(Data("FAILED to load model: \(error)\n".utf8))
        exit(2)
    }
}

func die(_ message: String, engine: LlamaCppEngine, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    engine.shutdown()
    exit(code)
}

// MARK: - Smoke (default, no args)

func runSmoke() async -> Never {
    let prompt = PromptPayload(stablePrefix: "", context: "Thanks so much for your patience while we")
    let params = SamplingParams(temperature: 0.3, topK: 40, topP: 0.9, maxTokens: 32)

    let engine = loadEngine()
    await engine.warmUp()

    // --- Direct engine stream ---
    print("Prompt: \(prompt.fullText)")
    print("Completion: ", terminator: "")

    var tokenCount = 0
    do {
        for try await piece in engine.stream(prompt: prompt, params: params, cacheKey: nil) {
            print(piece, terminator: "")
            tokenCount += 1
        }
    } catch {
        print("")
        die("STREAM ERROR: \(error)", engine: engine, code: 3)
    }

    print("")
    print("Tokens produced: \(tokenCount)")

    if tokenCount == 0 {
        engine.shutdown()
        FileHandle.standardError.write(Data("SMOKE FAILED: zero tokens produced.\n".utf8))
        exit(1)
    }
    print("SMOKE OK")

    // --- EngineSelector seam (Task 8: prove coordinator-facing seam with concrete engine) ---
    let selector = EngineSelector(engines: [engine])
    let selectorPrompt = PromptPayload(stablePrefix: "", context: "The best way to learn Swift is")
    let selectorParams = SamplingParams(temperature: 0.3, topK: 40, topP: 0.9, maxTokens: 16)

    var selectorTokens: [String] = []
    do {
        for try await piece in selector.stream(prompt: selectorPrompt, params: selectorParams, cacheKey: nil) {
            selectorTokens.append(piece)
        }
    } catch {
        engine.shutdown()
        FileHandle.standardError.write(Data("SELECTOR STREAM ERROR: \(error)\n".utf8))
        exit(3)
    }

    engine.shutdown()

    let selectorText = selectorTokens.joined()
    if selectorTokens.isEmpty {
        FileHandle.standardError.write(Data("SELECTOR FAILED: zero tokens produced.\n".utf8))
        exit(1)
    }
    print("SELECTOR OK (\(selectorTokens.count) tokens): \(selectorText)")
    exit(0)
}

// MARK: - Bench (--bench)

/// Stream a prompt; return (full completion text, TTFT in ms). TTFT = wall time from
/// calling `stream` to receiving the FIRST token.
func streamMeasured(
    engine: LlamaCppEngine, prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?
) async throws -> (completion: String, ttftMs: Double) {
    let clock = LatencyClock()
    var first: Double? = nil
    var out = ""
    for try await piece in engine.stream(prompt: prompt, params: params, cacheKey: cacheKey) {
        if first == nil {
            first = clock.elapsedMilliseconds()
        }
        out += piece
    }
    guard let ttft = first else {
        throw EngineError.backend("stream produced no tokens")
    }
    return (out, ttft)
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let idx = Int(((p / 100.0) * Double(sorted.count - 1)).rounded())
    return sorted[max(0, min(idx, sorted.count - 1))]
}

func runBench() async -> Never {
    let engine = loadEngine()

    // Warm up Metal kernels (JIT) and pay the model-load tax before any timing.
    await engine.warmUp()

    // A short, low-temperature config so completions are coherent and quick.
    let params = SamplingParams(temperature: 0.2, topK: 40, topP: 0.9, maxTokens: 16)

    // One discarded stream so the first MEASURED sample isn't polluted by first-decode JIT.
    do {
        _ = try await streamMeasured(
            engine: engine,
            prompt: PromptPayload(stablePrefix: "", context: "The quick brown fox"),
            params: params, cacheKey: nil)
    } catch {
        die("WARMUP STREAM ERROR: \(error)", engine: engine, code: 3)
    }

    print("===== Part 1: reuse correctness =====")

    let baseContext = "Thanks so much for your patience while we"
    let promptP = PromptPayload(stablePrefix: "", context: baseContext)
    // Append one character (the append/reuse fast path).
    let promptAppend = PromptPayload(stablePrefix: "", context: baseContext + " ")
    // Behind-the-caret edit: change an earlier word (the seq_rm divergence path).
    let promptEdit = PromptPayload(
        stablePrefix: "", context: "Thank you so much for your patience while we")

    var completions: [(String, String)] = []
    do {
        let r1 = try await streamMeasured(engine: engine, prompt: promptP, params: params, cacheKey: nil)
        guard !r1.completion.isEmpty else { die("P produced no tokens", engine: engine, code: 4) }
        completions.append((promptP.fullText, r1.completion))

        let r2 = try await streamMeasured(engine: engine, prompt: promptAppend, params: params, cacheKey: nil)
        guard !r2.completion.isEmpty else { die("P+append produced no tokens", engine: engine, code: 4) }
        completions.append((promptAppend.fullText, r2.completion))

        let r3 = try await streamMeasured(engine: engine, prompt: promptEdit, params: params, cacheKey: nil)
        guard !r3.completion.isEmpty else { die("P-edit produced no tokens", engine: engine, code: 4) }
        completions.append((promptEdit.fullText, r3.completion))
    } catch {
        die("CORRECTNESS STREAM ERROR: \(error)", engine: engine, code: 3)
    }

    for (prompt, completion) in completions {
        print("  prompt:     \"\(prompt)\"")
        print("  completion: \"\(completion)\"")
        print("")
    }

    // MARK: warm == cold equivalence assertion
    // Property: with a fixed sampler seed, the warm (KV-reuse) path must produce the
    // same first N tokens as a cold (full-prefill) path for the same prompt P.
    //
    // Cold P:  prime the cache with a DIVERGENT prompt D first, then stream P — the
    //          shared prefix with D is near-zero so P is nearly fully re-prefilled.
    // Warm P:  prime the cache with P-minus-last-char, then stream P — the large shared
    //          prefix exercises the incremental append / reuse decode path.
    //
    // Both use identical SamplingParams with the default fixed seed, so the sampled
    // tokens must be byte-identical if KV reuse is correct.
    print("===== Part 1b: warm == cold equivalence =====")
    let eqPrompt = PromptPayload(stablePrefix: "", context: baseContext)
    let divergentPrompt = PromptPayload(
        stablePrefix: "", context: "Zephyr winds carry the ancient tune while")
    // P minus its last character so the cache holds a large prefix of P.
    let eqPrefixPrompt = PromptPayload(
        stablePrefix: "", context: String(baseContext.dropLast()))
    let maxEquivTokens = 5
    let eqParams = SamplingParams(temperature: 0.2, topK: 40, topP: 0.9, maxTokens: maxEquivTokens)

    var coldOut: [String] = []
    var warmOut: [String] = []

    do {
        // Cold path: diverge cache, then stream P.
        _ = try await streamMeasured(engine: engine, prompt: divergentPrompt, params: eqParams, cacheKey: nil)
        var collected = 0
        for try await piece in engine.stream(prompt: eqPrompt, params: eqParams, cacheKey: nil) {
            coldOut.append(piece)
            collected += 1
            if collected >= maxEquivTokens { break }
        }

        // Warm path: prime with P prefix, then stream P.
        _ = try await streamMeasured(engine: engine, prompt: eqPrefixPrompt, params: eqParams, cacheKey: nil)
        collected = 0
        for try await piece in engine.stream(prompt: eqPrompt, params: eqParams, cacheKey: nil) {
            warmOut.append(piece)
            collected += 1
            if collected >= maxEquivTokens { break }
        }
    } catch {
        die("EQUIVALENCE STREAM ERROR: \(error)", engine: engine, code: 3)
    }

    let coldStr = coldOut.joined()
    let warmStr = warmOut.joined()
    print("  cold output: \"\(coldStr)\"")
    print("  warm output: \"\(warmStr)\"")
    let equivPass = coldStr == warmStr
    print("  assert warm output == cold output: \(equivPass ? "PASS" : "FAIL")")
    print("")

    if !equivPass {
        engine.shutdown()
        FileHandle.standardError.write(Data(
            "BENCH FAILED: warm/cold mismatch — KV reuse produced wrong tokens.\n  cold: \"\(coldStr)\"\n  warm: \"\(warmStr)\"\n".utf8))
        exit(1)
    }

    // MARK: Part 1c — Part B stable-prefix snapshot reuse (cross-field, cacheKey != nil)
    //
    // Goal: genuinely FIRE the Part B snapshot capture/restore path and PROVE it is
    // correct — restoring a captured prefix KV must yield byte-identical output to a
    // full re-decode of the same prompt.
    //
    // Trigger requirements baked into KVCacheStore:
    //   - capture: stablePrefix S must tokenize as a strict, non-empty token-prefix of
    //     the full prompt (S + context). So the capturing prompt needs a non-empty
    //     context, and S must end on a clean token boundary (we end it with "\n").
    //   - restore: the next prompt's tokens must BEGIN with the captured prefix tokens,
    //     and the snapshot must still be live in the N=3 LRU under the same cacheKey.
    print("===== Part 1c: Part B stable-prefix snapshot reuse =====")

    // A non-empty stable prefix: a short instruction + one example, ending on a newline
    // so the seam token is stable across different trailing contexts.
    let snapPrefix = """
    You are a concise writing assistant. Continue the user's sentence naturally.
    Example: "I was thinking about" -> "the weekend plans we made earlier."
    Now continue:
    """ + "\n"
    let snapKey = PrefixCacheKey(bundleID: "app.seer.bench", stablePrefix: snapPrefix)

    // Two divergent trailing contexts that share the stable prefix S.
    let ctxA = "Thanks so much for your patience while we"
    let ctxB = "I really appreciate you taking the time to"
    // A fully divergent prompt to evict S from the LIVE KV (not the snapshot LRU).
    let divergeForSnap = PromptPayload(
        stablePrefix: "", context: "Zephyr winds carry the ancient tune while travelers wander")

    let snapMaxTokens = 8
    let snapParams = SamplingParams(temperature: 0.2, topK: 40, topP: 0.9, maxTokens: snapMaxTokens)

    func collect(_ prompt: PromptPayload, _ key: PrefixCacheKey?) async throws -> [String] {
        var out: [String] = []
        var collected = 0
        for try await piece in engine.stream(prompt: prompt, params: snapParams, cacheKey: key) {
            out.append(piece)
            collected += 1
            if collected >= snapMaxTokens { break }
        }
        return out
    }

    var baselineOut: [String] = []
    var snapshotOut: [String] = []
    do {
        // --- Baseline (no snapshot): force a FULL decode of S + ctxB. ---
        // Prime the live KV with a fully-divergent prompt so it does NOT hold S, then
        // stream S+ctxB with cacheKey: nil → no restore, full prefill of the prefix.
        _ = try await collect(divergeForSnap, nil)
        baselineOut = try await collect(
            PromptPayload(stablePrefix: snapPrefix, context: ctxB), nil)

        // --- Snapshot path: capture S, evict S from live KV, then restore. ---
        // 1. Stream S+ctxA with the key → materialises S and CAPTURES its snapshot.
        _ = try await collect(PromptPayload(stablePrefix: snapPrefix, context: ctxA), snapKey)
        // 2. Stream a fully-divergent prompt (cacheKey: nil) → S is no longer live in KV.
        _ = try await collect(divergeForSnap, nil)
        // 3. Stream S+ctxB with the key → should RESTORE S's snapshot, decode only ctxB.
        snapshotOut = try await collect(
            PromptPayload(stablePrefix: snapPrefix, context: ctxB), snapKey)
    } catch {
        die("SNAPSHOT STREAM ERROR: \(error)", engine: engine, code: 3)
    }

    let baselineStr = baselineOut.joined()
    let snapshotStr = snapshotOut.joined()
    let snapStats = engine.snapshotStats()
    print("  baseline (full decode of S+ctxB, cacheKey nil): \"\(baselineStr)\"")
    print("  snapshot (restore S, decode ctxB, cacheKey set): \"\(snapshotStr)\"")
    let snapEquivPass = snapshotStr == baselineStr
    print("  assert snapshot output == baseline output: \(snapEquivPass ? "PASS" : "FAIL")")
    print("  snapshot probe: enabled=\(snapStats.enabled) captures=\(snapStats.captures) restores=\(snapStats.restores)")

    if !snapEquivPass {
        engine.shutdown()
        FileHandle.standardError.write(Data(
            "BENCH FAILED: Part B snapshot output != baseline — restore produced wrong tokens.\n  baseline: \"\(baselineStr)\"\n  snapshot: \"\(snapshotStr)\"\n".utf8))
        exit(1)
    }

    if snapStats.enabled {
        // The probe trusts restore on this hardware → the snapshot path MUST have fired.
        if snapStats.restores < 1 {
            engine.shutdown()
            FileHandle.standardError.write(Data(
                "BENCH FAILED: snapshot enabled but restores=0 — Part B did not fire.\n".utf8))
            exit(1)
        }
        print("  Part B snapshot FIRED (restores=\(snapStats.restores), captures=\(snapStats.captures)); restore output == full-decode output.")
    } else {
        print("  Part B snapshot disabled by probe (GPU restore unreliable); equivalence held via re-decode fallback.")
    }
    print("")

    // MARK: Part 1d — cancel-then-prefix-extend equivalence (the live overlay's exact stressor)
    //
    // SeerOverlayProbe cancels the in-flight stream on EVERY keystroke and immediately
    // starts a new stream whose prompt is a strict PREFIX-EXTENSION of the previous one.
    // The rest of the 1A suite only ever runs streams to completion, so this "cancel
    // mid-decode, then continue from a prefix-extended prompt" path — the one the overlay
    // hammers — was statically analyzed as correct (appendDecoded mutates the KV length
    // atomically with the decode, and the next prepare()'s seq_rm clears the stale
    // generated tail down to the shared prefix) but never DYNAMICALLY exercised. Lock it in.
    //
    // Property: streaming Q after a MID-STREAM-CANCELLED P (whose KV tail is partial,
    // soon-to-be-dropped generation) must produce byte-identical output to streaming Q
    // cold (full prefill after a divergent reset). A wrong post-cancel seq_rm / prefix
    // reuse would make the warm-after-cancel output diverge from the cold one.
    print("===== Part 1d: cancel-then-prefix-extend equivalence =====")

    let cancelP = PromptPayload(stablePrefix: "", context: "Thanks so much for")
    // Q strictly extends P — the overlay's per-keystroke prefix growth.
    let cancelQ = PromptPayload(
        stablePrefix: "", context: "Thanks so much for your patience while we")
    // A fully-divergent prompt to reset the live KV to a near-zero shared prefix with Q.
    let cancelDiverge = PromptPayload(
        stablePrefix: "", context: "Zephyr winds carry the ancient tune while")
    // Q comparison params (fixed seed). P gets more headroom so a 3-piece break is
    // genuinely mid-stream, not a naturally-finished short completion.
    let cancelParams = SamplingParams(temperature: 0.2, topK: 40, topP: 0.9, maxTokens: 8)
    let cancelPParams = SamplingParams(temperature: 0.2, topK: 40, topP: 0.9, maxTokens: 16)

    var warmAfterCancelStr = ""
    var coldQStr = ""
    do {
        // --- Warm-after-cancel: stream P, break mid-decode to fire onTermination, then Q. ---
        var pPieces = 0
        for try await _ in engine.stream(prompt: cancelP, params: cancelPParams, cacheKey: nil) {
            pPieces += 1
            if pPieces >= 3 { break }  // break → AsyncThrowingStream onTermination → cancel mid-decode
        }
        guard pPieces >= 2 else {
            die("Part 1d: P yielded \(pPieces) piece(s) — too few to cancel mid-stream",
                engine: engine, code: 4)
        }
        // Live KV now holds P + a partial generated tail. Streaming Q must drop that stale
        // tail (seq_rm) and decode only Q's fresh extension — the cancel-then-extend path.
        warmAfterCancelStr = try await streamMeasured(
            engine: engine, prompt: cancelQ, params: cancelParams, cacheKey: nil).completion

        // --- Cold Q: diverge the live KV to a near-zero shared prefix, then full-prefill Q. ---
        _ = try await streamMeasured(
            engine: engine, prompt: cancelDiverge, params: cancelParams, cacheKey: nil)
        coldQStr = try await streamMeasured(
            engine: engine, prompt: cancelQ, params: cancelParams, cacheKey: nil).completion
    } catch {
        die("CANCELLATION STREAM ERROR: \(error)", engine: engine, code: 3)
    }

    print("  warm-after-cancel Q output: \"\(warmAfterCancelStr)\"")
    print("  cold Q output:              \"\(coldQStr)\"")
    let cancelEquivPass = !coldQStr.isEmpty && warmAfterCancelStr == coldQStr
    print("  assert warm-after-cancel output == cold output: \(cancelEquivPass ? "PASS" : "FAIL")")
    print("")

    if !cancelEquivPass {
        engine.shutdown()
        FileHandle.standardError.write(Data(
            "BENCH FAILED: cancel-then-prefix-extend mismatch — post-cancel KV reuse produced wrong tokens.\n  cold: \"\(coldQStr)\"\n  warm-after-cancel: \"\(warmAfterCancelStr)\"\n".utf8))
        exit(1)
    }

    // MARK: Part 1e — ChatML parse_special warm == cold equivalence
    //
    // Proves that ChatML tokenization (parseSpecial: true) is consistent across KV reuse:
    // streaming a ChatML prompt warm (after a near-prefix primes the KV) must produce the
    // same tokens as streaming it cold (after a divergent eviction forces a full re-prefill).
    print("===== Part 1e: ChatML parse_special warm == cold equivalence =====")
    let asm = PromptAssembler()
    let chatmlFull = asm.assemble(textBeforeCaret: "Thanks so much for your patience while we")
    let chatmlWarmPrefix = asm.assemble(textBeforeCaret: "Thanks so much for your patience while w")
    let chatmlDiverge = asm.assemble(textBeforeCaret: "Zephyr winds carry the ancient tune while")
    let eqP = SamplingParams(temperature: 0.2, topK: 40, topP: 0.9, maxTokens: 6)
    var chatmlWarm = "", chatmlCold = ""
    do {
        // Prime the KV with a near-prefix of the full ChatML prompt → large shared prefix.
        _ = try await streamMeasured(engine: engine, prompt: chatmlWarmPrefix, params: eqP, cacheKey: nil)
        // Stream the full ChatML prompt warm (incremental decode / reuse path).
        chatmlWarm = try await streamMeasured(
            engine: engine, prompt: chatmlFull, params: eqP, cacheKey: nil).completion
        // Diverge the KV so the next stream of chatmlFull is a full re-prefill (cold).
        _ = try await streamMeasured(engine: engine, prompt: chatmlDiverge, params: eqP, cacheKey: nil)
        // Stream the full ChatML prompt cold (full-prefill path).
        chatmlCold = try await streamMeasured(
            engine: engine, prompt: chatmlFull, params: eqP, cacheKey: nil).completion
    } catch { die("Part 1e stream error: \(error)", engine: engine, code: 3) }
    print("  warm ChatML: \"\(chatmlWarm)\"")
    print("  cold ChatML: \"\(chatmlCold)\"")
    let chatmlEqPass = !chatmlCold.isEmpty && chatmlWarm == chatmlCold
    print("  assert ChatML warm == cold: \(chatmlEqPass ? "PASS" : "FAIL")")
    if !chatmlEqPass {
        engine.shutdown()
        FileHandle.standardError.write(Data("BENCH FAILED: ChatML parse_special warm/cold mismatch.\n".utf8))
        exit(1)
    }
    print("")

    // MARK: warm latency — 20 keystrokes, each appends one char (high shared prefix).
    print("===== Part 2: warm latency (incremental decode / reuse) =====")
    let warmBase = "Hello, I wanted to follow up on our conversation from earlier this week regarding"
    let warmSuffix = " the proposal and next steps we discussed in detail together"
    var warmTTFTs: [Double] = []
    do {
        for i in 0..<20 {
            // Each keystroke extends the prior prompt by one character → commonLength is large.
            let typed = String((warmBase + warmSuffix).prefix(warmBase.count + i + 1))
            let prompt = PromptPayload(stablePrefix: "", context: typed)
            let r = try await streamMeasured(engine: engine, prompt: prompt, params: params, cacheKey: nil)
            warmTTFTs.append(r.ttftMs)
        }
    } catch {
        die("WARM STREAM ERROR: \(error)", engine: engine, code: 3)
    }

    // MARK: cold latency — 20 prompts with mutually disjoint prefixes (forces full prefill).
    print("===== Part 3: cold latency (full prefill baseline) =====")
    // Unique filler phrases of comparable length so commonLength ~= 0 each time.
    let fillers = [
        "Apricot mornings drift over the harbor as",
        "Beneath the violet ridge a traveler once",
        "Crimson lanterns sway while the old market",
        "Distant thunder rolls past the quiet valley",
        "Every autumn the orchard keeper carefully prunes",
        "Frost gathers along the iron railing where",
        "Golden wheat ripples under a restless sky",
        "Hidden coves echo with the gulls that",
        "Ivory towers cast long shadows when the",
        "Juniper smoke curls above the campfire as",
        "Kestrels wheel over the chalk cliffs while",
        "Lavender fields hum with bees that drift",
        "Marble fountains glisten in the plaza where",
        "Nightingales answer the cathedral bells that toll",
        "Obsidian waves crash against the lighthouse as",
        "Pewter clouds gather over the moorland where",
        "Quartz veins glitter in the cavern walls",
        "Russet leaves spiral down the cobbled lane",
        "Sapphire dusk settles on the sleeping town",
        "Tidal pools mirror the bruised evening sky",
    ]
    let coldTail = " the weary travelers paused to rest and consider what would come next on their long road"
    var coldTTFTs: [Double] = []
    do {
        for filler in fillers {
            let prompt = PromptPayload(stablePrefix: "", context: filler + coldTail)
            let r = try await streamMeasured(engine: engine, prompt: prompt, params: params, cacheKey: nil)
            coldTTFTs.append(r.ttftMs)
        }
    } catch {
        die("COLD STREAM ERROR: \(error)", engine: engine, code: 3)
    }

    // MARK: summary
    let warmP50 = percentile(warmTTFTs, 50)
    let warmP95 = percentile(warmTTFTs, 95)
    let coldP50 = percentile(coldTTFTs, 50)
    let coldP95 = percentile(coldTTFTs, 95)
    let speedup = warmP50 > 0 ? coldP50 / warmP50 : 0

    func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    print("===== Summary =====")
    print("  warm TTFT  p50: \(fmt(warmP50)) ms   p95: \(fmt(warmP95)) ms   (n=\(warmTTFTs.count))")
    print("  cold TTFT  p50: \(fmt(coldP50)) ms   p95: \(fmt(coldP95)) ms   (n=\(coldTTFTs.count))")
    print("  reuse speedup (cold p50 / warm p50): \(fmt(speedup))x")

    let warmUnder100 = warmP50 < 100.0
    let warmBeatsCold = warmP50 < coldP50
    print("  assert warm p50 < 100 ms: \(warmUnder100 ? "PASS" : "FAIL")")
    print("  assert warm p50 < cold p50: \(warmBeatsCold ? "PASS" : "FAIL")")

    engine.shutdown()

    guard warmUnder100 && warmBeatsCold else {
        FileHandle.standardError.write(Data(
            "BENCH FAILED: warm p50=\(fmt(warmP50))ms (target <100), cold p50=\(fmt(coldP50))ms.\n".utf8))
        exit(1)
    }
    print("BENCH OK")
    exit(0)
}

// MARK: - Prompt Quality (--prompt-quality)

/// Prints raw-vs-ChatML completions for several human-eyeball quality contexts.
/// Use: swift run -c release SeerBench --prompt-quality
func runPromptQuality() async -> Never {
    let qualityContexts = [
        "Thanks so much for your",
        "I am writing to follow up on",
        "The meeting is scheduled for",
        "Let me know if you have any",
    ]
    let params = SamplingParams(temperature: 0.2, maxTokens: 24)
    let engine = loadEngine()
    await engine.warmUp()

    let asm = PromptAssembler()

    for ctx in qualityContexts {
        let rawPrompt = PromptPayload(stablePrefix: "", context: ctx)
        let chatmlPrompt = asm.assemble(textBeforeCaret: ctx)

        var rawCompletion = ""
        var chatmlCompletion = ""

        do {
            rawCompletion = try await streamMeasured(
                engine: engine, prompt: rawPrompt, params: params, cacheKey: nil).completion
        } catch {
            die("--prompt-quality RAW stream error for ctx \"\(ctx)\": \(error)",
                engine: engine, code: 3)
        }

        do {
            chatmlCompletion = try await streamMeasured(
                engine: engine, prompt: chatmlPrompt, params: params, cacheKey: nil).completion
        } catch {
            die("--prompt-quality CHATML stream error for ctx \"\(ctx)\": \(error)",
                engine: engine, code: 3)
        }

        print("ctx: \"\(ctx)\"")
        print("  RAW   : \"\(rawCompletion)\"")
        print("  CHATML: \"\(chatmlCompletion)\"")
        print("")
    }

    engine.shutdown()
    exit(0)
}

// MARK: - Entry

if CommandLine.arguments.contains("--bench") {
    await runBench()
} else if CommandLine.arguments.contains("--prompt-quality") {
    await runPromptQuality()
} else {
    await runSmoke()
}
