import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_in_app_messaging/firebase_in_app_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';

// Top-level channel definition for Android notification channel
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'INFO_DISKON_DAN_PROMO', // id
  'INFO_DISKON_DAN_PROMO', // title
  description: 'Channel untuk notifikasi diskon dan promo',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('Handling background message: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Setup local notification plugin for Android foreground alerts
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );

  // Create high importance notification channel on Android
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // In-App Messaging initial setup
  await FirebaseInAppMessaging.instance.setAutomaticDataCollectionEnabled(true);
  await FirebaseInAppMessaging.instance.setMessagesSuppressed(false);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PML 05 & 06 - Firebase Messaging & In-App Messaging',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1976D2),
        ),
        useMaterial3: true,
      ),
      home: const FcmHomeScreen(),
    );
  }
}

class FcmHomeScreen extends StatefulWidget {
  const FcmHomeScreen({super.key});

  @override
  State<FcmHomeScreen> createState() => _FcmHomeScreenState();
}

class _FcmHomeScreenState extends State<FcmHomeScreen> {
  static const String topicName = 'INFO_DISKON_DAN_PROMO';

  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _installationIdController =
      TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _promoIdController = TextEditingController();
  final TextEditingController _promoController = TextEditingController();
  final TextEditingController _promoUntilController = TextEditingController();

