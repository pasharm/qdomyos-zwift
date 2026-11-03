package org.cagnulen.qdomyoszwift;

import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.OpenableColumns;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import org.cagnulen.qdomyoszwift.QLog;

public class ContentHelper {

    public static String getFileName(Context context, Uri uri) {
        if (uri == null) {
            return null;
        }

        String result = null;
        String scheme = uri.getScheme();
        if ("content".equals(scheme)) {
            QLog.d("ContentHelper", "content");
            Cursor cursor = null;
            try {
                cursor = context.getContentResolver().query(uri, new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null);
                QLog.d("ContentHelper", "cursor " + cursor);
                if (cursor != null && cursor.moveToFirst()) {
                    int nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                    if (nameIndex >= 0) {
                        result = cursor.getString(nameIndex);
                        QLog.d("ContentHelper", "result " + result);
                    }
                }
            } catch (Exception e) {
                QLog.d("ContentHelper", "getFileName query failed " + e);
            } finally {
                if (cursor != null) {
                    cursor.close();
                }
            }
        }
        if ((result == null || result.isEmpty()) && uri.getLastPathSegment() != null) {
            result = uri.getLastPathSegment();
        }
        return result;
    }

    // Size in bytes reported by the provider, or -1 when it is unknown.
    public static long getFileSize(Context context, Uri uri) {
        Cursor cursor = null;
        try {
            cursor = context.getContentResolver().query(uri, new String[] {OpenableColumns.SIZE}, null, null, null);
            if (cursor != null && cursor.moveToFirst() && !cursor.isNull(0)) {
                return cursor.getLong(0);
            }
        } catch (Exception e) {
            QLog.d("ContentHelper", "getFileSize query failed " + e);
        } finally {
            if (cursor != null) {
                cursor.close();
            }
        }
        return -1;
    }

    public static boolean copyContentToFile(Context context, Uri uri, String destinationPath) {
        if (context == null || uri == null || destinationPath == null || destinationPath.isEmpty()) {
            return false;
        }

        InputStream inputStream = null;
        FileOutputStream outputStream = null;
        try {
            inputStream = context.getContentResolver().openInputStream(uri);
            if (inputStream == null) {
                QLog.d("ContentHelper", "copyContentToFile null input stream for " + uri);
                return false;
            }

            outputStream = new FileOutputStream(destinationPath, false);
            byte[] buffer = new byte[8192];
            int read;
            while ((read = inputStream.read(buffer)) != -1) {
                outputStream.write(buffer, 0, read);
            }
            outputStream.flush();
            return true;
        } catch (Exception e) {
            QLog.d("ContentHelper", "copyContentToFile failed " + e);
            return false;
        } finally {
            try {
                if (inputStream != null) {
                    inputStream.close();
                }
            } catch (Exception ignored) {
            }
            try {
                if (outputStream != null) {
                    outputStream.close();
                }
            } catch (Exception ignored) {
            }
        }
    }

    public static String importContentToAppDir(Context context, Uri uri, String destinationDirPath) {
        if (context == null || uri == null || destinationDirPath == null || destinationDirPath.isEmpty()) {
            return "";
        }

        String fileName = sanitizeFileName(getFileName(context, uri));
        if (fileName.isEmpty()) {
            fileName = "imported_file";
        }

        File destinationDir = new File(destinationDirPath);
        if (!destinationDir.exists() && !destinationDir.mkdirs()) {
            QLog.d("ContentHelper", "importContentToAppDir could not create " + destinationDirPath);
            return "";
        }

        File destinationFile = new File(destinationDir, fileName);
        if (destinationFile.exists() && !destinationFile.delete()) {
            QLog.d("ContentHelper", "importContentToAppDir could not replace " + destinationFile.getAbsolutePath());
            return "";
        }

        if (!copyContentToFile(context, uri, destinationFile.getAbsolutePath())) {
            if (destinationFile.exists()) {
                destinationFile.delete();
            }
            return "";
        }

        return destinationFile.getAbsolutePath();
    }

