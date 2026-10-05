import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class RoomNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'innerwave_room_chat',
    'Listening room chat',
    description: 'Messages and song suggestions from InnerWave listening rooms',
    importance: Importance.high,
  );

  static Future<void> initialize() async {
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(_channel);
  }

  static Future<void> requestPermission() async {
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> show({required String sender, required String body, required String messageId}) async {
    await _plugin.show(
      messageId.hashCode & 0x7fffffff,
      sender,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails('innerwave_room_chat', 'Listening room chat', channelDescription: 'Messages and song suggestions from InnerWave listening rooms', importance: Importance.high, priority: Priority.high, icon: '@mipmap/ic_launcher'),
        iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
      ),
      payload: 'listening-room',
    );
  }
}
