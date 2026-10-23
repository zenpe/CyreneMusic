package com.ryanheise.just_audio;

import android.content.Context;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import androidx.media3.common.C;
import androidx.media3.database.StandaloneDatabaseProvider;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DataSink;
import androidx.media3.datasource.DataSpec;
import androidx.media3.datasource.TransferListener;
import androidx.media3.datasource.cache.Cache;
import androidx.media3.datasource.cache.CacheDataSource;
import androidx.media3.datasource.cache.CacheDataSink;
import androidx.media3.datasource.cache.CacheEvictor;
import androidx.media3.datasource.cache.CacheSpan;
import androidx.media3.datasource.cache.ContentMetadataMutations;
import androidx.media3.datasource.cache.ContentMetadata;
import androidx.media3.datasource.cache.SimpleCache;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.media3.exoplayer.source.WrappingMediaSource;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.Result;
import java.io.File;
import java.io.IOException;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.locks.ReentrantLock;
import org.json.JSONObject;

/** Process-wide cache. Player disposal/recreation never releases a live store. */
final class StreamCacheManager {
    private static final StreamCacheManager INSTANCE = new StreamCacheManager();
    static StreamCacheManager get() { return INSTANCE; }
    private static final String META = "cyrene.identity.v1";
    private static final String PENDING_REMOVAL = "cyrene.pendingRemoval.v1";
    private static final String COMPLETE_OBSERVED = "cyrene.completeObserved.v1";
    private static final String VALIDATOR = "cyrene.etag.v1";
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final ExecutorService copier = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    // The platform thread only touches this short, memory-only registry lock.
    // It must never share a monitor with cache/database/filesystem operations.
    private final Object registrationLock = new Object();
    private final ReentrantLock stateLock = new ReentrantLock();
    private final Map<String, Map<String, String>> registrations = new LinkedHashMap<>();
    private final Map<String, Integer> readers = new HashMap<>();
    private final Set<String> pendingRemoval = java.util.concurrent.ConcurrentHashMap.newKeySet();
    private volatile SimpleCache cache;
    private volatile boolean enabled;
    private String directory;
    private MutableLruEvictor evictor;
    private volatile CompleteAudioStore complete;
    private long quota;
    private boolean copying;
    private long reservedBytes;
    private String copyingKey;
    private final Set<String> refreshTargets = new HashSet<>();

