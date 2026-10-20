package org.cagnulen.qdomyoszwift;

import android.content.Context;
import android.os.Build;
import android.os.Bundle;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.speech.tts.Voice;
import org.cagnulen.qdomyoszwift.QLog;

import java.io.File;
import java.util.ArrayList;
import java.util.Locale;

// Test only (T-246, not for a PR): what the speech engine of the phone does with the spoken
// texts of QZ. Lists the engines and the voices, then writes each text to a WAV file with a
// given language: the English voice that homeform asks for, the voice of the text itself and
// the default voice of the engine. The files land in <dir>, the log lines carry the tag T246.
public class TtsProbe {
    private static final String TAG = "T246";
    private static TextToSpeech tts;
    private static TextToSpeech early;
    private static final ArrayList<String[]> jobs = new ArrayList<>();
    private static String outDir;

    // name of the file, language tag ("" = the default of the engine, untouched), text
    private static void add(String name, String lang, String text) {
        jobs.add(new String[] {name, lang, text});
    }

    public static void run(Context context, String dir, String appText) {
        if (Build.VERSION.SDK_INT < 21) {
            QLog.d(TAG, "probe needs API 21");
            return;
        }
        outDir = dir;
        new File(dir).mkdirs();
        jobs.clear();
        String ru = ", скорость 10.0 километров в час, мощность 150, пульс 120";
        String uk = ", швидкість 10.0 кілометрів на годину, потужність 150, пульс 120";
        String en = ", speed 10.0 kilometers per hour, watt 150, heart rate 120";
        // The default voice first: every setLanguage below stays for the next requests
        add("default-app", "", appText);
        add("default-ru", "", ru);
        add("default-uk", "", uk);
        add("en-app", "en-US", appText);
        add("en-ru", "en-US", ru);
        add("en-uk", "en-US", uk);
        add("en-en", "en-US", en);
        add("en-start", "en-US", "Start pressed");
        add("ru-ru", "ru-RU", ru);
        add("ru-start", "ru-RU", "Start pressed");
        add("uk-uk", "uk-UA", uk);
        add("uk-start", "uk-UA", "Start pressed");

        // The order of homeform: a new engine and setLanguage right away, before the engine
        // is bound. Does the language stay or is the call lost?
        early = new TextToSpeech(context, new TextToSpeech.OnInitListener() {
            @Override
            public void onInit(int status) {
                QLog.d(TAG, "early onInit " + status + " language " + early.getLanguage() + " voice " +
                                (early.getVoice() != null ? early.getVoice().getName() : "null"));
            }
        });
        QLog.d(TAG, "early setLanguage(en-US) before init: " + early.setLanguage(Locale.US));

        tts = new TextToSpeech(context, new TextToSpeech.OnInitListener() {
            @Override
            public void onInit(int status) {
                QLog.d(TAG, "onInit " + status);
                if (status != TextToSpeech.SUCCESS) {
                    return;
                }
                report();
                tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                    @Override
                    public void onStart(String id) {}

                    @Override
                    public void onDone(String id) {
                        File f = new File(outDir, id + ".wav");
                        QLog.d(TAG, "done " + id + " " + f.length() + " bytes");
                        next();
                    }

                    @Override
                    public void onError(String id) {
                        QLog.d(TAG, "error " + id);
                        next();
                    }

                    @Override
                    public void onError(String id, int code) {
                        QLog.d(TAG, "error " + id + " code " + code);
                        next();
                    }
                });
                next();
            }
        });
    }

    private static void report() {
        QLog.d(TAG, "default engine " + tts.getDefaultEngine());
        for (TextToSpeech.EngineInfo e : tts.getEngines()) {
            QLog.d(TAG, "engine " + e.name + " (" + e.label + ")");
        }
        QLog.d(TAG, "language " + tts.getLanguage());
        if (Build.VERSION.SDK_INT >= 21) {
            Voice v = tts.getVoice();
            Voice d = tts.getDefaultVoice();
            QLog.d(TAG, "voice " + (v != null ? v.getName() + " " + v.getLocale() : "null") + ", default voice " +
                            (d != null ? d.getName() + " " + d.getLocale() : "null"));
        }
        if (Build.VERSION.SDK_INT >= 18) {
            QLog.d(TAG, "default language " + tts.getDefaultLanguage());
        }
        String[] tags = {"en-US", "en-GB", "ru-RU", "uk-UA"};
        for (String t : tags) {
            QLog.d(TAG, "isLanguageAvailable " + t + " = " + tts.isLanguageAvailable(Locale.forLanguageTag(t)));
        }
        if (Build.VERSION.SDK_INT >= 21 && tts.getVoices() != null) {
            int n = 0;
            for (Voice v : tts.getVoices()) {
                n++;
                String l = v.getLocale().getLanguage();
                if (l.equals("ru") || l.equals("uk") || (l.equals("en") && v.getLocale().getCountry().equals("US"))) {
                    QLog.d(TAG, "voice " + v.getName() + " " + v.getLocale() + " q" + v.getQuality() + " net " +
                                    v.isNetworkConnectionRequired() + " features " + v.getFeatures());
                }
            }
            QLog.d(TAG, "voices in all: " + n);
        }
    }

    private static void next() {
        if (jobs.isEmpty()) {
            QLog.d(TAG, "probe finished");
            return;
        }
        String[] j = jobs.remove(0);
        if (!j[1].isEmpty()) {
            int r = tts.setLanguage(Locale.forLanguageTag(j[1]));
            Voice v = tts.getVoice();
            QLog.d(TAG, "setLanguage " + j[1] + " = " + r + ", voice " + (v != null ? v.getName() : "null"));
        }
        File f = new File(outDir, j[0] + ".wav");
        int r = tts.synthesizeToFile(j[2], new Bundle(), f, j[0]);
        QLog.d(TAG, "synthesize " + j[0] + " [" + j[2] + "] = " + r);
        if (r != TextToSpeech.SUCCESS) {
            next();
        }
    }
}
