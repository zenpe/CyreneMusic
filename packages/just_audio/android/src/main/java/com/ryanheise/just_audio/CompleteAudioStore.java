package com.ryanheise.just_audio;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import org.json.JSONObject;

/** Complete, immutable audio objects. Only this owner publishes/deletes files.
 * Long copies never run under this monitor. Paths and URLs are not identities. */
final class CompleteAudioStore {
    private final File root;
    private final Map<String, JSONObject> entries = new LinkedHashMap<>();
    private final Map<String, Integer> readers = new HashMap<>();
    private final Set<String> deleted = new HashSet<>();
    private volatile long epoch;

    CompleteAudioStore(File root) throws Exception {
        this.root = root;
        if (!root.isDirectory() && !root.mkdirs()) throw new IOException("Cache directory unavailable");
        File[] files = root.listFiles();
        if (files == null) throw new IOException("Cache directory unavailable");
        // Metadata is the commit record. Missing/corrupt records never expose audio.
        for (File file : files) {
            if (!file.getName().matches("[a-f0-9]{64}\\.json")) continue;
            try {
                JSONObject entry = new JSONObject(readText(file));
                String id = file.getName().substring(0, 64);
                File audio = audio(id);
                if (entry.optInt("version") == 1 && audio.isFile()
                        && audio.length() == entry.getLong("fileSize")
                        && audio.lastModified() == entry.getLong("modified")) entries.put(id, entry);
            } catch (Exception ignored) { }
        }
        for (File file : files) {
            String name = file.getName();
            if (name.matches("[a-f0-9]{64}\\.(audio|json|deleted)")
                    && !entries.containsKey(name.substring(0, 64))) file.delete();
            if (name.startsWith("copy-") && name.endsWith(".part")) file.delete();
            if (name.matches("[a-f0-9]{64}\\.json\\.tmp")) file.delete();
        }
        // A crash between publishing the new record and retiring the old one
        // may leave two valid records. The newest commit always wins.
        Map<String, String> latest = new HashMap<>();
        for (String id : new ArrayList<>(entries.keySet())) {
            String logical = entries.get(id).optString("identity");
            String previous = latest.get(logical);
            if (previous == null) latest.put(logical, id);
            else if (entries.get(id).optLong("cachedAt") > entries.get(previous).optLong("cachedAt")) {
                retire(previous); latest.put(logical, id);
            } else retire(id);
        }
    }

    static String identity(Map<String, String> metadata) {
        return hash(new org.json.JSONArray(Arrays.asList(metadata.get("source"),
                metadata.get("songId"), metadata.get("quality"), metadata.get("owner"))).toString());
    }