    boolean handle(Context context, MethodCall call, Result result) {
        if (!call.method.startsWith("streamCache.")) return false;
        if (call.method.equals("streamCache.register")) {
            synchronized (registrationLock) {
                Map<String, String> metadata = call.argument("metadata");
                registrations.put(call.argument("id"), new HashMap<>(metadata));
                while (registrations.size() > 512) {
                    registrations.remove(registrations.keySet().iterator().next());
                }
            }
            result.success(null);
            return true;
        }
        worker.execute(() -> {
            try {
                Object value = null;
                switch (call.method) {
                case "streamCache.configure": {
                    boolean nextEnabled = Boolean.TRUE.equals(call.argument("enabled"));
                    // Respect disabling even if subsequent disk maintenance fails.
                    if (!nextEnabled) enabled = false;
                    if (!nextEnabled && complete != null) complete.invalidateJobs();
                    String requested = new File((String)call.argument("directory")).getCanonicalPath();
                    long bytes = ((Number)call.argument("maxBytes")).longValue();
                    if (bytes <= 0) throw new IllegalArgumentException("Invalid cache quota");
                    if (cache == null) {
                        evictor = new MutableLruEvictor(bytes);
                        SimpleCache opened = new SimpleCache(new File(requested), evictor,
                                new StandaloneDatabaseProvider(context.getApplicationContext()));
                        try {
                            opened.checkInitialization();
                            // A process may die while a deleted resource still has
                            // an active reader. Finish its persisted deletion first.
                            for (String key : new HashSet<>(opened.getKeys())) {
                                if (opened.getContentMetadata(key).get(PENDING_REMOVAL, 0L) == 1L) {
                                    finishRemoval(opened, key);
                                }
                            }
                        }
                        catch (Exception error) { opened.release(); throw error; }
                        directory = requested;
                        cache = opened;
                    } else if (!requested.equals(directory)) {
                        throw new IllegalStateException("Cache directory changes require process restart");
                    }
                    if (complete == null) complete = new CompleteAudioStore(new File(requested + "-complete-v2"));
                    stateLock.lock();
                    try {
                        if (quota != bytes) complete.invalidateJobs();
                        quota = bytes;
                        complete.trim(bytes);
                        updateQuota();
                        enabled = nextEnabled;
                        pruneIdle();
                    } finally { stateLock.unlock(); }
                    break;
                }
                case "streamCache.lookup": {
                    Map<String, String> identity = call.argument("identity");
                    value = enabled && complete != null ? complete.lookup(identity) : null;
                    break;
                }
                case "streamCache.stats": value = stats(); break;
                case "streamCache.clear": remove(null, null, null, null); break;
                case "streamCache.refresh": {
                    Map<String, String> identity = call.argument("identity");
                    stateLock.lock();
                    try {
                        if (complete != null) complete.invalidateJobs();
                        refreshTargets.clear();
                        refreshTargets.add(CompleteAudioStore.identity(identity));
                        removeFragments(identity.get("source"), identity.get("songId"), identity.get("quality"), identity.get("owner"));
                    } finally { stateLock.unlock(); }
                    break;
                }
                case "streamCache.cancelRefresh": {
                    Map<String, String> identity = call.argument("identity");
                    refreshTargets.remove(CompleteAudioStore.identity(identity));
                    break;
                }
                case "streamCache.delete": remove(call.argument("source"),
                        call.argument("songId"), call.argument("quality"), call.argument("owner")); break;
                default: main.post(result::notImplemented); return;
                }
                final Object reply = value;
                main.post(() -> result.success(reply));
                if (call.method.equals("streamCache.configure") && enabled) tryPromoteAny();
            } catch (Exception error) {
                // Never include upstream URLs, headers, tokens or filesystem paths.
                main.post(() -> result.error("stream_cache", "Audio cache operation failed", null));
            }
        });
        return true;
    }

    Map<String, String> takeRegistration(String id) {
        synchronized (registrationLock) { return registrations.remove(id); }
    }

    DataSource.Factory wrap(DataSource.Factory upstream, String uri,
            Map<?, ?> headers, Map<String, String> metadata) {
        if (metadata == null || !(uri.startsWith("https://") || uri.startsWith("http://"))) return upstream;
        final String key = fragmentKey(uri, metadata.get("owner"));
        // Metadata contains no URL or headers; scope need not be persisted in clear.
        Map<String, String> stored = new HashMap<>(metadata);
        stored.remove("scope");
        final String payload = new JSONObject(stored).toString();
        final long epoch = complete == null ? -1 : complete.epoch();
        worker.execute(this::makeRoomForIncoming);
        return () -> new StreamDataSource(upstream, key, payload, epoch);
    }

    private void makeRoomForIncoming() {
        stateLock.lock();
        try {
            if (!enabled || complete == null || cache == null) return;
            pruneIdle();
            synchronized (cache) {
                complete.trim(Math.max(0, quota - cache.getCacheSpace() - reservedBytes
                        - evictor.pendingBytes() - Math.min(quota / 5, 32L * 1024 * 1024)), refreshTargets);
            }
            updateQuota();
        } catch (Exception ignored) { }
        finally { stateLock.unlock(); }
    }

    static String fragmentKey(String uri, String owner) {
        return digest(owner == null || "public".equals(owner) ? uri : owner + "\u0000" + uri);
    }

    private void pruneIdle() {
        if (cache == null) return;
        synchronized (cache) {
            evictor.pruneIdle(cache, System.currentTimeMillis(), Math.min(quota / 5, 128L * 1024 * 1024));
        }
    }

