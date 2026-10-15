# Playback output and native preparation

This document records earlier output/EQ experiments. The current Android
architecture is described in `android-native-playback.md`: official just_audio
0.10.6 with the minimal Media3 1.9.2 playlist-preload adapter, one player and
app-side URL/lyric prefetch. The old custom preload manager and stream caching
described in historical experiments are retired.

## Behavior

- Normal Android source replacement and prepared-slot activation retain the
  user's volume. There is no per-track mute, deferred volume restore, or EQ fade.
- A load requested with `autoPlay: false` pauses an already playing player before
  loading/seeking, so a prepared target cannot briefly become audible.
- EQ updates follow actual audio-session and configuration changes. They are
  coalesced outside the startup deadline. Disabled EQ releases its existing
  attachment without polling for an audio session. Failed effects do not prevent
  normal playback. Attachment, application, and release are serialized separately
  from playback controls; stale-session cleanup cannot release a newer attachment.
- Native EQ application updates changed band levels instead of disabling,
  clearing, and enabling the effect on every update. Saved settings are retained.

## Native preparation and recovery

- Keep an existing, unexpired next slot when its source, queue revision, and
  parent playback generation match. Business and native descriptors retain the
  same generation when a preparation plan is reused.
- `prepared_window_ready` means the playlist mutation completed; it does not
  assert that the next item is buffered. Logs include `preparation_stage` and
  `next_reused` to make that distinction explicit.
- A background mutation deadline leaves the current player intact and tracks the
  outstanding native future. No more preparation or prepared activation is
  admitted while that mutation is outstanding. Pause/resume remain available.
- Before source replacement, stop, or prepared-window invalidation, drain the
  outstanding mutation with a bounded wait. A persistently hung instance is
  detached and cleaned up; a source replacement initializes a fresh instance
  within its existing deadline. Late callbacks cannot mutate the new instance.
- Recovery does not publish an intermediate fatal playback error or start a
  second URL resolution. Completed mutation rejection is logged, and a full
  source replacement establishes a fresh playlist.
- EngineHost discards stale queued preparation, binding, and invalidation after
  a newer source-load revision. Existing transaction guards, error classification,
  and terminal pending cleanup remain responsible for playback recovery.

## Verification

- Full suite: 360 tests passed with real QuickJS enabled; static analysis clean.
- Regression cases cover ordinary switching without volume writes, paused-load
  output suppression, background timeout with working pause/resume, late success
  reuse, late rejection containment, hung-mutation recovery, valid-slot retention,
  and stale queued binding/invalidation.
- A project-signed debug APK was installed over the emulator's existing package
  without clearing login/source settings. Latest Dart changes were hot reloaded.
- Emulator records are in ignored `build/playback-output*-verification.jsonl`
  and `build/playback-output*-events.jsonl`. These report native state and progress;
  they do not verify audible output or device-specific click/pop behavior.
- Two QQ/Netease rounds exercised sequential next, rapid selection, pause/resume,
  and live EQ toggles with stable volume and no residual pending track. One short
  QQ resume observation in the first round did not show increasing position;
  the second round used multiple samples and three resumes per platform, all
  showing continuing progress. These limited trials do not establish universal
  reliability or a causal explanation for the first short observation.
- Real upstream/CDN loading can still be slow. This change reduces unnecessary
  native work and contains failures; it does not guarantee instant playback or
  eliminate third-party network timeouts.