  String _subscriptionStatus = 'Menghubungkan ke topik...';
  bool _isSubscribed = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _installationIdController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    _promoIdController.dispose();
    _promoController.dispose();
    _promoUntilController.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    // 1. Request notification permission (khusus Android 13+ / Tiramisu dan iOS)
    NotificationSettings settings =
        await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (mounted) {
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        _showSnackBar('Izin notifikasi diberikan');
      } else {
        _showSnackBar('Izin notifikasi belum diizinkan');
      }
    }

    // 2. Berlangganan topik "INFO_DISKON_DAN_PROMO"
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topicName);
      if (mounted) {
        setState(() {
          _isSubscribed = true;
          _subscriptionStatus = 'Berhasil subscribe ke topik: $topicName';
        });
        _showSnackBar('Berhasil subscribe topik $topicName');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubscribed = false;
          _subscriptionStatus = 'Gagal subscribe ke topik: $e';
        });
        _showSnackBar('Tidak berhasil subscribe');
      }
    }

    // 3. Ambil FCM Token perangkat
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null && mounted) {
        setState(() {
          _tokenController.text = token;
        });
        debugPrint('FCM Token: $token');
      }
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }

    // Listener token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      if (mounted) {
        setState(() {
          _tokenController.text = newToken;
        });
      }
    });

    // 4. Ambil Firebase Installation ID (PML 06 - In-App Messaging)
    try {
      String installationId = await FirebaseInstallations.instance.getId();
      if (mounted) {
        setState(() {
          _installationIdController.text = installationId;
        });
      }
      // Log format persis seperti yang dicari di Android Studio Logcat pada Modul 06 (FIAM.Headless)
      debugPrint(
          'I/FIAM.Headless: Starting InAppMessaging runtime with Installation ID $installationId');
    } catch (e) {
      debugPrint('Error getting installation ID: $e');
    }

    // 5. Cek pesan saat aplikasi dibuka dari keadaan terminated (klik notifikasi)
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _processIncomingMessage(initialMessage, source: 'Terminated Launch');
    }

    // 6. Listener saat notifikasi di-klik ketika aplikasi ada di background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _processIncomingMessage(message, source: 'Background Click');
    });

    // 7. Listener pesan masuk ketika aplikasi sedang di foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _processIncomingMessage(message, source: 'Foreground');

      // Tampilkan notifikasi lokal heads-up
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: '@mipmap/ic_launcher',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      }
    });
  }

  void _processIncomingMessage(RemoteMessage message, {required String source}) {
    if (!mounted) return;

    setState(() {
      // Notification title & body
      if (message.notification != null) {
        _titleController.text = message.notification?.title ?? '';
        _bodyController.text = message.notification?.body ?? '';
      }

      // Data payload (promoId, promo, promoUntil)
      final data = message.data;
      if (data.isNotEmpty) {
        if (data.containsKey('promoId')) {
          _promoIdController.text = data['promoId'] ?? '';
        }
        if (data.containsKey('promo')) {
          _promoController.text = data['promo'] ?? '';
        }
        if (data.containsKey('promoUntil')) {
          _promoUntilController.text = data['promoUntil'] ?? '';
        }

        // Jika title/body dikirim via data payload
        if (_titleController.text.isEmpty && data.containsKey('title')) {
          _titleController.text = data['title'] ?? '';
        }
        if (_bodyController.text.isEmpty && data.containsKey('body')) {
          _bodyController.text = data['body'] ?? '';
        }
      }
    });

    _showSnackBar('Pesan diterima ($source)');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      _showSnackBar('$label berhasil disalin ke clipboard!');
    }
  }

  Future<void> _triggerOnForegroundEvent() async {
    try {
      // Trigger analytics event on_foreground
      await FirebaseAnalytics.instance.logEvent(name: 'on_foreground');
      // Trigger FIAM programmatic trigger
      await FirebaseInAppMessaging.instance.triggerEvent('on_foreground');
      _showSnackBar('Event "on_foreground" berhasil dipicu');
    } catch (e) {
      _showSnackBar('Gagal memicu event: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'INCOMING MESSAGE',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1565C0),
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Topic Status Card
              Card(
                color: _isSubscribed ? Colors.green.shade50 : Colors.orange.shade50,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: _isSubscribed
                        ? Colors.green.shade300
                        : Colors.orange.shade300,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(
                        _isSubscribed
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        color: _isSubscribed ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _subscriptionStatus,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _isSubscribed
                                ? Colors.green.shade900
                                : Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Token / Application ID
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Token / Application ID (FCM)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20, color: Color(0xFF1565C0)),
                    tooltip: 'Salin Token FCM',
                    onPressed: () => _copyToClipboard(
                      _tokenController.text,
                      'FCM Token',
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _tokenController,
                readOnly: true,
                maxLines: 2,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Memuat FCM Token...',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Installation ID (PML 06 - In-App Messaging)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E5F5), // Light purple
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCE93D8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.campaign,
                                color: Color(0xFF7B1FA2), size: 20),
                            SizedBox(width: 6),
                            Text(
                              'Installation ID (PML 06)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF7B1FA2),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.copy,
                              size: 18, color: Color(0xFF7B1FA2)),
                          tooltip: 'Salin Installation ID',
                          onPressed: () => _copyToClipboard(
                            _installationIdController.text,
                            'Installation ID',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _installationIdController,
                      readOnly: true,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Memuat Installation ID...',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide:
                              const BorderSide(color: Color(0xFFCE93D8)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide:
                              const BorderSide(color: Color(0xFFCE93D8)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Gunakan ID ini untuk "Test on device" pada In-App Messaging di Firebase Console.',
                      style: TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Section: Notification
              const Text(
                'Notification',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1565C0),
                ),
              ),
              const Divider(color: Color(0xFF90CAF9), thickness: 1.5),

              const SizedBox(height: 6),
              const Text(
                'Title',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _titleController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Title',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Text(
                'Body',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _bodyController,
                readOnly: true,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Body',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Section: Data
              const Text(
                'Data',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1565C0),
                ),
              ),
              const Divider(color: Color(0xFF90CAF9), thickness: 1.5),

              const SizedBox(height: 6),
              const Text(
                'Promo Id',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _promoIdController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Promo Id',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Text(
                'Promo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _promoController,
                readOnly: true,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Promo description',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Text(
                'Promo valid until',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _promoUntilController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Promo valid until',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Action buttons (Reset / Refresh / Trigger Event)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _titleController.clear();
                          _bodyController.clear();
                          _promoIdController.clear();
                          _promoController.clear();
                          _promoUntilController.clear();
                        });
                      },
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear Form'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _initializeServices(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7B1FA2),
                    side: const BorderSide(color: Color(0xFF7B1FA2)),
                  ),
                  onPressed: _triggerOnForegroundEvent,
                  icon: const Icon(Icons.touch_app),
                  label: const Text('Trigger Event "on_foreground"'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
