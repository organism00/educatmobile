import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  Function(Map<String, dynamic>)? onNotificationTap;

  Future<void> initialize() async {
    // Initialize local notifications
    await _initLocalNotifications();

    // Request permissions
    await _requestPermissions();

    // Get and store FCM token
    await _getAndStoreToken();

    // Setup message handlers
    _setupMessageHandlers();
  }

  Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null && onNotificationTap != null) {
      try {
        final data = jsonDecode(response.payload!);
        onNotificationTap!(data);
      } catch (e) {
        print('Error parsing notification payload: $e');
      }
    }
  }

  Future<void> _requestPermissions() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('Notification permission status: ${settings.authorizationStatus}');
  }

  Future<void> _getAndStoreToken() async {
    try {
      _fcmToken = await _firebaseMessaging.getToken();
      print('FCM Token: $_fcmToken');
      // Store token locally for later use
      if (_fcmToken != null) {
        // You can save it to SharedPreferences here
        // final prefs = await SharedPreferences.getInstance();
        // await prefs.setString('fcm_token', _fcmToken!);
      }
    } catch (e) {
      print('Error getting FCM token: $e');
    }
  }

  void _setupMessageHandlers() {
    // Foreground messages
    FirebaseMessaging.onMessage.listen(_showLocalNotification);

    // Background messages (when app is in background)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // When app is opened from a terminated state
    FirebaseMessaging.instance.getInitialMessage().then(_handleInitialMessage);

    // When app is in foreground and opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
  }

  void _showLocalNotification(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null) {
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'educat_channel',
            'Educat Chat Notifications',
            channelDescription: 'Notifications for new messages',
            icon: android?.smallIcon ?? '@mipmap/ic_launcher',
            priority: Priority.high,
            importance: Importance.max,
            autoCancel: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  void _handleInitialMessage(RemoteMessage? message) {
    if (message != null && onNotificationTap != null) {
      onNotificationTap!(message.data);
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    if (onNotificationTap != null) {
      onNotificationTap!(message.data);
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      print('Subscribed to topic: $topic');
    } catch (e) {
      print('Error subscribing to topic $topic: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      print('Unsubscribed from topic: $topic');
    } catch (e) {
      print('Error unsubscribing from topic $topic: $e');
    }
  }

  Future<void> sendTestNotification() async {
    await _localNotifications.show(
      0,
      '📱 Message Notification',
      'You have a new message',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'educat_channel',
          'Educat Chat Notifications',
          channelDescription: 'Notifications for new messages',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  String? get fcmToken => _fcmToken;
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Handling background message: ${message.messageId}");
  print('Message data: ${message.data}');
  print('Message notification: ${message.notification?.title}');
}