    // Copies a picked file into destinationDirPath without replacing anything there: a file with
    // the same name and size is taken as already imported, otherwise a free name gets a "_N"
    // suffix. A name taken by a file this install cannot see (left by an uninstalled copy of the
    // app) fails to open for writing, so the next suffix is tried as well.
    public static String importContentToAppDirKeepExisting(Context context, Uri uri, String fileName, long size,
                                                           String destinationDirPath) {
        if (context == null || uri == null || destinationDirPath == null || destinationDirPath.isEmpty()) {
            return "";
        }

        fileName = sanitizeFileName(fileName);
        if (fileName.isEmpty()) {
            fileName = sanitizeFileName(getFileName(context, uri));
        }
        if (fileName.isEmpty()) {
            fileName = "imported_file";
        }

        File destinationDir = new File(destinationDirPath);
        if (!destinationDir.exists() && !destinationDir.mkdirs()) {
            QLog.d("ContentHelper", "importContentToAppDirKeepExisting could not create " + destinationDirPath);
            return "";
        }

        int dot = fileName.lastIndexOf('.');
        String base = dot > 0 ? fileName.substring(0, dot) : fileName;
        String extension = dot > 0 ? fileName.substring(dot) : "";
        for (int attempt = 0; attempt < 100; attempt++) {
            String candidate = attempt == 0 ? fileName : base + "_" + attempt + extension;
            File destinationFile = new File(destinationDir, candidate);
            if (destinationFile.exists()) {
                // a same-size file counts as this workout only if the app can read it: after a
                // reinstall the copies made by the previous install are still listed but unreadable
                if (size >= 0 && destinationFile.length() == size && isReadable(destinationFile)) {
                    return destinationFile.getAbsolutePath();
                }
                continue;
            }
            if (copyContentToFile(context, uri, destinationFile.getAbsolutePath())) {
                // the same workout may already be here under another name (name_1.fit, ...):
                // keep one copy, otherwise every import multiplies them
                File twin = findIdenticalFile(destinationDir, destinationFile);
                if (twin != null) {
                    destinationFile.delete();
                    return twin.getAbsolutePath();
                }
                return destinationFile.getAbsolutePath();
            }
            if (destinationFile.exists()) {
                destinationFile.delete();
            }
        }
        QLog.d("ContentHelper", "importContentToAppDirKeepExisting gave up on " + fileName);
        return "";
    }

    // A readable file of the folder with the same bytes as file, or null.
    private static File findIdenticalFile(File dir, File file) {
        File[] others = dir.listFiles();
        if (others == null) {
            return null;
        }
        for (File other : others) {
            if (other.equals(file) || !other.isFile() || other.length() != file.length()) {
                continue;
            }
            if (sameContent(other, file)) {
                return other;
            }
        }
        return null;
    }

    private static boolean sameContent(File a, File b) {
        java.io.FileInputStream inA = null;
        java.io.FileInputStream inB = null;
        try {
            inA = new java.io.FileInputStream(a);
            inB = new java.io.FileInputStream(b);
            byte[] bufA = new byte[8192];
            byte[] bufB = new byte[8192];
            while (true) {
                int readA = readFully(inA, bufA);
                int readB = readFully(inB, bufB);
                if (readA != readB) {
                    return false;
                }
                if (readA <= 0) {
                    return true;
                }
                for (int i = 0; i < readA; i++) {
                    if (bufA[i] != bufB[i]) {
                        return false;
                    }
                }
            }
        } catch (Exception e) {
            // unreadable (a file of a previous install): not a copy this install can use
            return false;
        } finally {
            try {
                if (inA != null) {
                    inA.close();
                }
            } catch (Exception ignored) {
            }
            try {
                if (inB != null) {
                    inB.close();
                }
            } catch (Exception ignored) {
            }
        }
    }

    private static int readFully(InputStream in, byte[] buffer) throws java.io.IOException {
        int total = 0;
        while (total < buffer.length) {
            int read = in.read(buffer, total, buffer.length - total);
            if (read == -1) {
                break;
            }
            total += read;
        }
        return total;
    }

