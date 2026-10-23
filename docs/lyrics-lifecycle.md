# Lyrics lifecycle

Lyrics are independent of audio URL resolution and native playback. A selected
track starts cache lookup and lyric acquisition as soon as its switch transaction
is accepted. It must not resolve another audio URL or rewrite the audio cache.

## Ownership

- `LyricRemoteSource` returns lyric fields plus a classified result, never an
  audio URL. `LyricPayload.merge` preserves the current playback metadata.
- `LyricRequestCoordinator` shares a task between foreground and prefetch.
  Foreground adoption shares the attempt count and deadline. Background work
  gets one attempt; foreground gets at most two for retryable failures.
- Each attempt has an 8-second total timeout, with a 1-second retry delay and
  an 18-second task budget. The backend lyric operation uses one attempt and a
  shared 7-second deadline, including QQ metadata lookup. Timeouts cancel the
  individual HTTP operation; Navidrome uses `AbortableRequest` on its shared
  client. Rate limits disable automatic retries and honor `Retry-After`.
- New selections invalidate obsolete tasks. Song identity, playback generation,
  backend/auth scope and cache generation protect UI updates and cache writes.
  Clearing cache or disposing playback cancels outstanding lyric tasks.
- `PlaybackLyricProjection` retains active lyrics while the pending track loads.
  Early pending results merge into the playable plan and are promoted at commit.
  A failed switch can restore the original track without displaying another
  track's lyrics. Floating lyrics only consume the active projection.

## Cache and results

Ready lyrics refresh after 7 days but remain usable offline. Failed refreshes
do not delete the text or extend its freshness. Disk retention is bounded to
1,000 entries / 32 MiB, evicting oldest fetched entries; memory retains 64.
Confirmed absence is cached for 30 minutes. Ambiguous empty responses and
transient errors are not negative cached. Private-library cache identities
include a digest of the server and account; audio quality is not part of identity.

Backend `/lyrics/*` responses classify `ready`, `empty`, `unavailable` and
`unsupported`. Upstream HTTP/business failures are checked before normalization.
Only explicit provider absence (currently Netease `nolyric`) is authoritative.
The lyric cache uses a new internal namespace to bypass previously cached empty
success responses. Manual refresh bypasses the cache. Other API cache rules and
audio providers' playback request policies are unchanged. Upstream 401/403 are
mapped to lyric failure, not client authentication failure.

All lyric views show loading until the bounded recovery finishes; a failed
request offers lyric-only retry. Existing text remains visible during refresh.
Unsupported requests do not repeatedly retry. Plain-text rendering is unchanged.

## Validation

Focused tests cover adoption, bounded retries, HTTP cancellation, late responses,
cache clearing during requests, cache expiration across restart, early lyrics,
playback metadata preservation, old selection isolation, manual retry, and the
existing playback navigation/recovery scenarios. Backend tests exercise empty
responses, explicit absence, cache namespace rollover, manual bypass, upstream
authentication/rate limiting and QQ's metadata/lyric path.

Deploy the backend changes in `cyapi-workers` before distributing the client to
obtain the full result-classification and cache behavior. Old backend empty
responses remain non-authoritative on the client. Automated tests do not establish
real-provider availability or device rendering/performance under real networks.
