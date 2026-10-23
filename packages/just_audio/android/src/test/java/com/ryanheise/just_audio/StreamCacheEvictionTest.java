package com.ryanheise.just_audio;

import static org.junit.Assert.*;
import androidx.media3.datasource.cache.Cache;
import androidx.media3.datasource.cache.CacheSpan;
import java.io.File;
import java.lang.reflect.Proxy;
import java.util.*;
import org.junit.Test;
import java.util.concurrent.*;

public class StreamCacheEvictionTest {
    private final StreamCacheManager.MutableLruEvictor evictor =
            new StreamCacheManager.MutableLruEvictor(1000);
    private final Set<String> removed = new HashSet<>();
    private final Cache cache = (Cache)Proxy.newProxyInstance(Cache.class.getClassLoader(),
            new Class<?>[]{Cache.class}, (proxy, method, args) -> {
                if (method.getName().equals("removeSpan")) {
                    CacheSpan span = (CacheSpan)args[0];
                    removed.add(span.key);
                    evictor.onSpanRemoved((Cache)proxy, span);
                }
                return null;
            });
    private CacheSpan add(String key, long size, long touched) {
        CacheSpan span = new CacheSpan(key, 0, size, touched, new File(key));
        evictor.onSpanAdded(cache, span);
        return span;
    }

    @Test public void idleExpiryAndCapNeverEvictActiveFragments() {
        long day = 24L * 60 * 60 * 1000;
        evictor.pinned.add("active");
        add("active", 300, 0);
        add("expired", 100, 0);
        add("old-idle", 200, day);
        add("new-idle", 200, day + 1);
        evictor.pruneIdle(cache, day + 2, 200);
        assertEquals(Set.of("expired", "old-idle"), removed);
    }

    @Test public void pendingWritesCountTowardQuotaAndTouchDoesNotConsumeReservations() {
        CacheSpan active = add("active", 100, 1);
        evictor.pinned.add("active");
        add("idle", 200, 2);
        assertTrue(evictor.reserve("active", 80));
        evictor.onSpanTouched(cache, active, new CacheSpan("active", 0, 100, 3, new File("active")));
        assertEquals(80L, evictor.pendingBytes());
        evictor.setMaxBytes(cache, 350);
        assertTrue(removed.contains("idle"));
        assertFalse(removed.contains("active"));
        evictor.onSpanAdded(cache, new CacheSpan("active", 100, 80, 4, new File("second")));
        assertEquals(0, evictor.pendingBytes());
    }

    @Test public void concurrentReservationsCannotExceedCapacity() throws Exception {
        evictor.setMaxBytes(cache, 100);
        ExecutorService pool = Executors.newFixedThreadPool(4);
        try {
            List<Future<Boolean>> results = new ArrayList<>();
            for (int i = 0; i < 40; i++) {
                String key = "writer-" + i;
                results.add(pool.submit(() -> evictor.reserve(key, 10)));
            }
            int admitted = 0;
            for (Future<Boolean> result : results) if (result.get(1, TimeUnit.SECONDS)) admitted++;
            assertEquals(10, admitted);
            assertEquals(100, evictor.pendingBytes());
        } finally { pool.shutdownNow(); }
    }
}
