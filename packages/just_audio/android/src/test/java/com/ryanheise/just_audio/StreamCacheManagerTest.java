package com.ryanheise.just_audio;

import static org.junit.Assert.*;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.*;
import java.util.concurrent.locks.ReentrantLock;
import org.junit.Test;
import org.junit.Rule;
import org.junit.rules.TemporaryFolder;
import androidx.media3.datasource.DataSink;
import androidx.media3.datasource.DataSpec;
import java.io.ByteArrayOutputStream;

public class StreamCacheManagerTest {
    @Rule public TemporaryFolder temporary = new TemporaryFolder();

    @Test public void intermediateStreamCloseDoesNotCancelRefresh() throws Exception {
        StreamCacheManager manager = new StreamCacheManager();
        CompleteAudioStore store = new CompleteAudioStore(temporary.newFolder());
        Field complete = StreamCacheManager.class.getDeclaredField("complete");
        complete.setAccessible(true); complete.set(manager, store);
        Map<String,String> identity = Map.of("source", "qq", "songId", "one", "quality", "standard", "owner", "public");
        Field targets = StreamCacheManager.class.getDeclaredField("refreshTargets");
        targets.setAccessible(true);
        @SuppressWarnings("unchecked") Set<String> refreshes = (Set<String>)targets.get(manager);
        String logical = CompleteAudioStore.identity(identity);
        refreshes.add(logical);
        Field workerField = StreamCacheManager.class.getDeclaredField("worker");
        workerField.setAccessible(true);
        ExecutorService worker = (ExecutorService)workerField.get(manager);
        try {
            Method release = StreamCacheManager.class.getDeclaredMethod("release", String.class, boolean.class,
                    boolean.class);
            release.setAccessible(true);
            // No disk cache is needed to exercise ownership: even a cache IO
            // failure during stream close must leave the playback refresh alive.
            for (int seek = 0; seek < 3; seek++) {
                release.invoke(manager, "fragment", false, false);
                worker.submit(() -> {}).get(1, TimeUnit.SECONDS);
                assertTrue(refreshes.contains(logical));
            }
            manager.handle(null, new MethodCall("streamCache.cancelRefresh", Map.of("identity", identity)),
                    new MethodChannel.Result() {
                        public void success(Object value) { }
                        public void error(String code, String message, Object details) { }
                        public void notImplemented() { }
                    });
            worker.submit(() -> {}).get(1, TimeUnit.SECONDS);
            assertFalse(refreshes.contains(logical));
        } finally { worker.shutdownNow(); }
    }

    @Test public void ongoingWritesSurviveMaintenanceLockWithoutDroppingBytes() throws Exception {
        StreamCacheManager manager = new StreamCacheManager();
        CompleteAudioStore store = new CompleteAudioStore(temporary.newFolder());
        StreamCacheManager.MutableLruEvictor evictor = new StreamCacheManager.MutableLruEvictor(100);
        for (Map.Entry<String,Object> value : Map.<String,Object>of(
                "enabled", true, "complete", store, "evictor", evictor).entrySet()) {
            Field field = StreamCacheManager.class.getDeclaredField(value.getKey());
            field.setAccessible(true); field.set(manager, value.getValue());
        }
        Class<?> type = Class.forName(StreamCacheManager.class.getName() + "$BudgetedSink");
        var constructor = type.getDeclaredConstructor(StreamCacheManager.class, String.class, long.class);
        constructor.setAccessible(true);
        DataSink sink = (DataSink)constructor.newInstance(manager, "song", store.epoch());
        ByteArrayOutputStream written = new ByteArrayOutputStream();
        int[] closes = {0};
        Field delegate = type.getDeclaredField("sink"); delegate.setAccessible(true);
        delegate.set(sink, new DataSink() {
            @Override public void open(DataSpec spec) { }
            @Override public void write(byte[] data, int offset, int length) { written.write(data, offset, length); }
            @Override public void close() { closes[0]++; }
        });
        whileMaintenanceBlocked(manager, () -> {
            sink.write(new byte[]{1,2,3}, 0, 3);
            sink.write(new byte[]{4,5}, 0, 2);
            return null;
        });
        sink.write(new byte[]{6}, 0, 1);
        assertArrayEquals(new byte[]{1,2,3,4,5,6}, written.toByteArray());
        assertEquals(0, closes[0]);
        assertEquals(6, evictor.pendingBytes());
        sink.close();
        assertEquals(1, closes[0]);
    }
    @Test public void fragmentsKeepQueryParametersAndPrivateOwner() {
        String url = "https://cdn.example/audio?id=one&quality=128k&token=a";
        assertEquals(StreamCacheManager.fragmentKey(url, "public"), StreamCacheManager.fragmentKey(url, null));
        assertNotEquals(StreamCacheManager.fragmentKey(url, "public"), StreamCacheManager.fragmentKey(url.replace("token=a", "token=b"), "public"));
        assertNotEquals(StreamCacheManager.fragmentKey(url, "alice"), StreamCacheManager.fragmentKey(url, "bob"));
    }
    @Test public void registrationNeverWaitsForCacheMaintenance() throws Exception {
        StreamCacheManager manager = StreamCacheManager.get();
        whileMaintenanceBlocked(manager, () -> {
            MethodChannel.Result result = new MethodChannel.Result() {
                @Override public void success(Object value) { }
                @Override public void error(String code, String message, Object details) { fail(code); }
                @Override public void notImplemented() { fail("not implemented"); }
            };
            Map<String, String> identity = Map.of("songId", "test");
            assertTrue(manager.handle(null, new MethodCall("streamCache.register",
                    Map.of("id", "lock-test", "metadata", identity)), result));
            assertEquals(identity, manager.takeRegistration("lock-test"));
            return null;
        });
    }

    @Test public void foregroundCacheAcquireBypassesBusyMaintenance() throws Exception {
        StreamCacheManager manager = StreamCacheManager.get();
        Method acquire = StreamCacheManager.class.getDeclaredMethod("acquire", String.class, String.class);
        acquire.setAccessible(true);
        whileMaintenanceBlocked(manager, () -> {
            assertEquals(false, acquire.invoke(manager, "unused", "{}"));
            return null;
        });
    }

    private void whileMaintenanceBlocked(StreamCacheManager manager, Callable<Void> action) throws Exception {
        Field field = StreamCacheManager.class.getDeclaredField("stateLock");
        field.setAccessible(true);
        ReentrantLock lock = (ReentrantLock)field.get(manager);
        ExecutorService executor = Executors.newSingleThreadExecutor();
        lock.lock();
        try {
            // Represents a stalled filesystem operation on the maintenance worker.
            // Neither registration nor a new foreground open may wait for it.
            executor.submit(action).get(1, TimeUnit.SECONDS);
        } finally {
            lock.unlock();
            executor.shutdownNow();
        }
    }
}
