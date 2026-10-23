package com.ryanheise.just_audio;

import static org.junit.Assert.*;
import androidx.media3.common.PlaybackException;
import androidx.media3.datasource.HttpDataSource;
import java.io.IOException;
import java.net.SocketTimeoutException;
import java.util.Collections;
import org.junit.Test;

public class PlaybackErrorCodeTest {
    @Test public void nestedHttpStatusSurvivesSourceError() {
        for (int status : new int[] {401, 403, 404, 410, 429, 503}) {
            HttpDataSource.InvalidResponseCodeException response =
                new HttpDataSource.InvalidResponseCodeException(status, "Rejected", null,
                    Collections.emptyMap(), null, new byte[0]);
            PlaybackException error = new PlaybackException("Source error",
                new IOException(response), PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS);
            assertEquals(status, PlaybackErrorCode.from(error));
        }
    }

    @Test public void transportTimeoutRemainsDistinctFromHttpRejection() {
        PlaybackException error = new PlaybackException("Source error", new SocketTimeoutException(),
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT);
        assertEquals(PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
            PlaybackErrorCode.from(error));
    }

    @Test public void decodingFailureIsNotReportedAsHttpOrNetwork() {
        PlaybackException error = new PlaybackException("Renderer error", null,
            PlaybackException.ERROR_CODE_DECODING_FAILED);
        assertEquals(PlaybackException.ERROR_CODE_DECODING_FAILED, PlaybackErrorCode.from(error));
    }
}