    /** MediaSource lifetime includes paused/current/prepared slots and all seeks. */
    MediaSource protectCompleteSource(MediaSource child, String uri) {
        CompleteAudioStore store = complete;
        Uri parsed = Uri.parse(uri);
        if (store == null || !"file".equals(parsed.getScheme())) return child;
        String path = parsed.getPath();
        return new WrappingMediaSource(child) {
            private boolean retained;
            @Override protected void prepareSourceInternal() {
                retained = store.retainPath(path);
                super.prepareSourceInternal();
            }
            @Override protected void releaseSourceInternal() {
                try { super.releaseSourceInternal(); }
                finally {
                    if (retained) {
                        retained = false;
                        worker.execute(() -> {
                            store.releasePath(path);
                            try { store.trim(quota); } catch (Exception ignored) { }
                            updateQuota();
                        });
                    }
                }
            }
        };
    }

    private void updateQuota() {
        if (cache != null && complete != null) synchronized (cache) {
            evictor.setMaxBytes(cache, Math.max(0, quota - complete.bytes() - reservedBytes));
        }
    }

    // Management stays responsive while a separate, single copier does disk IO.
    // No upstream factory: missing bytes cannot cause a hidden network request.
    private void tryPromoteAny() {
        stateLock.lock();
        try {
        if (!enabled || copying || complete == null || cache == null) return;
        for (String key : cache.getKeys()) {
            try {
                if (pendingRemoval.contains(key)) continue;
                ContentMetadata content = cache.getContentMetadata(key);
                if (content.get(COMPLETE_OBSERVED, 0L) != 1L) continue;
                long length = ContentMetadata.getContentLength(content);
                if (length <= 0 || length > quota / 2 || !cache.isCached(key, 0, length)) continue;
                JSONObject json = new JSONObject(content.get(META, "{}"));
                if (!json.has("owner")) continue;
                Map<String, String> metadata = new HashMap<>();
                for (Iterator<String> fields = json.keys(); fields.hasNext();) {
                    String field = fields.next(); metadata.put(field, json.getString(field));
                }
                if (complete.lookup(metadata) != null && !refreshTargets.contains(CompleteAudioStore.identity(metadata))) {
                    if (!readers.containsKey(key)) finishRemoval(cache, key);
                    continue;
                }
                synchronized (cache) { evictor.pinned.add(key); }
                reservedBytes = length;
                updateQuota();
                synchronized (cache) {
                    complete.trim(Math.max(0, quota - cache.getCacheSpace() - evictor.pendingBytes() - length), refreshTargets);
                    if (complete.bytes() + cache.getCacheSpace() + evictor.pendingBytes() + length > quota) {
                        reservedBytes = 0;
                        if (!readers.containsKey(key)) evictor.pinned.remove(key);
                        updateQuota();
                        continue;
                    }
                }
                copying = true;
                copyingKey = key;
                long epoch = complete.epoch();
                copier.execute(() -> copyComplete(key, length, metadata, epoch));
                return;
            } catch (Exception ignored) { /* Optional cache cannot fail playback. */ }
        }
        } finally { stateLock.unlock(); }
    }

