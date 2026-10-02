package com.msixv.com.m6player;

import android.media.audiofx.Equalizer;
import androidx.annotation.NonNull;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * The equalizer, attached to the audio player's session by this app instead of by
 * just_audio's own audio pipeline.
 *
 * just_audio asks for the equalizer the moment it starts a player, but with
 * media3 1.9 the player's audio session id arrives a few milliseconds later, so on
 * a cold phone the request lost the race and playback failed with a
 * NullPointerException until the app was restarted. Here the session id is handed
 * over by Dart whenever it changes ("attach"), the chosen on/off state and band
 * gains are remembered and reapplied to each new session, and any failure only
 * affects the equalizer, never playback.
 */
public class EqualizerBridge implements MethodChannel.MethodCallHandler {
    private Equalizer equalizer;
    private boolean enabled = false;
    private final Map<Integer, Double> gains = new HashMap<>(); // dB per band

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "configure": {
                    // The saved settings, sent once at start-up
                    Boolean on = call.argument("enabled");
                    enabled = on != null && on;
                    List<Double> list = call.argument("gains");
                    gains.clear();
                    if (list != null) {
                        for (int i = 0; i < list.size(); i++) gains.put(i, list.get(i));
                    }
                    result.success(null);
                    break;
                }
                case "attach": {
                    Integer sessionId = call.argument("sessionId");
                    release();
                    if (sessionId == null) {
                        result.success(null);
                        break;
                    }
                    try {
                        equalizer = new Equalizer(0, sessionId);
                        equalizer.setEnabled(enabled);
                        for (Map.Entry<Integer, Double> entry : gains.entrySet()) applyGain(entry.getKey(), entry.getValue());
                        result.success(parameters());
                    } catch (Exception e) {
                        // This phone's equalizer isn't available: playback carries on without it
                        release();
                        result.success(null);
                    }
                    break;
                }
                case "setEnabled": {
                    Boolean on = call.argument("enabled");
                    enabled = on != null && on;
                    if (equalizer != null) equalizer.setEnabled(enabled);
                    result.success(null);
                    break;
                }
                case "setGain": {
                    Integer band = call.argument("band");
                    Double gain = call.argument("gain");
                    if (band != null && gain != null) {
                        gains.put(band, gain);
                        applyGain(band, gain);
                    }
                    result.success(null);
                    break;
                }
                case "release":
                    release();
                    result.success(null);
                    break;
                default:
                    result.notImplemented();
            }
        } catch (Exception e) {
            result.error("equalizer", String.valueOf(e.getMessage()), null);
        }
    }

    /** Sets one band's gain (dB), kept inside what the phone's equalizer allows. */
    private void applyGain(int band, double gainDb) {
        if (equalizer == null || band < 0 || band >= equalizer.getNumberOfBands()) return;
        short[] range = equalizer.getBandLevelRange(); // millibels
        double millibels = Math.max(range[0], Math.min(range[1], Math.round(gainDb * 100.0)));
        equalizer.setBandLevel((short) band, (short) millibels);
    }

    private Map<String, Object> parameters() {
        short[] range = equalizer.getBandLevelRange();
        List<Map<String, Object>> bands = new ArrayList<>();
        for (short i = 0; i < equalizer.getNumberOfBands(); i++) {
            Map<String, Object> band = new HashMap<>();
            band.put("index", (int) i);
            band.put("hertz", equalizer.getCenterFreq(i) / 1000.0); // the phone reports milliHertz
            band.put("gain", equalizer.getBandLevel(i) / 100.0);
            bands.add(band);
        }
        Map<String, Object> out = new HashMap<>();
        out.put("minDb", range[0] / 100.0);
        out.put("maxDb", range[1] / 100.0);
        out.put("bands", bands);
        return out;
    }

    private void release() {
        if (equalizer != null) {
            try {
                equalizer.release();
            } catch (Exception ignored) {
                // Already gone with its session
            }
            equalizer = null;
        }
    }
}
