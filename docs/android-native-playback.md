# Android playback: official Media3 playlist preloading

The app uses a local snapshot of official just_audio **0.10.6** with a minimal
Android adapter exposing Media3's built-in playlist-preload configuration. The
snapshot pins Media3 **1.9.2**; the resolved debug dependency graph also reports
1.9.2. It preserves upstream stop/prepare, error reporting and decoder lifecycle.
The hosted pub cache is untouched. All adapter differences are documented in
`packages/just_audio/CYRENE_ADAPTER.md`.

## Playback ownership

Android reuses one player with a rolling current/next playlist. Background work
resolves the next URL and lyrics through the existing bounded, source/quality-aware
caches, then inserts the next source using upstream playlist APIs. Media3 is
configured to buffer three seconds of the next item. DefaultLoadControl gives
current-item loading priority. A matching manual next uses seek by index; native
automatic advancement commits the source identity before publishing playing
state. An unprepared target follows normal loading; it does not wait for the
background candidate. Existing transaction/deadline/recovery protections remain.

`CYRENE_ANDROID_PLAYLIST_PRELOAD` defaults to true. Build with
`--dart-define=CYRENE_ANDROID_PLAYLIST_PRELOAD=false` to retain single-source
loading and URL/lyric prefetch while disabling native next-item preparation.
This flag does not downgrade Media3. iOS retains its upstream playlist behavior
and receives no Android preload configuration; desktop continues using MediaKit.

The previous isolated DefaultPreloadManager, incremental SimpleCache bridge,
custom source UUID/error details and append experiment required a local plugin
fork. They are retired. Next-link readiness is not native sample-buffer readiness;
do not compare previous prepared-slot timings as if the same path still exists.
The iOS playlist path continues to use official playlist APIs.

## Failure ownership and complete-file cache

A native next item can fail after selection but before reaching ready. Such an
error carries the selected prepared generation, without publishing a successful
source commit. The service validates queue revision, entry, track identity and
parent generation before staging that failed target. Recovery explicitly retries
that target; a terminal error remembers it and clears pending state. Late errors
and ready events cannot replace a newer selection. Error indices alone do not
identify a background failing source and are not a reason to suppress errors.

Android complete-file caching uses the same bounded CacheService download path
as desktop. The retired native stream-cache bridge no longer writes audio bytes,
so metadata-only refresh cannot create missing cache files. The shared cache path
retains the cache preference, same-track request sharing and single-download
limit; Media3 playlist buffers remain separate from persistent file caching.

Review-fix verification (2026-10-15): 373 tests passed, six opt-in native
QuickJS tests skipped; analyzer clean; debug APK rebuilt and installed with
`adb install -r`. Regression tests cover next-item failure before ready, retrying
the correct target, terminal pending cleanup, late events, and actual background
cache writes from PlaybackService. The emulator's controlled 403 automatic
transition briefly reported ready before failing; its error still belonged to
the next generation, no late success commit followed the failure, and a valid
source recovered. A separate Android cache miss wrote a real file and the
fixture removed only its own cache entry afterward. Pre-ready error ownership
is covered by the controlled unit fixture, not claimed from that native run.
Evidence: `build/two-review-fixes-final-{tests,analyze,build}.log` and
`build/two-review-fixes-emulator-final.json`. Muted emulator tests verify
readiness/progress, not physical audible output.

## Historical preparation-only trial (before Media3 1.9.2 adapter)

The initial trial used `--dart-define=CYRENE_ANDROID_PLAYLIST_PRELOAD=true` to
try the rolling current/next window through upstream
`insertAudioSource` and `seek(index: ...)`. The engine and service share this
construction-time flag. Android uses `useLazyPreparation: false` in this trial;
iOS retains its previous lazy-preparation setting. No plugin or pub-cache source
was modified. At that stage normal builds kept the flag false. These observations
describe Media3 1.4.1 and are superseded by the native-preloading validation below.

**Playlist insertion is not proof of sample prebuffering.** A controlled HTTP
fixture served 120-second WAV files, adding a 1.5-second delay to the next file.
After inserting the next source and waiting three seconds, all three prepared
trials still first requested its audio after activation. Cold ready times were
1559/1566/1615 ms; playlist ready times were 1576/1616/1607 ms. This configuration
therefore did not hide the next source's network delay. Do not advertise it as
isolated native prebuffering or a demonstrated instant-switch improvement.

The same fixture checked a 403 next source: the long current item continued
playing before activation, activation was bounded by the harness timeout, and a
subsequent valid source recovered. A four-second current item also advanced to
the next item normally. This does not establish that all background preparation
errors are isolated: upstream error indices are not reliable failing-source IDs.

Two real QQ/Netease mixed-queue runs passed: position progress, rapid navigation,
pause/resume, natural advance, and manual selection near completion. Prepared
manual switches took 1331/1570 ms, including native readiness waits of 857/1012
ms. First loads took 6029/2370 ms and early unprepared next switches took
3463/2039 ms. These are sequential emulator observations, not a paired benchmark
proving superiority over the baseline. Automatic-advance observations include a
seek and the last 500 ms of the preceding song, so are not pure switch timings.