    private void copyComplete(String key, long length, Map<String, String> metadata, long epoch) {
        File staged = null;
        String checksum = null;
        JSONObject format = null;
        try {
            staged = complete.temporary();
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            DataSource input = new CacheDataSource.Factory().setCache(cache)
                    .setCacheWriteDataSinkFactory(null)
                    .setUpstreamDataSourceFactory(() -> new DataSource() {
                        @Override public long open(DataSpec spec) throws IOException {
                            throw new IOException("Incomplete cached resource");
                        }
                        @Override public int read(byte[] data, int offset, int length) throws IOException {
                            throw new IOException("Incomplete cached resource");
                        }
                        @Override public Uri getUri() { return null; }
                        @Override public void close() { }
                        @Override public void addTransferListener(TransferListener listener) { }
                    }).createDataSource();
            try (FileOutputStream output = new FileOutputStream(staged)) {
                try {
                    input.open(new DataSpec.Builder().setUri("https://cache.invalid/")
                            .setKey(key).setLength(length).build());
                    byte[] buffer = new byte[64 * 1024]; long copied = 0;
                    while (copied < length) {
                        if (!enabled || complete.epoch() != epoch) throw new IOException("Cancelled cache copy");
                        int n = input.read(buffer, 0, (int)Math.min(buffer.length, length - copied));
                        if (n <= 0) throw new IOException("Incomplete cached resource");
                        output.write(buffer, 0, n); digest.update(buffer, 0, n); copied += n;
                    }
                    output.getFD().sync();
                    checksum = CompleteAudioStore.hex(digest.digest());
                } finally { input.close(); }
            }
            format = inspectAudio(staged);
        } catch (Exception ignored) { }
        File output = staged; String hash = checksum; JSONObject properties = format;
        worker.execute(() -> {
            stateLock.lock();
            try {
                if (properties != null && enabled && complete.publish(output, metadata, hash, properties, epoch)) {
                    refreshTargets.remove(CompleteAudioStore.identity(metadata));
                    // Remove redundant fragments only after the complete object commits.
                    pendingRemoval.add(key);
                    cache.applyContentMetadataMutations(key,
                            new ContentMetadataMutations().set(PENDING_REMOVAL, 1L));
                    if (!readers.containsKey(key)) {
                        finishRemoval(cache, key); pendingRemoval.remove(key);
                    }
                } else if (complete.epoch() == epoch) {
                    // Invalid/unsupported resources must not spin in the copier queue.
                    cache.applyContentMetadataMutations(key,
                            new ContentMetadataMutations().remove(COMPLETE_OBSERVED));
                }
            } catch (Exception ignored) { }
            finally {
                if (output != null) output.delete();
                if (complete.epoch() == epoch) refreshTargets.remove(CompleteAudioStore.identity(metadata));
                synchronized (cache) { if (!readers.containsKey(key)) evictor.pinned.remove(key); }
                copying = false; copyingKey = null; reservedBytes = 0; updateQuota();
                try {
                    if (pendingRemoval.contains(key) && !readers.containsKey(key)) {
                        finishRemoval(cache, key); pendingRemoval.remove(key);
                    }
                } catch (IOException ignored) { }
                tryPromoteAny();
                pruneIdle();
                stateLock.unlock();
            }
        });
    }

