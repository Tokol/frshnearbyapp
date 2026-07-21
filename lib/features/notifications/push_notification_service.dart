import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/backend_service.dart';
import 'device_installation_store.dart';

class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _backend = BackendService();
  final _installationStore = DeviceInstallationStore();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  GlobalKey<ScaffoldMessengerState>? _messengerKey;
  String? _registeredToken;

  void initialize(GlobalKey<ScaffoldMessengerState> messengerKey) {
    _messengerKey = messengerKey;
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) {
      if (user != null) unawaited(registerCurrentDevice());
    });
    _tokenSubscription ??= _messaging.onTokenRefresh.listen(
      (token) => unawaited(_registerToken(token)),
    );
    _messageSubscription ??= FirebaseMessaging.onMessage.listen(
      _showForegroundMessage,
    );
  }

  Future<void> registerCurrentDevice() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      const vapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');
      if (kIsWeb && vapidKey.isEmpty) return;
      final token = await _messaging.getToken(
        vapidKey: kIsWeb ? vapidKey : null,
      );
      if (token != null) await _registerToken(token);
    } catch (error) {
      debugPrint('Push registration skipped: $error');
    }
  }

  Future<void> _registerToken(String token) async {
    if (FirebaseAuth.instance.currentUser == null) return;
    await _backend.registerPushInstallation(
      installationId: await _installationStore.id(),
      token: token,
      platform: _platform,
      locale: PlatformDispatcher.instance.locale.languageCode,
    );
    _registeredToken = token;
  }

  Future<void> unregisterCurrentDevice() async {
    try {
      final token = _registeredToken ?? await _messaging.getToken();
      if (token != null && FirebaseAuth.instance.currentUser != null) {
        await _backend.unregisterPushInstallation(token);
      }
      await _messaging.deleteToken();
      _registeredToken = null;
    } catch (error) {
      debugPrint('Push unregistration failed: $error');
    }
  }

  void _showForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ?? 'FRSH update';
    final body = message.notification?.body;
    _messengerKey?.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(body == null || body.isEmpty ? title : '$title\n$body'),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  String get _platform {
    if (kIsWeb) return 'WEB';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'ANDROID',
      TargetPlatform.iOS => 'IOS',
      TargetPlatform.macOS => 'MACOS',
      _ => 'OTHER',
    };
  }
}
