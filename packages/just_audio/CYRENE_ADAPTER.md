# Cyrene Android playlist-preload adapter

Base: the unmodified pub.dev just_audio **0.10.6** release, retrieved from the
hosted pub cache. LICENSE, Dart, Android and Darwin sources are retained. The
upstream example and tests are not vendored. The global pub cache is untouched.

Changes from that release are deliberately limited to:

1. `android/build.gradle.kts`: pin the four Media3 artifacts to **1.9.2**.
2. `lib/just_audio.dart`: optional constructor parameter
   `androidPlaylistPreloadDuration` (null preserves the native default, zero
   disables, maximum 30 seconds). Configure every native Android incarnation
   before it loads a source, using that incarnation's own method channel.
3. `android/.../AudioPlayer.java`: one method-channel case calls upstream
   `ExoPlayer.setPreloadConfiguration`. No custom LoadControl, source manager,
   HTTP/cache pipeline, extra player, stop removal or altered error handling.
4. `analysis_options.yaml`: disable the inherited super-parameter style lint
   so the upstream constructors can remain unchanged.

The app owns a rolling current/next playlist using the existing official
insert/remove/seek APIs. Media3's default LoadControl prioritizes loading the
current item over preloading. The app requests three seconds of next-item data.
Inserting an item does not establish that it has buffered.

The app feature flag is `CYRENE_ANDROID_PLAYLIST_PRELOAD`. Keep this boundary
when rebasing onto a newer upstream release; upstream APIs may eventually remove
the need for the adapter. Do not restore the retired custom plugin extension.

References:

- https://developer.android.com/jetpack/androidx/releases/media3#1.5.0
- https://developer.android.com/reference/androidx/media3/exoplayer/ExoPlayer.PreloadConfiguration
- https://pub.dev/packages/just_audio
