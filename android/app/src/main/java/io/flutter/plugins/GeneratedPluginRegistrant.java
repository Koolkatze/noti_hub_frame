package io.flutter.plugins;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import io.flutter.Log;

import io.flutter.embedding.engine.FlutterEngine;

/**
 * Generated file. Do not edit.
 * This file is generated by the Flutter tool based on the
 * plugins that support the Android platform.
 */
@Keep
public final class GeneratedPluginRegistrant {
  private static final String TAG = "GeneratedPluginRegistrant";
  public static void registerWith(@NonNull FlutterEngine flutterEngine) {
    try {
      flutterEngine.getPlugins().add(new com.lib.flutter_blue_plus.FlutterBluePlusPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin flutter_blue_plus, com.lib.flutter_blue_plus.FlutterBluePlusPlugin", e);
    }
    try {
      flutterEngine.getPlugins().add(new im.zoe.labs.flutter_notification_listener.FlutterNotificationListenerPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin flutter_notification_listener, im.zoe.labs.flutter_notification_listener.FlutterNotificationListenerPlugin", e);
    }
  }
}
