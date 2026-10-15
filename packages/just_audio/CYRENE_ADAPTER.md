# Cyrene Android playback adapter

Base: the unmodified pub.dev just_audio **0.10.6** release, retrieved from the
hosted pub cache. LICENSE, Dart, Android and Darwin sources are retained. The
upstream example and tests are not vendored. The global pub cache is untouched.

Changes from that release are deliberately limited to:

1. `android/build.gradle.kts`: pin Media3 artifacts to **1.9.2**, including
   explicit datasource/database dependencies for the stream cache.
2. `lib/just_audio.dart`: optional constructor parameter
   `androidPlaylistPreloadDuration` (null preserves the native default, zero
   disables, maximum 30 seconds). Configure every native Android incarnation
   before it loads a source, using that incarnation's own method channel.
3. `android/.../AudioPlayer.java`: one method-channel case calls upstream
   `ExoPlayer.setPreloadConfiguration`. Upstream LoadControl, player count,
   stop/prepare and playback error handling remain unchanged.
4. `analysis_options.yaml`: disable the inherited super-parameter style lint
   so the upstream constructors can remain unchanged.
5. Optional `ProgressiveAudioSource.androidStreamCache` registers bounded source
   identity metadata. Only registered HTTP progressive sources use the process-wide
   `StreamCacheManager`: Media3 SimpleCache/CacheDataSource, mutable span-LRU quota,
   no blocking cache locks, scoped management and cache-specific network fallback.
   Headers and the DefaultHttpDataSource network stack are unchanged. Cache IO runs
   on loading/management threads, not the platform thread. HLS/DASH are excluded.
   The platform-interface package and other operating-system implementations are
   untouched. Registration failure falls back to ordinary playback.

The app owns a rolling current/next playlist using the existing official
insert/remove/seek APIs. Media3's default LoadControl prioritizes loading the
current item over preloading. The app requests three seconds of next-item data.
Inserting an item does not establish that it has buffered.

The app feature flag is `CYRENE_ANDROID_PLAYLIST_PRELOAD`. Keep this boundary
when rebasing onto a newer upstream release; upstream APIs may eventually remove
the need for the adapter. The current cache does not restore the retired custom
preload/source-manager extension. See `docs/android-stream-cache.md` for lifecycle
rules and verification.

References:

- https://developer.android.com/jetpack/androidx/releases/media3#1.5.0
- https://developer.android.com/reference/androidx/media3/exoplayer/ExoPlayer.PreloadConfiguration
- https://pub.dev/packages/just_audio
- https://developer.android.com/media/media3/exoplayer/downloading-media
