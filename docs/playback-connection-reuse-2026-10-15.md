# Playback HTTP connection reuse (2026-10-15)

## Scope

- Start next-track preparation 500 ms after playback becomes eligible instead
  of 2500 ms. Existing cancellation, target adoption and concurrency rules stay
  in place.
- Reuse one lazily initialized `http.Client` for LX script HTTP requests in the
  isolate. This does not change the audio player's CDN transport or cache
  downloader.
- Use http 1.6.0 `AbortableRequest` with a separate trigger for each HTTP request.
  A resolution cancellation triggers only its own HTTP requests. Every exit
  aborts any remaining send/body work, including `Future.timeout` exits.
- Preserve GET/POST encoding, headers, redirects and the shared headers/body
  deadline. No automatic retry, new routing or concurrency increase is added.
- The client lives for the transport's process/isolate lifetime; the underlying
  HTTP implementation manages idle connections. `LxHttpBridge.close()` is for
  transport shutdown/tests only, not track switching or individual runtime
  disposal, which could interrupt another resolution.

## Verification

- 89 playback/navigation/engine regression tests passed.
- Seven local HTTP tests passed, including one TCP connection reused across
  four sequential GET/POST requests; cancellation and timeout both before
  headers and during body streaming without interrupting an active peer;
  successful subsequent requests; existing encoding and deadline checks.
- Six opt-in real QuickJS tests passed, including cancellation and isolation.
- Full-project static analysis passed. The Android x64 debug APK built and was
  installed with `adb install -r`; the app launched successfully. No uninstall
  or account/source-data clearing was performed.
- Logs: `build/connection-reuse-playback-tests.log`,
  `build/connection-reuse-tests.log`, `build/connection-reuse-native-tests.log`.

## Android emulator observations

The updated Dart code ran after hot restart on the existing Android 15 debug
emulator, with the account and source configuration retained. The mixed QQ /
NetEase runner restored the queue, mode, volume and cache setting after each run.

- Next-track timers actually fired around 504–643 ms in the two runs, rather
  than the previous 2500 ms delay.
- Run 2 passed first play (2921 ms), early next (2155 ms), prepared next
  (582 ms), automatic advance, rapid selection, pause/resume and manual next
  near completion. The early-next transaction reused resolved data
  (`resolve_ms=0`) but still required native source loading.
- Run 1 was not a full pass: one QQ candidate exceeded its resolution budget;
  the app skipped it and played the following NetEase candidate. The runner
  expected the fixed QQ target and reported `target not ready` despite the
  following track being playing with no pending transaction. First/early-next
  native loads were also slower (3711/6330 ms) in this run.
- No matched before/after network experiment was completed. These observations
  confirm behavior, not a quantified connection-reuse speedup or elimination
  of upstream timeouts. Local server tests establish actual TCP reuse; live
  upstream keep-alive behavior can differ.
- The emulator has no audio output. Ready/playing, position and target identity
  checks do not replace a physical-device listening test.
