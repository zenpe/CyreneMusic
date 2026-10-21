package com.ryanheise.just_audio;

import androidx.media3.common.PlaybackException;
import androidx.media3.datasource.HttpDataSource;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Set;

/** Preserve HTTP evidence through both the load result and playback event. */
final class PlaybackErrorCode {
    private PlaybackErrorCode() {}

    static int from(PlaybackException error) {
        Set<Throwable> visited = Collections.newSetFromMap(new IdentityHashMap<>());
        for (Throwable cause = error; cause != null && visited.add(cause); cause = cause.getCause()) {
            if (cause instanceof HttpDataSource.InvalidResponseCodeException) {
                return ((HttpDataSource.InvalidResponseCodeException) cause).responseCode;
            }
        }
        // Media3 codes distinguish transport, decoding and renderer failures.
        // Do not reduce them to ExoPlaybackException.TYPE_SOURCE (zero).
        return error.errorCode;
    }
}