Reproduce with `tool/verify_official_playlist_preload.cjs` against an attached
debug VM; it hosts local Range-capable audio through adb reverse and logs request
times without third-party credentials. Business results are in
`build/official-playlist-mixed-r{1,2}-results.jsonl`; fixture results are in
`build/official-playlist-fixture-r2.json`. Tests use muted output and establish
native readiness/progress, not audible output. That preparation-only experiment
remained opt-in because it did not demonstrate early next-sample buffering.

## Native preloading validation (2026-10-15)

Two controlled runs on Media3 1.9.2 with the adapter confirmed all three next
sources were requested **before activation**. With a fixed 1.5-second response
delay, cold source readiness took 1550-1655 ms; prepared readiness took 12-33 ms.
With preloading disabled on the same Media3 version, playlist readiness took
1575/1577/1576 ms and no next-source audio request preceded activation. This
confirms the benefit of enabling preloading independently of the version upgrade.
These tests measure native readiness/progress, not audible output.

The 403 candidate did not interrupt the current long track. The production
JustAudioEngine was also exercised with that candidate: current audio continued
progressing without a current-track error, failed activation ended after 2014 ms
under a two-second test deadline, and a subsequent valid source played and
progressed. No errors are suppressed on the assumption that their index identifies
the failing source. Native fatal errors still take the existing recovery path.

Two actual QQ/Netease mixed-queue runs passed, including rapid selection,
pause/resume, automatic advance and a manual selection near completion. Prepared
manual switches took 660/476 ms, with native readiness waits of 463/236 ms.
Cold first loads still took 4801/3124 ms; unprepared early-next loads took
3607/2614 ms. Thus preloading does not guarantee instantaneous arbitrary or cold
selection. Complete-file caching was disabled in the first run and retained in
the second. These sequential observations are not a controlled cross-version
performance comparison.

Reports: `build/native-playlist-fixture-on-r1.json`,
`build/native-playlist-fixture-engine-r2.json`, and
`build/native-playlist-business-r{1,2}-results.jsonl`.
The disabled same-version control is `build/native-playlist-fixture-off-r1.json`.
An additional independent QQ and Netease round also passed all navigation,
progress and pause/resume checks. Prepared manual switches took 561 ms (QQ) and
530 ms (Netease), with native readiness waits of 197/274 ms. Results are in
`build/native-playlist-platforms-r3-results.jsonl`. Automatic observations
include seeking to 500 ms before the old track ends; their elapsed times must
not be presented as pure source-switch latency. The emulator has audio disabled,
so these checks do not replace listening on a physical device.

Final regression: 368 tests passed, six opt-in native QuickJS tests skipped;
analyzer clean; default-enabled debug APK built and installed with `adb install
-r` using the existing debug certificate. Account/source preferences were kept.
Evidence: `build/playlist-native-final-{tests,analyze,build}.log` and
`build/playlist-native-dependencies.log`. An audit against the hosted 0.10.6
snapshot found only the four documented source/configuration differences plus
the adapter notes file. Native stop/prepare and error handling are unchanged.

Business transaction generations, obsolete-result rejection, bounded native
operations/cleanup, loading-state termination and manual intent remain app-side.
Native source loading retains the official stop behavior. Dart does not add an
extra stop before calling setAudioSource.

## Cache and errors

Existing complete-file cache reads, manual downloads and stable-playback
background caching remain. Automatic writes are serialized; competing background
downloads are skipped. Android no longer invokes the retired stream-cache
MethodChannel. Old Android cache-directory fragments are disposable OS cache;
this change does not delete user downloads or cache metadata.

Official PlayerException does not expose the fork's nested HTTP status/Media3
code fields. Only explicit HTTP-valued exception codes are treated as HTTP
status; a generic Source error remains a source-read failure, not an invented
403 or token-expiration diagnosis.

## Validation

Run flutter pub get, flutter analyze and flutter test. Build Android with Java 17
and the existing project toolchain; do not edit the global pub cache. Verify
pubspec.lock uses the documented local just_audio 0.10.6 snapshot and Gradle
resolves Media3 1.9.2. Updating this dependency does not require upgrading
unrelated packages.

The emulator business harness is:
node tool/verify_business_playback_switch.cjs <VM-WebSocket-URL> <tag>

SWITCH_MIXED=1 tests QQ/Netease together; SWITCH_PLAYER_PAGE=1 also opens the
actual player page. The script runs current PlaybackService navigation, disables
complete-file cache reads for selected test tracks, then restores queue, mode,
volume, cache enablement, bypass keys and log sink. SWITCH_KEEP_CACHE=1 retains
the current cache switch during the scenario. It stops playback and mutes output, so native
ready/position assertions are not an acoustic-output test.

Retired plugin sources and fork-specific experiments were moved recoverably to
build/retired-just-audio-extension and are not shipped or analyzed. Historical
experiment results remain in playback-emulator-review-2026-10-15.md; their native
prebuffer/stop-removal numbers do not describe the current official dependency.

Migration checks: 367 tests passed, 6 opt-in native script tests skipped,
analyzer clean, Android debug APK built and installed over the emulator app with
the same certificate. Two complete QQ/Netease mixed-queue runs passed (cache
disabled and enabled), including rapid navigation, pause/resume, progress and a
manual selection near completion. The initial cold run had a load_source timeout
after about 7.4 seconds; pending cleared and the subsequent run recovered. That
failure is not attributed to a proven upstream defect or claimed fixed by the
version upgrade. See official-just-audio-* reports in build/.