    private static JSONObject inspectAudio(File file) throws Exception {
        MediaExtractor extractor = new MediaExtractor();
        try {
            extractor.setDataSource(file.getAbsolutePath());
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat format = extractor.getTrackFormat(i);
                String mime = format.getString(MediaFormat.KEY_MIME);
                if (mime == null || !mime.startsWith("audio/")) continue;
                JSONObject out = new JSONObject().put("mime", mime);
                for (String name : new String[]{MediaFormat.KEY_SAMPLE_RATE, MediaFormat.KEY_CHANNEL_COUNT,
                        MediaFormat.KEY_BIT_RATE, MediaFormat.KEY_DURATION})
                    if (format.containsKey(name)) out.put(name,
                            name.equals(MediaFormat.KEY_DURATION) ? format.getLong(name) : format.getInteger(name));
                extractor.selectTrack(i);
                java.nio.ByteBuffer sample = java.nio.ByteBuffer.allocate(65536);
                if (extractor.readSampleData(sample, 0) <= 0) throw new IOException("No audio samples");
                return out;
            }
            throw new IOException("Not supported audio");
        } finally { extractor.release(); }
    }

    private static String digest(String value) {
        try {
            byte[] bytes = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder();
            for (byte b : bytes) out.append(String.format(Locale.ROOT, "%02x", b & 255));
            return out.toString();
        } catch (Exception impossible) { throw new IllegalStateException(impossible); }
    }

    private Map<String, Object> stats() throws Exception {
        stateLock.lock();
        try {
            pruneIdle();
            Map<String, Object> result = new HashMap<>();
            Map<String, Set<String>> groups = new HashMap<>();
            long bytes = 0;
            Set<String> completeIdentities = new HashSet<>();
            if (complete != null) {
                bytes += complete.bytes();
                for (Map<String, String> meta : complete.identities()) {
                    String song = meta.get("songId") + ":" + meta.get("quality");
                    groups.computeIfAbsent(meta.get("source"), ignored -> new HashSet<>()).add(song);
                    completeIdentities.add(meta.get("source") + ":" + song);
                }
            }
            if (cache != null) for (String key : cache.getKeys()) {
                if (pendingRemoval.contains(key)) continue;
                Set<CacheSpan> spans = cache.getCachedSpans(key);
                if (spans.isEmpty()) continue;
                for (CacheSpan span : spans) bytes += span.length;
                JSONObject meta = new JSONObject(cache.getContentMetadata(key).get(META, "{}"));
                String source = meta.optString("source", "unknown");
                groups.computeIfAbsent(source, ignored -> new HashSet<>())
                        .add(meta.optString("songId") + ":" + meta.optString("quality"));
            }
            int count = 0;
            for (Map.Entry<String, Set<String>> entry : groups.entrySet()) {
                result.put(entry.getKey(), entry.getValue().size());
                count += entry.getValue().size();
            }
            result.put("totalFiles", count);
            result.put("completeFiles", completeIdentities.size());
            result.put("partialFiles", Math.max(0, count - completeIdentities.size()));
            result.put("totalSize", bytes);
            result.put("completeSize", complete == null ? 0L : complete.bytes());
            result.put("partialSize", cache == null ? 0L : cache.getCacheSpace());
            long temporary = reservedBytes;
            if (cache != null) synchronized (cache) { temporary += evictor.pendingBytes(); }
            result.put("temporarySize", temporary);
            result.put("totalSize", (complete == null ? 0 : complete.bytes())
                    + (cache == null ? 0 : cache.getCacheSpace()) + temporary);
            return result;
        } finally { stateLock.unlock(); }
    }

    private void remove(String source, String songId, String quality, String owner) throws Exception {
        stateLock.lock();
        try {
            if (complete != null) complete.remove(source, songId, quality, owner);
            if (source == null) refreshTargets.clear();
            removeFragments(source, songId, quality, owner);
            updateQuota();
        } finally { stateLock.unlock(); }
    }

    private void removeFragments(String source, String songId, String quality, String owner) throws Exception {
            if (cache == null) return;
            Set<String> keys = new HashSet<>(cache.getKeys());
            keys.addAll(readers.keySet());
            for (String key : keys) {
                JSONObject meta = new JSONObject(cache.getContentMetadata(key).get(META, "{}"));
                if (source != null && (!source.equals(meta.optString("source")) ||
                        !songId.equals(meta.optString("songId")) ||
                        (quality != null && !quality.equals(meta.optString("quality"))) ||
                        (owner != null && !owner.equals(meta.optString("owner"))))) continue;
                // Preserve the current read/connection. Persist the deletion so
                // even process death before close cannot resurrect these bytes.
                pendingRemoval.add(key);
                cache.applyContentMetadataMutations(key,
                        new ContentMetadataMutations().set(PENDING_REMOVAL, 1L));
                if (!readers.containsKey(key) && !key.equals(copyingKey)) {
                    finishRemoval(cache, key);
                    pendingRemoval.remove(key);
                }
            }
    }

    private boolean acquire(String key, String metadata) throws IOException {
        // Optional caching must not queue a foreground load behind maintenance.
        if (!stateLock.tryLock()) return false;
        try {
            if (!enabled || cache == null || pendingRemoval.contains(key)) return false;
            ContentMetadataMutations mutations = new ContentMetadataMutations();
            mutations.set(META, metadata);
            cache.applyContentMetadataMutations(key, mutations);
            readers.put(key, readers.getOrDefault(key, 0) + 1);
            synchronized (cache) { evictor.pinned.add(key); }
            return true;
        } finally { stateLock.unlock(); }
    }

    private void release(String key, boolean completeRead, boolean changedResource) {
        // Media3 close flushes the sink first. Disk deletion then belongs to the
        // management worker, never the platform thread or a new source load.
        worker.execute(() -> {
            stateLock.lock();
            try {
                if (changedResource) {
                    pendingRemoval.add(key);
                    cache.applyContentMetadataMutations(key,
                            new ContentMetadataMutations().set(PENDING_REMOVAL, 1L));
                }
                int count = readers.getOrDefault(key, 1) - 1;
                if (count > 0) readers.put(key, count);
                else {
                    readers.remove(key);
                    synchronized (cache) { if (!key.equals(copyingKey)) evictor.pinned.remove(key); }
                    if (pendingRemoval.contains(key) && !key.equals(copyingKey)) {
                        finishRemoval(cache, key);
                        pendingRemoval.remove(key);
                    }
                }
                if (completeRead && !pendingRemoval.contains(key)
                        && !cache.getCachedSpans(key).isEmpty()) {
                    cache.applyContentMetadataMutations(key,
                            new ContentMetadataMutations().set(COMPLETE_OBSERVED, 1L));
                }
            } catch (Exception ignored) {
                // Keep the persisted marker and bypass on failure; retry clear or
                // the next process initialization will finish the removal.
            } finally { stateLock.unlock(); }
            tryPromoteAny();
            // Extractor repositioning and seeks close/reopen DataSources.
            // Refresh intent belongs to playback, which cancels it explicitly
            // on source replacement/stop. A stream close must not consume it.
            pruneIdle();
            updateQuota();
        });
    }

    private static void finishRemoval(SimpleCache cache, String key) throws IOException {
        cache.removeResource(key);
        cache.applyContentMetadataMutations(key,
                new ContentMetadataMutations().remove(PENDING_REMOVAL));
    }

    /** Cache capacity is optional: stop writing without reopening the HTTP stream. */
    private final class BudgetedSink implements DataSink {
        private final String key;
        private final long epoch;
        private DataSink sink;
        private boolean owned;
        BudgetedSink(String key, long epoch) { this.key = key; this.epoch = epoch; }
        @Override public void open(DataSpec spec) throws IOException {
            synchronized (cache) {
                owned = evictor.writers.add(key);
            }
            if (!owned) return;
            sink = new CacheDataSink.Factory().setCache(cache)
                    .setFragmentSize(2 * 1024 * 1024).createDataSink();
            try { sink.open(spec); } catch (IOException error) { close(); }
        }
        @Override public void write(byte[] data, int offset, int length) throws IOException {
            if (sink == null) return;
            // Memory-only admission does not contend with statistics or disk maintenance.
            boolean admitted = enabled && complete.epoch() == epoch
                    && !pendingRemoval.contains(key) && evictor.reserve(key, length);
            if (!admitted) {
                close();
                // Reclaim on the worker, never on the native playback thread.
                worker.execute(StreamCacheManager.this::makeRoomForIncoming);
                return;
            }
            try { sink.write(data, offset, length); } catch (IOException error) { close(); }
        }
        @Override public void close() {
            try { if (sink != null) sink.close(); } catch (IOException ignored) { }
            finally {
                sink = null;
                if (owned) synchronized (cache) {
                    evictor.releaseReservation(key); evictor.writers.remove(key); owned = false;
                }
            }
        }
    }

    private final class StreamDataSource implements DataSource {
        private final DataSource.Factory upstream;
        private final String key;
        private final String metadata;
        private final List<TransferListener> listeners = new ArrayList<>();
        private DataSource delegate;
        private DataSpec spec;
        private long consumed;
        private boolean leased;
        private long openedLength = C.LENGTH_UNSET;
        private boolean reachedEnd;
        private boolean hadSpans;
        private boolean changedResource;
        private boolean validated;
        private int upstreamOpens;
        private final long epoch;

        StreamDataSource(DataSource.Factory upstream, String key, String metadata, long epoch) {
            this.upstream = upstream; this.key = key; this.metadata = metadata; this.epoch = epoch;
        }
        @Override public void addTransferListener(TransferListener listener) {
            listeners.add(listener);
            if (delegate != null) delegate.addTransferListener(listener);
        }
        private DataSource listen(DataSource source) {
            for (TransferListener listener : listeners) source.addTransferListener(listener);
            return source;
        }
        @Override public long open(DataSpec dataSpec) throws IOException {
            spec = dataSpec.buildUpon().setKey(key)
                    .setFlags(dataSpec.flags | DataSpec.FLAG_ALLOW_CACHE_FRAGMENTATION).build(); consumed = 0;
            reachedEnd = false; openedLength = C.LENGTH_UNSET;
            changedResource = false; validated = true; upstreamOpens = 0;
            try {
                try { leased = complete != null && epoch == complete.epoch() && acquire(key, metadata); }
                catch (IOException ignored) { leased = false; }
                hadSpans = leased && !cache.getCachedSpans(key).isEmpty();
                delegate = listen(leased ? new CacheDataSource.Factory().setCache(cache)
                        .setCacheWriteDataSinkFactory(() -> new BudgetedSink(key, epoch))
                        .setUpstreamDataSourceFactory(() -> observe(upstream.createDataSource()))
                        .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
                        .createDataSource() : upstream.createDataSource());
                openedLength = delegate.open(spec);
                return openedLength;
            } catch (IOException error) {
                if (!cacheError(error)) throw error;
                return bypass();
            }
        }
        private DataSource observe(DataSource network) {
            return new DataSource() {
                @Override public long open(DataSpec request) throws IOException {
                    long length = network.open(request);
                    upstreamOpens++;
                    String etag = "";
                    for (Map.Entry<String, List<String>> header : network.getResponseHeaders().entrySet()) {
                        if ("etag".equalsIgnoreCase(header.getKey()) && !header.getValue().isEmpty())
                            etag = header.getValue().get(0);
                    }
                    String previous = cache.getContentMetadata(key).get(VALIDATOR, "");
                    boolean strong = !etag.isEmpty() && !etag.startsWith("W/");
                    if (!strong || (hadSpans && previous.isEmpty())) validated = false;
                    if (!previous.isEmpty() && !previous.equals(etag)) changedResource = true;
                    if (strong && !changedResource) {
                        try { cache.applyContentMetadataMutations(key,
                                new ContentMetadataMutations().set(VALIDATOR, etag)); }
                        catch (IOException ignored) { validated = false; }
                    }
                    return length;
                }
                @Override public int read(byte[] b, int o, int n) throws IOException { return network.read(b,o,n); }
                @Override public void close() throws IOException { network.close(); }
                @Override public Uri getUri() { return network.getUri(); }
                @Override public Map<String,List<String>> getResponseHeaders() { return network.getResponseHeaders(); }
                @Override public void addTransferListener(TransferListener listener) { network.addTransferListener(listener); }
            };
        }
        private boolean cacheError(Throwable error) {
            if (!leased) return false;
            while (error != null) {
                if (error instanceof Cache.CacheException ||
                        error instanceof androidx.media3.datasource.FileDataSource.FileDataSourceException ||
                        error instanceof androidx.media3.datasource.cache.CacheDataSink.CacheDataSinkException)
                    return true;
                error = error.getCause();
            }
            return false;
        }
        private long bypass() throws IOException {
            try { closeDelegate(); } catch (IOException ignored) { }
            delegate = listen(upstream.createDataSource());
            return delegate.open(spec.subrange(consumed));
        }
        @Override public int read(byte[] buffer, int offset, int length) throws IOException {
            if (length == 0) return 0;
            if (spec.length != C.LENGTH_UNSET && consumed >= spec.length) return C.RESULT_END_OF_INPUT;
            int read;
            try { read = delegate.read(buffer, offset, length); }
            catch (IOException error) {
                if (!cacheError(error)) throw error;
                bypass();
                read = delegate.read(buffer, offset, length);
            }
            if (read != C.RESULT_END_OF_INPUT) consumed += read;
            else reachedEnd = true;
            return read;
        }
        @Override public Uri getUri() { return delegate == null ? null : delegate.getUri(); }
        @Override public Map<String, List<String>> getResponseHeaders() {
            return delegate == null ? Collections.emptyMap() : delegate.getResponseHeaders();
        }
        private void closeDelegate() throws IOException {
            try { if (delegate != null) delegate.close(); }
            finally {
                delegate = null;
                if (leased) {
                    leased = false;
                    // Cache maintenance cannot turn a successful network read into
                    // a playback failure (e.g. full disk while flushing a span).
                    boolean representationKnown = (!hadSpans && upstreamOpens == 1)
                            || (upstreamOpens > 0 && validated) || (upstreamOpens == 0
                            && cache.getContentMetadata(key).get(COMPLETE_OBSERVED, 0L) == 1L);
                    release(key, !changedResource && representationKnown && spec.position == 0
                            && spec.length == C.LENGTH_UNSET
                            && (reachedEnd || (openedLength > 0 && consumed == openedLength)), changedResource);
                }
            }
        }
        @Override public void close() throws IOException {
            boolean wasCached = leased;
            try { closeDelegate(); }
            catch (IOException error) { if (!wasCached) throw error; }
        }
    }

    /** Same span LRU policy as Media3, with a live quota to avoid reopening locks. */
    static final class MutableLruEvictor implements CacheEvictor {
        private final TreeSet<CacheSpan> spans = new TreeSet<>((a, b) -> {
            int order = Long.compare(a.lastTouchTimestamp, b.lastTouchTimestamp);
            return order == 0 ? a.compareTo(b) : order;
        });
        private long bytes;
        private long maxBytes;
        final Set<String> pinned = new HashSet<>();
        final Set<String> writers = new HashSet<>();
        private final Map<String, Long> pending = new HashMap<>();
        synchronized long pendingBytes() { long sum = 0; for (long value : pending.values()) sum += value; return sum; }
        // This monitor protects only byte counters and reservations. Never perform
        // cache/disk operations while holding it (cache callbacks enter this monitor).
        synchronized boolean reserve(String key, long incoming) {
            if (incoming < 0 || incoming > maxBytes - bytes - pendingBytes()) return false;
            pending.merge(key, incoming, Long::sum);
            return true;
        }
        synchronized void releaseReservation(String key) { pending.remove(key); }
        private synchronized List<CacheSpan> snapshot() { return new ArrayList<>(spans); }
        private synchronized boolean fits(long incoming) {
            return bytes + pendingBytes() + incoming <= maxBytes;
        }
        void pruneIdle(Cache cache, long now, long cap) {
            long idle = 0;
            for (CacheSpan span : snapshot()) {
                if (pinned.contains(span.key)) continue;
                if (now - span.lastTouchTimestamp >= 24L * 60 * 60 * 1000) cache.removeSpan(span);
                else idle += span.length;
            }
            for (CacheSpan span : snapshot()) {
                if (idle <= cap) break;
                if (!pinned.contains(span.key)) { cache.removeSpan(span); idle -= span.length; }
            }
        }
        MutableLruEvictor(long maxBytes) { this.maxBytes = maxBytes; }
        void setMaxBytes(Cache cache, long value) {
            synchronized (this) { maxBytes = value; }
            evict(cache, 0);
        }
        private void evict(Cache cache, long incoming) {
            for (CacheSpan span : snapshot()) {
                if (fits(incoming)) break;
                if (!pinned.contains(span.key)) cache.removeSpan(span);
            }
        }
        @Override public boolean requiresCacheSpanTouches() { return true; }
        @Override public void onCacheInitialized() { }
        @Override public void onStartFile(Cache cache, String key, long position, long length) {
            // Actual writes reserve bytes; declared fragment length is not an allocation.
        }
        @Override public void onSpanAdded(Cache cache, CacheSpan span) {
            synchronized (this) {
                pending.computeIfPresent(span.key, (key, value) -> Math.max(0, value - span.length));
                spans.add(span); bytes += span.length;
            }
            evict(cache, 0);
        }
        @Override public synchronized void onSpanRemoved(Cache cache, CacheSpan span) {
            spans.remove(span); bytes -= span.length;
        }
        @Override public synchronized void onSpanTouched(Cache cache, CacheSpan oldSpan, CacheSpan newSpan) {
            spans.remove(oldSpan); spans.add(newSpan);
        }
    }
}
