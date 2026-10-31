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

  // Jika pesan adalah data-only (tanpa payload notification bawaan), tampilkan notifikasi lokal
  if (message.notification == null && message.data.isNotEmpty) {
    final plugin = FlutterLocalNotificationsPlugin();
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await plugin.initialize(settings: initSettings);
    String title = message.data['title'] ??
        (message.data.containsKey('promo') ? 'Promo Diskon' : 'Notifikasi Promo');
    String body = message.data['body'] ??
        message.data['promo'] ??
        'Pesan data baru diterima';
    await plugin.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'INFO_DISKON_DAN_PROMO',
          'INFO_DISKON_DAN_PROMO',
          channelDescription: 'Channel untuk notifikasi diskon dan promo',
          icon: '@mipmap/ic_launcher',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }
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

  // Enable foreground notification presentation options
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

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

    // Minta izin runtime notifikasi Android 13+ secara eksplisit
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

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

      // Ambil judul dan isi notifikasi, baik dari payload notification maupun data
      String title = message.notification?.title ??
          message.data['title'] ??
          (message.data.containsKey('promo') ? 'Promo Diskon' : 'Notifikasi Masuk');
      String body = message.notification?.body ??
          message.data['body'] ??
          message.data['promo'] ??
          'Ada pesan baru yang diterima';

      flutterLocalNotificationsPlugin.show(
        id: message.hashCode,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon: '@mipmap/ic_launcher',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
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

              // Token / Application ID
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Token / Application ID',
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
            ],
          ),
        ),
      ),
    );
  }
}
