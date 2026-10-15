# Android streaming cache

Android HTTP progressive playback and Media3's three-second next-item preload
use a shared SimpleCache/CacheDataSource store. There is one store per process,
independent of player disposal and Flutter hot restart. No extra player, whole-song
downloader, network stack replacement or playback deadline change is introduced.
Windows/iOS and explicit user downloads retain their existing implementations.

## Identity and completeness

The resource key hashes the exact URL (including signed parameters), normalized
request headers, platform/song/quality and hashed account/resolver fingerprint.
Range offsets do not enter the key. Different signed URLs are deliberately not
merged. Changing a URL, account, quality or headers can reduce hits; this is safer
than merging bytes from potentially different representations. Cache directory
contents are Media3 fragments, never standalone media files. Android's legacy
complete-file API returns no hits and explicit downloads fetch complete files.
Apple/HLS/DASH sources are excluded. Resolved-URL caches and lyrics are separate.

## Lifecycle and maintenance

- The cache preference and byte quota configure the native store. LRU evicts
  spans at the live quota without releasing/reopening the cache. Active write
  buffers are not counted as committed cache size until their spans commit.
- Cache initialization/management use a worker; actual reads/writes use Media3
  loading threads. Registration uses a separate memory-only lock on the platform
  thread. New cache opens use tryLock and bypass busy maintenance immediately.
  No FLAG_BLOCK_ON_CACHE: locked spans also use upstream immediately.
- Disabling bypasses new opens. Existing reads/writes finish through their current
  connection, without reopening a potentially expired signed URL. The preference
  takes effect as each connection is replaced or closed.
- Clear/delete immediately hide and bypass affected keys. Idle resources are
  removed now; active resources keep their valid read/connection and are deleted
  on the management worker after the last close, including late writes. Physical
  disk space for an active resource is therefore released later. A persisted
  removal marker lets process initialization finish deletion after an abrupt exit.
  Cleanup failure keeps the key bypassed. Playback buffers are not flushed.
- Cache-specific read/write errors have one upstream fallback at the correct
  byte offset. A failing write sink may require a second HTTP open because Media3
  opens upstream before the sink. HTTP authentication/403/timeout errors are not
  cache errors and do not trigger this fallback. No resolver request is added here.
- Cache initialization failure bypasses caching; playback remains available.
  Management errors propagate instead of reporting successful deletion. Method
  calls have bounded waits. A custom-directory change requires process restart.
- Only former automatic-cache filenames/layout and manifests are cleaned. The
  cache root is never recursively deleted; user downloads/settings remain intact.

## Verification

`tool/verify_android_stream_cache.cjs <debug-vm-websocket>` runs a real Android
Media3 player against a local Range-capable WAV fixture. It removes only unique QA
entries and restores configuration. Global-clear/quota cases run only if no user
cache existed. The fixture verifies new-player cache reuse with zero additional
HTTP requests, seek misses, resource/account/header isolation, disabling, deletion
with an open writer, live quota/clear, and unwritable-cache fallback. It records
`build/android-stream-cache-fixture.json`. This verifies readiness and progress;
the emulator does not establish physical audible output.

Review regressions additionally hold the native maintenance lock while registering
and acquiring a source (JVM tests), and use a throttled single-use URL that rejects
all subsequent opens. The emulator must keep receiving and buffering new bytes
after deletion/disable without a reconnect; checking buffered position growth
avoids mistaking already buffered audio for a healthy upstream connection.
Set `STREAM_CACHE_CRASH_TEST=1` to additionally kill/relaunch the emulator app
with a live, deleted cache reader. The fixture verifies that its committed files
remain readable until termination and disappear on the next process startup.

Review-fix verification: both JVM lock-contention tests and 25 emulator checks
passed, including continued upstream reads after delete/disable on a single-use
signed URL and persisted deletion after forced process death. Analyzer clean;
latest Android x64 debug APK rebuilt and installed with account/source settings
preserved. The quota/global-clear checks from the earlier empty-store run are not
rerun against an emulator containing user cache; this run uses per-resource delete.

Verified on 2026-10-15: analyzer clean; 65 related Dart regression tests passed;
Android x64 debug build succeeded. The controlled native fixture passed all 16
checks, reused 3,148,784 committed bytes with zero extra replay requests, and
used two HTTP opens in the injected write-sink failure (initial open plus one
fallback). The QQ/NetEase mixed business run passed manual/rapid/automatic
navigation and pause/resume with caching enabled. Prepared activation was 986 ms,
automatic advancement 1,135 ms, and first cold playback 5,420 ms. These are single
run observations, not a cross-device latency guarantee or an A/B improvement claim.
Business evidence: `build/native-cache-mixed-final-results.jsonl` and corresponding
events/native logs. The debug build is installed over the existing emulator app.

Native-cache hits avoid downloading already cached bytes. They cannot accelerate
third-party link parsing or an uncached CDN connection, and partial cached bytes
do not establish full offline availability.
