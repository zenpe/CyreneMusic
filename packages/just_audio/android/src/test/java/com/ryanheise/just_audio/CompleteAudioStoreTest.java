package com.ryanheise.just_audio;

import static org.junit.Assert.*;
import java.io.*;
import java.nio.file.Files;
import java.util.*;
import org.json.JSONObject;
import org.junit.*;
import org.junit.rules.TemporaryFolder;

public class CompleteAudioStoreTest {
    @Rule public TemporaryFolder temporary = new TemporaryFolder();
    private CompleteAudioStore store;
    private File root;
    private Map<String, String> identity;

    @Before public void setup() throws Exception {
        root = temporary.newFolder(); store = new CompleteAudioStore(root);
        identity = new HashMap<>(Map.of("source", "qq", "songId", "AbC", "quality", "standard",
                "owner", "public", "origin", "script-a"));
    }
    private boolean publish(long epoch) throws Exception {
        File staged = store.temporary(); Files.write(staged.toPath(), new byte[]{1,2,3,4});
        try { return store.publish(staged, identity, "checksum", new JSONObject().put("mime", "audio/mpeg"), epoch); }
        finally { staged.delete(); }
    }
    @Test public void survivesRestartWithoutUpstreamUrl() throws Exception {
        assertTrue(publish(store.epoch()));
        store = new CompleteAudioStore(root);
        Map<String,Object> result = store.lookup(identity);
        assertNotNull(result); assertFalse(result.containsKey("url"));
        assertFalse((Boolean)result.get("qualityVerified"));
        assertEquals(4L, ((Number)result.get("fileSize")).longValue());
    }
    @Test public void identitiesIsolateQualityServerAndSource() throws Exception {
        publish(store.epoch());
        for (String key : List.of("quality", "owner", "source", "songId")) {
            Map<String,String> changed = new HashMap<>(identity); changed.put(key, "other");
            assertNull(store.lookup(changed));
        }
        Map<String,String> otherResolver = new HashMap<>(identity);
        otherResolver.put("origin", "other-script");
        assertEquals(store.lookup(identity).get("path"), store.lookup(otherResolver).get("path"));
    }
    @Test public void failedRefreshPreservesOldFileAndSuccessfulReplacementRetainsReaders() throws Exception {
        publish(store.epoch());
        String oldPath = (String)store.lookup(identity).get("path");
        store.retainPath(oldPath);
        long stale = store.epoch();
        store.invalidateJobs();
        assertFalse(publish(stale));
        assertEquals(oldPath, store.lookup(identity).get("path"));
        File staged = store.temporary();
        Files.write(staged.toPath(), new byte[]{5,6,7,8});
        assertTrue(store.publish(staged, identity, "new-checksum", new JSONObject().put("mime", "audio/mpeg"), store.epoch()));
        assertNotEquals(oldPath, store.lookup(identity).get("path"));
        assertTrue(new File(oldPath).exists());
        assertEquals(1, store.identities().size());
        store.releasePath(oldPath);
        assertFalse(new File(oldPath).exists());
        assertNotNull(new CompleteAudioStore(root).lookup(identity));
    }

    @Test public void refreshReservationDoesNotEvictPreviousGoodObject() throws Exception {
        publish(store.epoch());
        store.trim(0, Set.of(CompleteAudioStore.identity(identity)));
        assertNotNull(store.lookup(identity));
        store.trim(0);
        assertNull(store.lookup(identity));
    }

    @Test public void restartKeepsNewestCommitAfterInterruptedReplacement() throws Exception {
        publish(store.epoch());
        Map<String,Object> old = store.lookup(identity);
        File oldAudio = new File((String)old.get("path"));
        File oldRecord = new File(root, old.get("key") + ".json");
        byte[] record = Files.readAllBytes(oldRecord.toPath());
        long modified = oldAudio.lastModified();
        File staged = store.temporary(); Files.write(staged.toPath(), new byte[]{9,8,7,6});
        assertTrue(store.publish(staged, identity, "replacement", new JSONObject().put("mime", "audio/mpeg"), store.epoch()));
        String expected = (String)store.lookup(identity).get("path");
        // Simulate process death before the previous record was retired.
        Files.write(oldAudio.toPath(), new byte[]{1,2,3,4});
        oldAudio.setLastModified(modified);
        Files.write(oldRecord.toPath(), record);
        store = new CompleteAudioStore(root);
        assertEquals(expected, store.lookup(identity).get("path"));
        assertEquals(1, store.identities().size());
        assertFalse(oldAudio.exists());
    }
    @Test public void clearHidesImmediatelyButKeepsAllReadersUntilRelease() throws Exception {
        publish(store.epoch()); String path = (String)store.lookup(identity).get("path");
        assertTrue(store.retainPath(path)); assertTrue(store.retainPath(path));
        store.remove("qq", "AbC", null);
        assertNull(store.lookup(identity)); assertTrue(new File(path).exists());
        store.releasePath(path); assertTrue(new File(path).exists());
        store.releasePath(path); assertFalse(new File(path).exists());
    }
    @Test public void processDeathCannotResurrectDeletedReader() throws Exception {
        publish(store.epoch()); String path = (String)store.lookup(identity).get("path");
        store.retainPath(path); store.remove(null,null,null);
        store = new CompleteAudioStore(root);
        assertNull(store.lookup(identity)); assertFalse(new File(path).exists());
    }
    @Test public void clearCancelsLateCopyCommit() throws Exception {
        long epoch = store.epoch(); store.remove(null,null,null);
        assertFalse(publish(epoch)); assertNull(store.lookup(identity));
    }
    @Test public void quotaDoesNotDeletePreparedOrPlayingFile() throws Exception {
        publish(store.epoch()); String path = (String)store.lookup(identity).get("path");
        store.retainPath(path); store.trim(0); assertNotNull(store.lookup(identity));
        store.releasePath(path); store.trim(0); assertNull(store.lookup(identity));
    }
    @Test public void truncatedAudioIsInvalidatedInsteadOfReturned() throws Exception {
        publish(store.epoch()); String path = (String)store.lookup(identity).get("path");
        Files.write(new File(path).toPath(), new byte[]{1});
        assertNull(store.lookup(identity));
    }
    @Test public void abandonedCopyIsRemovedOnRestart() throws Exception {
        File staged = store.temporary(); Files.write(staged.toPath(), new byte[]{1});
        store = new CompleteAudioStore(root); assertFalse(staged.exists());
    }
}