    static String hash(String text) {
        try { return hex(MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8))); }
        catch (Exception error) { throw new IllegalStateException(error); }
    }

    static String hex(byte[] data) {
        StringBuilder out = new StringBuilder();
        for (byte b : data) out.append(String.format(Locale.ROOT, "%02x", b & 255));
        return out.toString();
    }

    long epoch() { return epoch; }
    synchronized void invalidateJobs() { epoch++; }
    File temporary() throws IOException { return File.createTempFile("copy-", ".part", root); }
    private File audio(String id) { return new File(root, id + ".audio"); }

    synchronized Map<String, Object> lookup(Map<String, String> identity) throws Exception {
        String wanted = identity(identity);
        for (String id : new ArrayList<>(entries.keySet())) {
            JSONObject entry = entries.get(id);
            if (deleted.contains(id) || !wanted.equals(entry.optString("identity"))) continue;
            File file = audio(id);
            if (!file.isFile() || file.length() != entry.getLong("fileSize")
                    || file.lastModified() != entry.getLong("modified")) { retire(id); continue; }
            long now = System.currentTimeMillis();
            entry.put("lastAccess", now);
            if (now - new File(root, id + ".json").lastModified() > 60000) {
                try { writeRecord(new File(root, id + ".json"), entry); } catch (IOException ignored) { }
            }
            Map<String, Object> result = new HashMap<>();
            for (Iterator<String> keys = entry.keys(); keys.hasNext();) {
                String key = keys.next(); result.put(key, entry.get(key));
            }
            result.put("path", file.getAbsolutePath());
            result.put("key", id);
            return result;
        }
        return null;
    }

    synchronized boolean publish(File temporary, Map<String, String> metadata,
            String checksum, JSONObject format, long expectedEpoch) throws Exception {
        if (epoch != expectedEpoch) return false;
        String logical = identity(metadata);
        String id = hash(logical + ":" + checksum);
        if (deleted.contains(id)) return false;
        if (entries.containsKey(id)) return true;
        long now = System.currentTimeMillis();
        for (JSONObject previous : entries.values()) {
            if (logical.equals(previous.optString("identity"))) now = Math.max(now, previous.optLong("cachedAt") + 1);
        }
        File target = audio(id);
        if (!temporary.renameTo(target)) throw new IOException("Cannot publish cache audio");
        JSONObject entry = new JSONObject(metadata);
        entry.put("version", 1).put("identity", logical).put("checksum", checksum)
                .put("fileSize", target.length()).put("modified", target.lastModified())
                .put("cachedAt", now).put("lastAccess", now).put("format", format.toString())
                .put("contentType", format.getString("mime")).put("qualityVerified", false);
        try {
            writeRecord(new File(root, id + ".json"), entry);
            entries.put(id, entry);
        } catch (Exception error) { target.delete(); throw error; }
        for (String old : new ArrayList<>(entries.keySet())) {
            if (!old.equals(id) && logical.equals(entries.get(old).optString("identity"))) retire(old);
        }
        return true;
    }

    private void retire(String id) throws IOException {
        File record = new File(root, id + ".json");
        File tombstone = new File(root, id + ".deleted");
        // Durable invalidation precedes deletion; a killed process cannot revive it.
        deleted.add(id);
        if (record.exists() && !record.renameTo(tombstone)) throw new IOException("Cannot invalidate cache");
        if (!readers.containsKey(id)) deleteRetired(id);
    }

    private void deleteRetired(String id) {
        File file = audio(id);
        if (file.exists() && !file.delete()) return;
        new File(root, id + ".deleted").delete();
        entries.remove(id);
        deleted.remove(id);
    }

    synchronized void remove(String source, String songId, String quality) throws Exception {
        remove(source, songId, quality, null);
    }

    synchronized void remove(String source, String songId, String quality, String owner) throws Exception {
        epoch++;
        for (String id : new ArrayList<>(entries.keySet())) {
            JSONObject entry = entries.get(id);
            if (source == null || (source.equals(entry.optString("source"))
                    && songId.equals(entry.optString("songId"))
                    && (quality == null || quality.equals(entry.optString("quality")))
                    && (owner == null || owner.equals(entry.optString("owner"))))) retire(id);
        }
    }

    synchronized void trim(long maxBytes) throws Exception {
        trim(maxBytes, Collections.emptySet());
    }

    synchronized void trim(long maxBytes, Set<String> protectedIdentities) throws Exception {
        List<String> ids = new ArrayList<>(entries.keySet());
        ids.sort(Comparator.comparingLong(id -> entries.get(id).optLong("lastAccess")));
        for (String id : ids) {
            if (bytes() <= maxBytes) break;
            if (!readers.containsKey(id) && !protectedIdentities.contains(entries.get(id).optString("identity"))) retire(id);
        }
    }

    synchronized long bytes() {
        long total = 0;
        for (JSONObject entry : entries.values()) total += entry.optLong("fileSize");
        return total;
    }

    synchronized List<Map<String, String>> identities() {
        List<Map<String, String>> out = new ArrayList<>();
        for (Map.Entry<String, JSONObject> item : entries.entrySet()) {
            if (deleted.contains(item.getKey())) continue;
            Map<String, String> meta = new HashMap<>();
            for (String key : new String[]{"source", "songId", "quality", "owner", "origin"})
                meta.put(key, item.getValue().optString(key));
            out.add(meta);
        }
        return out;
    }

    synchronized boolean retainPath(String path) {
        String id = idForPath(path);
        if (id == null || !entries.containsKey(id)) return false;
        readers.put(id, readers.getOrDefault(id, 0) + 1);
        return true;
    }

    synchronized void releasePath(String path) {
        String id = idForPath(path);
        if (id == null) return;
        int count = readers.getOrDefault(id, 0) - 1;
        if (count > 0) readers.put(id, count);
        else { readers.remove(id); if (deleted.contains(id)) deleteRetired(id); }
    }

    private String idForPath(String path) {
        File file = new File(path);
        if (!root.equals(file.getParentFile()) || !file.getName().matches("[a-f0-9]{64}\\.audio")) return null;
        return file.getName().substring(0, 64);
    }

    private static String readText(File file) throws IOException {
        if (file.length() > 65536) throw new IOException("Invalid cache record");
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (InputStream in = new FileInputStream(file)) {
            byte[] buffer = new byte[4096]; int n;
            while ((n = in.read(buffer)) != -1) bytes.write(buffer, 0, n);
        }
        return bytes.toString("UTF-8");
    }

    private static void writeRecord(File file, JSONObject data) throws IOException {
        File staged = new File(file.getPath() + ".tmp");
        try {
            try (FileOutputStream out = new FileOutputStream(staged)) {
                out.write(data.toString().getBytes(StandardCharsets.UTF_8)); out.getFD().sync();
            }
            if (!staged.renameTo(file)) throw new IOException("Cannot publish cache record");
        } finally { staged.delete(); }
    }
}
