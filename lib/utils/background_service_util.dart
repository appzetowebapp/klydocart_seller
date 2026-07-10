import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:webview_master_app/config/app_config.dart';

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  final AudioPlayer audioPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
  
  audioPlayer.setAudioContext(AudioContext(
    android: AudioContextAndroid(
      isSpeakerphoneOn: true,
      stayAwake: true,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.alarm,
      audioFocus: AndroidAudioFocus.gainTransientExclusive,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: {
        AVAudioSessionOptions.duckOthers,
      },
    ),
  ));

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    service.setForegroundNotificationInfo(
      title: "Klydocart Delivery Service Active",
      content: "Waiting for new orders...",
    );
  }
  
  service.on('playOrderRingtone').listen((event) async {
    try {
      if (audioPlayer.state == PlayerState.playing) {
        return; // Prevent duplicate playback and echo
      }
      await audioPlayer.play(AssetSource('audio/iphone-remix-68028.mp3'));
    } catch (e) {
      debugPrint('⚠️ AudioPlayer play error: $e');
    }
  });
  
  service.on('stopOrderRingtone').listen((event) async {
    try {
      await audioPlayer.stop();
    } catch (e) {
      debugPrint('⚠️ AudioPlayer stop error: $e');
    }
  });

  service.on('stopService').listen((event) async {
    try {
      await audioPlayer.stop();
    } catch (_) {}
    service.stopSelf();
  });

  // Location tracking logic (remains same)
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) {
        return;
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        debugPrint(
          '📍 Background Location: ${position.latitude}, ${position.longitude}',
        );

        service.invoke('update', {
          "latitude": position.latitude,
          "longitude": position.longitude,
        });
      } catch (e) {
        debugPrint('❌ Background Location Error: $e');
      }
    }
  });
}

@pragma('vm:entry-point')
class BackgroundServiceUtil {
  static const int notificationId = 888;

  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: AppConfig.silentChannelId,
        initialNotificationTitle: 'Restaurant service active',
        initialNotificationContent: 'Waiting for new orders...',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  static Future<void> start() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
  }

  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke('stopService');
    }
  }

  static Future<bool> isRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }
}
