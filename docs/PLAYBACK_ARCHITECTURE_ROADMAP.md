# Playback Architecture Roadmap

## Objective

Improve playback reliability, error recovery, testability, and car-screen usability without a high-risk rewrite or a repository-wide state-management migration.

## Current constraints

- `PlaybackService` owns queueing, resolution, caching, engine control, history, session persistence, lyrics, and failure handling.
- UI code reaches singleton services directly from many files.
- Playback state is observable, but user-facing failures have historically been callback-only or log-only.
- Core playback transactions and failure policies have little automated coverage.
- Tablet detection is currently used as a proxy for car-screen behavior.

## Target boundaries

```text
UI
  -> PlayerService facade (stable public API)
    -> PlaybackCoordinator (single state owner)
      -> QueueController
      -> TrackResolver
      -> PlaybackFailurePolicy
      -> PlaybackHistoryRecorder
      -> PlaybackSessionManager
        -> AudioEngine / SourceAdapter / Cache / Storage ports
```

Rules:

1. Only the coordinator commits active playback state.
2. Every asynchronous switch result carries a transaction ID; stale results cannot commit.
3. Domain code does not display Toast, SnackBar, dialogs, or use `BuildContext`.
4. A playback problem is persistent state. A visual notification is a one-shot UI effect keyed by problem ID.
5. History and remote play counts commit only after the engine confirms playback started.
6. Existing `PlayerService` methods remain stable while internals migrate.

## Playback problem model

A problem contains:

- stable problem ID and playback transaction ID;
- affected track and source;
- typed category rather than parsed message text;
- user-facing message;
- supported recovery actions;
- occurrence time.

The playback service exposes the current problem through a notifier and may emit a compatibility callback for the root presenter. New UI should read state and acknowledge effects by problem ID.

## Source health policy

Source health must combine lightweight validation with passive playback evidence.

- A single unavailable or copyrighted track does not mark a source unhealthy.
- Repeated script-integrity or authorization failures may open a circuit breaker.
- Network timeouts degrade health but do not immediately disable a source.
- Users can revalidate, re-import, or switch the active source.
- Health checks must not block local or cached playback.

## Experience profiles

Use explicit profiles instead of treating every large screen as a car display:

- phone;
- tablet;
- car;
- desktop.

The car profile uses at least 56 dp targets, persistent primary controls, predictable Back behavior, reduced motion/blur, and screenshot coverage at 1920x1080 and 1280x720.

## Delivery plan

### Phase 0: safety net and contracts

- [x] Record history only after confirmed playback.
- [x] Introduce typed, persistent playback problems with deduplicated UI effects.
- [x] Add characterization tests for switch success, failure, stale transactions, and resume.
- [x] Establish a CI analyzer baseline that cannot increase.

Exit criteria: playback behavior can be refactored behind tests without changing the facade.

### Phase 1: reliability and recovery

- [x] Introduce explicit playback request intent: manual, automatic, retry, restore.
- [x] Extract and test failure/auto-skip policy.
- [x] Bind delayed auto-skip work to its playback transaction and make it cancellable.
- [x] Propagate typed Lx runtime failures instead of collapsing every failure to a null URL.
- [x] Add passive source-health tracking and circuit breaking.
- [x] Present retry, switch-source, and re-import actions consistently.

Exit criteria: failures are visible, actionable, deduplicated, and never create false history.

### Phase 2: playback-core extraction

Extract in this order to keep dependencies flowing inward:

- [x] History recorder owns confirmed-start history and listening statistics.
- [x] Session manager owns debounce, periodic persistence, load, and clear.
- [x] Failure policy is independent and covered by intent tests.
- [x] Queue controller owns queue, pointer, shuffle, source, and cover mappings.
- [x] Track resolver owns request deduplication, timeouts, and request-scoped failures.
- [x] PlaybackService acts as the compatibility facade/coordinator over these modules.

Exit criteria: `PlaybackService` is a compatibility facade/coordinator rather than a multi-domain implementation.

### Phase 3: car experience

- [x] Add explicit car profile selection and persistence.
- [x] Standardize Back: close transient panel first, then player route.
- [x] Add reduced-effects rendering and 56 dp car touch targets.
- [ ] Add golden and emulator workflow tests for car resolutions (deferred; manual emulator validation is sufficient for now).

### Phase 4: observability and quality

- [x] Replace direct `print` calls in critical paths with structured, redacted logging.
- [x] Track transaction ID, stage latency, source, cache result, and failure kind.
- [x] Split immersive backdrop and playback controls into isolated repaint scopes.
- [x] Reduce the analyzer baseline incrementally (`avoid_print`: 1129 -> 1115).

## Non-goals

- No immediate Provider/Riverpod/BLoC migration.
- No big-bang rewrite of playback or player UI.
- No source disablement based on a single failed track.
- No user-visible raw exceptions, URLs, tokens, cookies, or script payloads.
