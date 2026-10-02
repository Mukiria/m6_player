package com.msixv.com.m6player;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;

/**
 * Lets Android Auto read the cover images the app saves from songs' tags. The
 * car is a different app and can't open the app's private files, so it asks for
 * content://com.msixv.com.m6player.covers/&lt;file name&gt; and gets the file from
 * the app's covers folder (the same folder Dart's getApplicationDocumentsDirectory()
 * points into). Read-only, and only files directly inside that folder.
 */
public class CoverProvider extends ContentProvider {
    @Override
    public boolean onCreate() {
        return true;
    }

    /** The covers folder: "flutter" is where path_provider's documents folder lives on Android. */
    private File coversDir() {
        Context context = getContext();
        return new File(context.getDir("flutter", Context.MODE_PRIVATE), "covers");
    }

    /** The requested file, or null if it isn't a plain file inside the covers folder. */
    private File fileFor(Uri uri) {
        String name = uri.getLastPathSegment();
        if (name == null || name.isEmpty()) return null;
        try {
            File dir = coversDir();
            File file = new File(dir, name);
            // Keep requests inside the folder (no ../ tricks)
            if (!file.getCanonicalPath().startsWith(dir.getCanonicalPath() + File.separator)) return null;
            return file.isFile() ? file : null;
        } catch (IOException e) {
            return null;
        }
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        File file = fileFor(uri);
        if (file == null || !"r".equals(mode)) throw new FileNotFoundException(uri.toString());
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        File file = fileFor(uri);
        if (file == null) return null;
        MatrixCursor cursor = new MatrixCursor(new String[] {OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE});
        cursor.addRow(new Object[] {file.getName(), file.length()});
        return cursor;
    }

    @Override
    public String getType(Uri uri) {
        String name = uri.getLastPathSegment();
        if (name != null && name.toLowerCase().endsWith(".png")) return "image/png";
        return "image/jpeg";
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException("read only");
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("read only");
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("read only");
    }
}
