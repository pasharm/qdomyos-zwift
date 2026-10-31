package org.cagnulen.qdomyoszwift;

import android.app.ActivityManager;
import android.app.DownloadManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.util.Log;

import androidx.core.content.FileProvider;

import java.io.File;

// personal: the newer beta build (UiBetaUpdate.qml). The system download manager fetches the APK into
// the files of the app (no storage permission), its id is kept, so a download that ends while QZ is
// closed is found at the next launch. The APK goes to the installer through a FileProvider.
public class BetaUpdate {
    private static final String TAG = "QZ:BetaUpdate";
    private static final String PREFS = "qz_beta_update";
    private static final String AUTHORITY = "org.cagnulen.qdomyoszwift.betaupdate";
    private static final String APK_TYPE = "application/vnd.android.package-archive";
    private static final String CHANNEL = "qz_beta_update";
    private static final int NOTIFICATION_ID = 7362;

    private static BroadcastReceiver receiver;

    private static String fileName(int build) {
        return "qz-beta-" + build + ".apk";
    }

    private static File file(Context context, int build) {
        return new File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), fileName(build));
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static DownloadManager manager(Context context) {
        return (DownloadManager) context.getSystemService(Context.DOWNLOAD_SERVICE);
    }

    // The build of a finished download, -1 while it runs, 0 if there is none
    public static int downloadedBuild(Context context) {
        SharedPreferences p = prefs(context);
        long id = p.getLong("id", -1);
        int build = p.getInt("build", 0);
        if (id < 0)
            return 0;
        int status = -1;
        Cursor cursor = manager(context).query(new DownloadManager.Query().setFilterById(id));
        if (cursor != null) {
            if (cursor.moveToFirst())
                status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
            cursor.close();
        }
        if (status == DownloadManager.STATUS_SUCCESSFUL && file(context, build).length() > 0)
            return build;
        if (status == DownloadManager.STATUS_PENDING || status == DownloadManager.STATUS_RUNNING
                || status == DownloadManager.STATUS_PAUSED)
            return -1;
        Log.d(TAG, "download " + id + " of build " + build + " is gone, status " + status);
        forget(context);
        return 0;
    }

    // The download and its file, and the stored id
    private static void forget(Context context) {
        SharedPreferences p = prefs(context);
        long id = p.getLong("id", -1);
        if (id >= 0)
            manager(context).remove(id);
        p.edit().remove("id").remove("build").apply();
    }

    // At launch: the download of this build or of an older one is not needed any more
    public static void cleanup(Context context, int installedBuild) {
        if (prefs(context).getInt("build", 0) <= installedBuild && prefs(context).getLong("id", -1) >= 0) {
            Log.d(TAG, "build " + prefs(context).getInt("build", 0) + " is installed, the download is removed");
            forget(context);
        }
        File[] files = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS).listFiles();
        if (files == null)
            return;
        for (File f : files) {
            String name = f.getName();
            if (!name.startsWith("qz-beta-") || !name.endsWith(".apk"))
                continue;
            try {
                int build = Integer.parseInt(name.substring(8, name.length() - 4));
                if (build <= installedBuild && f.delete())
                    Log.d(TAG, "removed " + name);
            } catch (NumberFormatException e) {
                // not a file of this class
            }
        }
    }

    public static void download(Context context, String url, int build, String downloadTitle,
                                String doneTitle, String doneText) {
        final Context app = context.getApplicationContext();
        forget(app);
        File target = file(app, build);
        if (target.exists())
            target.delete();
        DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url))
                .setTitle(downloadTitle)
                .setMimeType(APK_TYPE)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                .setDestinationInExternalFilesDir(app, Environment.DIRECTORY_DOWNLOADS, fileName(build));
        final long id = manager(app).enqueue(request);
        prefs(app).edit().putLong("id", id).putInt("build", build).apply();
        Log.d(TAG, "download " + id + " of build " + build + " started");

        if (receiver != null) {
            try {
                app.unregisterReceiver(receiver);
            } catch (IllegalArgumentException e) {
                // already unregistered
            }
        }
        final int wanted = build;
        receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context c, Intent intent) {
                if (intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1) != id)
                    return;
                try {
                    app.unregisterReceiver(this);
                } catch (IllegalArgumentException e) {
                    // already unregistered
                }
                receiver = null;
                if (downloadedBuild(app) != wanted) {
                    Log.d(TAG, "download " + id + " did not finish");
                    return;
                }
                // Android 10+ does not start an activity of an app in the background: a notification then
                if (inForeground())
                    install(app);
                else
                    notifyDownloaded(app, doneTitle, doneText);
            }
        };
        IntentFilter filter = new IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE);
        // The download manager is another app: the receiver is exported
        if (Build.VERSION.SDK_INT >= 33)
            app.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED);
        else
            app.registerReceiver(receiver, filter);
    }

    private static boolean inForeground() {
        ActivityManager.RunningAppProcessInfo info = new ActivityManager.RunningAppProcessInfo();
        ActivityManager.getMyMemoryState(info);
        return info.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND;
    }

    private static Intent installIntent(Context context, int build) {
        Uri uri = FileProvider.getUriForFile(context, AUTHORITY, file(context, build));
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setDataAndType(uri, APK_TYPE);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        return intent;
    }

    // Opens the installer of Android for the downloaded build; false if there is none
    public static boolean install(Context context) {
        int build = downloadedBuild(context);
        if (build <= 0)
            return false;
        try {
            context.startActivity(installIntent(context, build));
            Log.d(TAG, "installer opened for build " + build);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "installer not opened: " + e);
            return false;
        }
    }

    private static void notifyDownloaded(Context context, String title, String text) {
        int build = downloadedBuild(context);
        if (build <= 0)
            return;
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(new NotificationChannel(CHANNEL, title, NotificationManager.IMPORTANCE_DEFAULT));
            builder = new Notification.Builder(context, CHANNEL);
        } else {
            builder = new Notification.Builder(context);
        }
        int flags = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        PendingIntent pending = PendingIntent.getActivity(context, NOTIFICATION_ID, installIntent(context, build), flags);
        builder.setSmallIcon(R.drawable.icon)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(pending)
                .setAutoCancel(true);
        nm.notify(NOTIFICATION_ID, builder.build());
        Log.d(TAG, "notification for build " + build);
    }
}