    private static boolean isReadable(File file) {
        java.io.FileInputStream stream = null;
        try {
            stream = new java.io.FileInputStream(file);
            return stream.read() != -1 || file.length() == 0;
        } catch (Exception e) {
            return false;
        } finally {
            try {
                if (stream != null) {
                    stream.close();
                }
            } catch (Exception ignored) {
            }
        }
    }

    private static String sanitizeFileName(String value) {
        if (value == null) {
            return "";
        }

        return value.replace('\\', '_').replace('/', '_').trim();
    }

    // One import of a folder of workouts (CustomQtActivity.importFitFilesFromTree). After every
    // reinstall Documents/QZ/fit holds one more copy of each workout (the new install cannot read
    // the copies of the previous one), so a folder import meets the same workout many times. Each
    // picked file is hashed once and compared with the files of the destination folder, each of
    // them read at most once per import: a workout that is already there is not copied again, a
    // new one is copied under a free name.
    public static class FolderImport {
        private final File destinationDir;
        // content hash -> local path, for the files of the folder read so far and the ones copied
        private final java.util.HashMap<String, String> pathByHash = new java.util.HashMap<String, String>();
        // files of the folder not read yet, listed on first need
        private java.util.ArrayList<File> unread = null;
        // bytes read by the last sha256 call
        private long hashedLength = 0;
        // local paths already passed on by isNewPath
        private final java.util.HashSet<String> passedOn = new java.util.HashSet<String>();
        // the last importFile copied the picked file, rather than finding its bytes here already
        private boolean copiedLast = false;

        public FolderImport(String destinationDirPath) {
            destinationDir = new File(destinationDirPath == null ? "" : destinationDirPath);
        }

        // true the first time path is asked about: the copies of one workout give the same local
        // path, and the native side needs it once
        public boolean isNewPath(String path) {
            return passedOn.add(path);
        }

        // Local path of the picked file uri, "" when it cannot be imported. fileName and size are
        // the ones reported by the provider, size -1 when unknown.
        public String importFile(Context context, Uri uri, String fileName, long size) {
            copiedLast = false;
            String name = sanitizeFileName(fileName);
            if (name.isEmpty()) {
                return importContentToAppDirKeepExisting(context, uri, fileName, size, destinationDir.getPath());
            }
            // a readable file of the folder with the same name and size is taken without reading
            // (Documents/QZ was picked, and its "fit" subfolder is the destination itself)
            File sameName = new File(destinationDir, name);
            if (size > 0 && sameName.length() == size && isReadable(sameName)) {
                return sameName.getAbsolutePath();
            }
            String hash = sha256(context, uri);
            if (hash == null) {
                QLog.d("ContentHelper", "FolderImport could not read " + uri);
                return "";
            }
            String copy = findCopy(hash, hashedLength);
            if (copy != null) {
                return copy;
            }
            if (!destinationDir.exists() && !destinationDir.mkdirs()) {
                QLog.d("ContentHelper", "FolderImport could not create " + destinationDir);
                return "";
            }
            int dot = name.lastIndexOf('.');
            String base = dot > 0 ? name.substring(0, dot) : name;
            String extension = dot > 0 ? name.substring(dot) : "";
            for (int attempt = 0; attempt < 100; attempt++) {
                File destinationFile = new File(destinationDir, attempt == 0 ? name : base + "_" + attempt + extension);
                // a file of a previous install keeps its name taken
                if (destinationFile.exists()) {
                    continue;
                }
                if (copyChecked(context, uri, destinationFile, hash)) {
                    pathByHash.put(hash, destinationFile.getAbsolutePath());
                    copiedLast = true;
                    return destinationFile.getAbsolutePath();
                }
                destinationFile.delete();
            }
            QLog.d("ContentHelper", "FolderImport gave up on " + name);
            return "";
        }

