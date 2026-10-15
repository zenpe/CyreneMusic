package com.ryanheise.just_audio;

import android.content.Context;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import androidx.media3.common.C;
import androidx.media3.database.StandaloneDatabaseProvider;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DataSpec;
import androidx.media3.datasource.TransferListener;
import androidx.media3.datasource.cache.Cache;
import androidx.media3.datasource.cache.CacheDataSource;
import androidx.media3.datasource.cache.CacheEvictor;
import androidx.media3.datasource.cache.CacheSpan;
import androidx.media3.datasource.cache.ContentMetadataMutations;
import androidx.media3.datasource.cache.SimpleCache;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.Result;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.locks.ReentrantLock;
import org.json.JSONObject;
import org.json.JSONArray;

/** Process-wide cache. Player disposal/recreation never releases a live store. */
final class StreamCacheManager {
    private static final StreamCacheManager INSTANCE = new StreamCacheManager();
    static StreamCacheManager get() { return INSTANCE; }
    private static final String META = "cyrene.identity.v1";
    private static final String PENDING_REMOVAL = "cyrene.pendingRemoval.v1";
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    // The platform thread only touches this short, memory-only registry lock.
    // It must never share a monitor with cache/database/filesystem operations.
    private final Object registrationLock = new Object();
    private final ReentrantLock stateLock = new ReentrantLock();
    private final Map<String, Map<String, String>> registrations = new LinkedHashMap<>();
    private final Map<String, Integer> readers = new HashMap<>();
    private final Set<String> pendingRemoval = new HashSet<>();
    private volatile SimpleCache cache;
    private volatile boolean enabled;
    private String directory;
    private MutableLruEvictor evictor;

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
                    stateLock.lock();
                    try {
                        synchronized (cache) { evictor.setMaxBytes(cache, bytes); }
                        enabled = nextEnabled;
                    } finally { stateLock.unlock(); }
                    break;
                }
                case "streamCache.stats": value = stats(); break;
                case "streamCache.clear": remove(null, null, null); break;
                case "streamCache.delete": remove(call.argument("source"),
                        call.argument("songId"), call.argument("quality")); break;
                default: main.post(result::notImplemented); return;
                }
                final Object reply = value;
                main.post(() -> result.success(reply));
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
        // Exact URL + representation + identity. Never join different signed URLs.
        TreeMap<String, String> normalized = new TreeMap<>();
        if (headers != null) for (Map.Entry<?, ?> entry : headers.entrySet()) {
            normalized.put(entry.getKey().toString().toLowerCase(Locale.ROOT), entry.getValue().toString());
        }
        TreeMap<String, String> identity = new TreeMap<>(metadata);
        final String key = digest(new JSONArray(Arrays.asList(uri,
                new JSONObject(normalized).toString(), new JSONObject(identity).toString())
                ).toString());
        // Metadata contains no URL or headers; scope need not be persisted in clear.
        Map<String, String> stored = new HashMap<>(metadata);
        stored.remove("scope");
        final String payload = new JSONObject(stored).toString();
        return () -> new StreamDataSource(upstream, key, payload);
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
            Map<String, Object> result = new HashMap<>();
            Map<String, Set<String>> groups = new HashMap<>();
            long bytes = 0;
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
            result.put("totalSize", bytes);
            return result;
        } finally { stateLock.unlock(); }
    }

    private void remove(String source, String songId, String quality) throws Exception {
        stateLock.lock();
        try {
            if (cache == null) return;
            Set<String> keys = new HashSet<>(cache.getKeys());
            keys.addAll(readers.keySet());
            for (String key : keys) {
                JSONObject meta = new JSONObject(cache.getContentMetadata(key).get(META, "{}"));
                if (source != null && (!source.equals(meta.optString("source")) ||
                        !songId.equals(meta.optString("songId")) ||
                        (quality != null && !quality.equals(meta.optString("quality"))))) continue;
                // Preserve the current read/connection. Persist the deletion so
                // even process death before close cannot resurrect these bytes.
                pendingRemoval.add(key);
                cache.applyContentMetadataMutations(key,
                        new ContentMetadataMutations().set(PENDING_REMOVAL, 1L));
                if (!readers.containsKey(key)) {
                    finishRemoval(cache, key);
                    pendingRemoval.remove(key);
                }
            }
        } finally { stateLock.unlock(); }
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
            return true;
        } finally { stateLock.unlock(); }
    }

    private void release(String key) {
        // Media3 close flushes the sink first. Disk deletion then belongs to the
        // management worker, never the platform thread or a new source load.
        worker.execute(() -> {
            stateLock.lock();
            try {
                int count = readers.getOrDefault(key, 1) - 1;
                if (count > 0) readers.put(key, count);
                else {
                    readers.remove(key);
                    if (pendingRemoval.contains(key)) {
                        finishRemoval(cache, key);
                        pendingRemoval.remove(key);
                    }
                }
            } catch (Exception ignored) {
                // Keep the persisted marker and bypass on failure; retry clear or
                // the next process initialization will finish the removal.
            } finally { stateLock.unlock(); }
        });
    }

    private static void finishRemoval(SimpleCache cache, String key) throws IOException {
        cache.removeResource(key);
        cache.applyContentMetadataMutations(key,
                new ContentMetadataMutations().remove(PENDING_REMOVAL));
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

        StreamDataSource(DataSource.Factory upstream, String key, String metadata) {
            this.upstream = upstream; this.key = key; this.metadata = metadata;
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
            spec = dataSpec.buildUpon().setKey(key).build(); consumed = 0;
            try {
                try { leased = acquire(key, metadata); }
                catch (IOException ignored) { leased = false; }
                delegate = listen(leased ? new CacheDataSource.Factory().setCache(cache)
                        .setUpstreamDataSourceFactory(upstream)
                        .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
                        .createDataSource() : upstream.createDataSource());
                return delegate.open(spec);
            } catch (IOException error) {
                if (!cacheError(error)) throw error;
                return bypass();
            }
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
                    release(key);
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
    private static final class MutableLruEvictor implements CacheEvictor {
        private final TreeSet<CacheSpan> spans = new TreeSet<>((a, b) -> {
            int order = Long.compare(a.lastTouchTimestamp, b.lastTouchTimestamp);
            return order == 0 ? a.compareTo(b) : order;
        });
        private long bytes;
        private long maxBytes;
        MutableLruEvictor(long maxBytes) { this.maxBytes = maxBytes; }
        void setMaxBytes(Cache cache, long value) { maxBytes = value; evict(cache, 0); }
        private void evict(Cache cache, long incoming) {
            while (bytes + incoming > maxBytes && !spans.isEmpty()) cache.removeSpan(spans.first());
        }
        @Override public boolean requiresCacheSpanTouches() { return true; }
        @Override public void onCacheInitialized() { }
        @Override public void onStartFile(Cache cache, String key, long position, long length) {
            if (length != C.LENGTH_UNSET) evict(cache, length);
        }
        @Override public void onSpanAdded(Cache cache, CacheSpan span) {
            spans.add(span); bytes += span.length; evict(cache, 0);
        }
        @Override public void onSpanRemoved(Cache cache, CacheSpan span) {
            spans.remove(span); bytes -= span.length;
        }
        @Override public void onSpanTouched(Cache cache, CacheSpan oldSpan, CacheSpan newSpan) {
            onSpanRemoved(cache, oldSpan); onSpanAdded(cache, newSpan);
        }
    }
}
