# LX script runtime

The UI uses `LxRuntime` through `LxMusicRuntimeService`. The service retains its
staged activation contract: validate a candidate in isolation, publish it
synchronously only after validation succeeds, then dispose the previous runtime.

## Ownership and scheduling

- `LxQuickJsRuntime` schedules work on the caller isolate. It loads the fetch
  asset, tracks deadlines/cancellation and queues foreground work ahead of queued
  preloads. It never creates or evaluates a native JS context.
- `lx_runtime_worker.dart` owns a worker isolate for one active source or one
  candidate. Its protocol sends only Dart data, with command IDs; FFI handles
  never cross isolate boundaries. Script contents are returned during loading,
  not copied again with every resolved URL.
- `LxScriptEngine` owns the JS context, timers and HTTP callbacks. Complete song
  resolutions run serially. Network/timer callbacks can execute while the active
  resolution awaits I/O. Native async/await requires no Promise monkeypatching.
- Successful resolutions retain script globals, token promises, HTTP work and
  expiry/renewal timers. Cancelling or timing out an active resolution disposes
  the complete context before admitting the next resolution. The configured
  script is reconstructed lazily. Cancelling an item still in the queue removes
  only that item.
- Disposal is cooperative. After native execution reaches its interrupt bound,
  the worker cancels transport/timers, frees FFI handles, closes its ports and
  exits. Killing an isolate during an FFI callback is unsafe.

## Bounds and compatibility

QuickJS has a 64 MiB allocation limit, a 5-second synchronous initialization
bound, and a 1500 ms synchronous resolution/drain bound. Remaining operation
deadlines can shorten these bounds. Script initialization has a separate
12-second total deadline; queued resolution time counts against the caller's
existing playback budget. This does not extend the player's total switch budget.
Native budgets follow runtime instances, rather than thread-local storage,
because Dart isolates may migrate OS threads. Contexts never execute concurrently
within an isolate; independent candidate isolates may execute concurrently.

`LxScriptUtils` implements synchronous AES/RSA and secure random bytes beside the
engine. AES-128/192/256 ECB/CBC uses PKCS7. RSA follows LX desktop's 128-byte,
zero-prefixed `RSA_NO_PADDING` contract. Zlib returns promises. Byte conversion
preserves typed-array slice boundaries; inflation output is bounded as it is
produced. Unknown modes and malformed keys fail explicitly, rather than returning
unchanged input. No keys or utility arguments are logged.

The HTTP bridge preserves JSON/text response types. Typed transport failures can
survive the script's error chain; arbitrary business errors and the last HTTP
status are not sufficient evidence for an automatic retry. A script that wraps
an error and drops its transport annotation remains a generic script failure.
Playback recovery retains its existing single-retry/total-budget limits.
Unclassified stream interruptions can replay the same URL; explicit access
denial, 404 and 410 remain grounds for refreshing and rejecting a repeated bad URL.

Windows, Android and Linux use the checked-in QuickJS bridge. Apple retains the
existing JavaScriptCore binding: worker scheduling and utility APIs apply there,
but the QuickJS native interrupt and allocation bounds do not. Apple execution
bounds and device behavior require separate platform validation. An isolate is
not a separate process and does not contain arbitrary native memory corruption.

## Validation

- `lx_runtime_worker_test.dart`: UI event-loop responsiveness, serial resolution,
  priority, queued vs. active cancellation, worker recovery, binary utility
  bridging, transport evidence and independent native contexts.
- `lx_quickjs_native_test.dart`: staged activation, token/timer retention,
  cancellation and late callbacks, source replacement and diagnostics.
- `lx_execution_limits_native_test.dart`: dead loops, catastrophic regexp,
  endless Promise queues, memory limits and candidate rollback.
- `lx_script_utils_test.dart`: independent Node AES/RSA/zlib vectors, malformed
  inputs and decompression bounds. The fixture contains generated public keys
  and test data only.
- Playback and proxy tests cover link refresh/retry decisions and transport
  timeout diagnostics. Node fixtures verify sandbox encoding and API contracts.

Set `CYRENE_LX_NATIVE_TEST=1` with the built library available to the loader.
The quality workflow builds the native bridge and runs these tests with an
external job timeout: a broken native interrupt can block Dart's own timeouts.