        // true when fileName in the destination folder is a file this install cannot read (left by
        // a previous one: it keeps its name) and the last importFile, for that file, gave ownCopy,
        // another file that already held the same bytes. A file the import copied from is never
        // such a file, so its bytes stay in place whatever happened to the copy.
        public boolean isOldCopy(String fileName, String ownCopy) {
            if (copiedLast || fileName == null || fileName.isEmpty()) {
                return false;
            }
            File file = new File(destinationDir, fileName);
            return !file.getAbsolutePath().equals(ownCopy) && file.exists() && !isReadable(file);
        }

        // Copies uri to file, on disk before it returns: true only when the bytes written have the
        // hash the picked file had when it was read first.
        private static boolean copyChecked(Context context, Uri uri, File file, String hash) {
            InputStream in = null;
            FileOutputStream out = null;
            try {
                in = context.getContentResolver().openInputStream(uri);
                if (in == null) {
                    return false;
                }
                java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
                out = new FileOutputStream(file, false);
                byte[] buffer = new byte[65536];
                int read;
                while ((read = in.read(buffer)) != -1) {
                    out.write(buffer, 0, read);
                    digest.update(buffer, 0, read);
                }
                out.getFD().sync();
                out.close();
                out = null;
                return hash.equals(hex(digest.digest()));
            } catch (Exception e) {
                QLog.d("ContentHelper", "FolderImport could not copy to " + file + ": " + e);
                return false;
            } finally {
                try {
                    if (in != null) {
                        in.close();
                    }
                } catch (Exception ignored) {
                }
                try {
                    if (out != null) {
                        out.close();
                    }
                } catch (Exception ignored) {
                }
            }
        }

        // A file of the folder with this content, or null. Only files whose size can match are read;
        // a size of 0 is read too: under FUSE passthrough a recently written file can report 0.
        private String findCopy(String hash, long length) {
            String known = pathByHash.get(hash);
            if (known != null) {
                return known;
            }
            if (unread == null) {
                unread = new java.util.ArrayList<File>();
                File[] files = destinationDir.listFiles();
                if (files != null) {
                    for (File file : files) {
                        if (file.isFile()) {
                            unread.add(file);
                        }
                    }
                }
            }
            java.util.Iterator<File> iterator = unread.iterator();
            while (iterator.hasNext()) {
                File file = iterator.next();
                long fileLength = file.length();
                if (fileLength != length && fileLength != 0) {
                    continue;
                }
                iterator.remove();
                // null: not readable, a file of a previous install
                String fileHash;
                try {
                    fileHash = sha256(new java.io.FileInputStream(file));
                } catch (Exception e) {
                    fileHash = null;
                }
                if (fileHash == null) {
                    continue;
                }
                if (!pathByHash.containsKey(fileHash)) {
                    pathByHash.put(fileHash, file.getAbsolutePath());
                }
                if (fileHash.equals(hash)) {
                    return file.getAbsolutePath();
                }
            }
            return null;
        }

        private String sha256(Context context, Uri uri) {
            try {
                return sha256(context.getContentResolver().openInputStream(uri));
            } catch (Exception e) {
                return null;
            }
        }

        // Hash of the content of in, which is closed here; null when it cannot be read. The number
        // of bytes read goes to hashedLength.
        private String sha256(InputStream in) {
            if (in == null) {
                return null;
            }
            try {
                java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
                byte[] buffer = new byte[65536];
                long total = 0;
                int read;
                while ((read = in.read(buffer)) != -1) {
                    digest.update(buffer, 0, read);
                    total += read;
                }
                hashedLength = total;
                return hex(digest.digest());
            } catch (Exception e) {
                return null;
            } finally {
                try {
                    if (in != null) {
                        in.close();
                    }
                } catch (Exception ignored) {
                }
            }
        }

        private static String hex(byte[] bytes) {
            StringBuilder result = new StringBuilder();
            for (byte b : bytes) {
                result.append(Character.forDigit((b >> 4) & 0xf, 16)).append(Character.forDigit(b & 0xf, 16));
            }
            return result.toString();
        }
    }
}
