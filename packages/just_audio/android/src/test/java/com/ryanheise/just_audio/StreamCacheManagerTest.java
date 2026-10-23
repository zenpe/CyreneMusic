package com.ryanheise.just_audio;

import static org.junit.Assert.*;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Map;
import java.util.concurrent.*;
import java.util.concurrent.locks.ReentrantLock;
import org.junit.Test;

public class StreamCacheManagerTest {
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
