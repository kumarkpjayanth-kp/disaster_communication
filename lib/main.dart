import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:offline_mesh/government_id_storage.dart';
import 'package:offline_mesh/notification_service.dart';
import 'package:offline_mesh/offline_map_screen.dart';
import 'package:offline_mesh/p2p_service.dart';
import 'package:offline_mesh/sound_modem_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData baseDark = ThemeData.dark();
    const Color pureBlack = Color(0xFF0D0D0D);
    const Color tacticalAccent = Color(0xFFE53935);
    const Color surfaceDark = Color(0xFF1A1A1A);
    const Color cardBorder = Color(0xFF2D2D2D);

    final ColorScheme darkScheme = baseDark.colorScheme.copyWith(
      surface: pureBlack,
      background: pureBlack,
      secondary: tacticalAccent,
      secondaryContainer: tacticalAccent,
      primary: tacticalAccent,
    );

    final TextTheme darkTextTheme = baseDark.textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );

    final ThemeData optimizedDarkTheme = baseDark.copyWith(
      scaffoldBackgroundColor: pureBlack,
      primaryColor: pureBlack,
      colorScheme: darkScheme,
      textTheme: darkTextTheme,
      appBarTheme: const AppBarTheme(
        elevation: 0.0,
        backgroundColor: pureBlack,
        foregroundColor: Colors.white,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: tacticalAccent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: Colors.white70),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        disabledElevation: 0,
        highlightElevation: 0,
        backgroundColor: tacticalAccent,
        foregroundColor: Colors.white,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: baseDark,
      darkTheme: optimizedDarkTheme,
      home: const StartupScreen(),
    );
  }
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

enum _PermissionState { loading, granted, denied }

class _StartupScreenState extends State<StartupScreen> {
  _PermissionState _permissionState = _PermissionState.loading;

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
  }

  Future<void> _checkAndRequestPermissions() async {
    setState(() => _permissionState = _PermissionState.loading);

    // Request all runtime permissions in one place so release APK shows the same prompts as debug.
    final Map<Permission, PermissionStatus> statuses = await <Permission>[
      Permission.location,
      Permission.notification,
      Permission.microphone,
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
    ].request();

    final bool allGranted =
        statuses.values.every((PermissionStatus s) => s.isGranted);

    if (!mounted) return;
    setState(() {
      _permissionState =
          allGranted ? _PermissionState.granted : _PermissionState.denied;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_permissionState) {
      case _PermissionState.loading:
        return Scaffold(
          backgroundColor: const Color(0xFF0D0D0D),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Color(0xFFE53935)),
                const SizedBox(height: 24),
                Text(
                  'Setting up offline mesh…',
                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                ),
              ],
            ),
          ),
        );
      case _PermissionState.granted:
        return const _IdentityGate();
      case _PermissionState.denied:
        return Scaffold(
          backgroundColor: const Color(0xFFB71C1C),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 64, color: Colors.white),
                  const SizedBox(height: 24),
                  const Text(
                    'Permissions required',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Location, microphone (for ultrasound discovery), and Bluetooth are needed to connect to nearby users when the network is down.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _checkAndRequestPermissions,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFB71C1C),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }
}

/// After permissions: ensure government ID is set, then show ChatScreen.
class _IdentityGate extends StatefulWidget {
  const _IdentityGate();

  @override
  State<_IdentityGate> createState() => _IdentityGateState();
}

class _IdentityGateState extends State<_IdentityGate> {
  String? _governmentId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadId();
  }

  Future<void> _loadId() async {
    final id = await getGovernmentId();
    if (!mounted) return;
    setState(() {
      _governmentId = id;
      _loading = false;
    });
  }

  Future<void> _onIdSaved(String id) async {
    await setGovernmentId(id);
    if (!mounted) return;
    setState(() => _governmentId = id);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D0D),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE53935))),
      );
    }
    if (_governmentId == null || _governmentId!.trim().isEmpty) {
      return GovernmentIdScreen(onSaved: _onIdSaved);
    }
    return ChatScreen(governmentId: _governmentId!);
  }
}

/// One-time screen to set government-declared ID.
class GovernmentIdScreen extends StatefulWidget {
  const GovernmentIdScreen({super.key, required this.onSaved});

  final Future<void> Function(String id) onSaved;

  @override
  State<GovernmentIdScreen> createState() => _GovernmentIdScreenState();
}

class _GovernmentIdScreenState extends State<GovernmentIdScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final id = _controller.text.trim();
    if (id.isEmpty) return;
    setState(() => _saving = true);
    await widget.onSaved(id);
    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text('Your identity'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.badge_outlined,
                  size: 56, color: Color(0xFFE53935)),
              const SizedBox(height: 24),
              const Text(
                'Government-declared ID',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your national or government-issued ID. This is used as your identity on the mesh network.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'ID number',
                  hintText: 'e.g. National ID',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.governmentId});

  final String governmentId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final P2PService _p2pService;
  final TextEditingController _messageController = TextEditingController();
  MessageCategory _selectedCategory = MessageCategory.general;

  @override
  void initState() {
    super.initState();
    _p2pService = P2PService(governmentId: widget.governmentId);
    _p2pService.startMesh();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _p2pService.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    await _p2pService.broadcastMessage(text, category: _selectedCategory);
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: ValueListenableBuilder<String>(
          valueListenable: _p2pService.statusNotifier,
          builder: (BuildContext context, String status, Widget? child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.governmentId,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white70, fontSize: 12),
                ),
              ],
            );
          },
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<OfflineMapScreen>(
                          builder: (BuildContext context) => OfflineMapScreen(
                            messages: _p2pService.messagesNotifier.value,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.map_outlined,
                              color: Color(0xFFE53935),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tactical Map',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'View reports by location',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white54),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: DropdownButtonFormField<MessageCategory>(
                        value: _selectedCategory,
                        dropdownColor: const Color(0xFF1A1A1A),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: MessageCategory.general,
                              child: Text('General', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(
                              value: MessageCategory.medical,
                              child: Text('Medical', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(
                              value: MessageCategory.danger,
                              child: Text('Danger', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(
                              value: MessageCategory.resources,
                              child: Text('Resources', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(
                              value: MessageCategory.logistics,
                              child: Text('Logistics', style: TextStyle(fontSize: 13))),
                        ],
                        onChanged: (MessageCategory? value) {
                          if (value != null) {
                            setState(() => _selectedCategory = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Type a message…',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFE53935),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ValueListenableBuilder<List<P2PMessage>>(
                  valueListenable: _p2pService.messagesNotifier,
                  builder: (
                    BuildContext context,
                    List<P2PMessage> messages,
                    Widget? child,
                  ) {
                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 56,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Mesh is on — you’ll see messages from nearby users.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: messages.length,
                      itemBuilder: (BuildContext context, int index) {
                        final msg = messages[index];
                        final isMe = msg.sender == _p2pService.userName;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _categoryColor(msg.category)
                                              .withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          _categoryLabel(msg.category),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: _categoryColor(msg.category),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        msg.sender,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white70,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.white.withOpacity(0.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    msg.text,
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
          Positioned(
            right: 20,
            bottom: 24,
            child: _SosButton(
              onPressed: () async {
                await SoundModemService().broadcastAcousticSOS();
                await _p2pService.broadcastSOSAlert();
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _categoryLabel(MessageCategory c) {
    switch (c) {
      case MessageCategory.medical:
        return 'Medical';
      case MessageCategory.danger:
        return 'Danger';
      case MessageCategory.resources:
        return 'Resources';
      case MessageCategory.logistics:
        return 'Logistics';
      case MessageCategory.general:
      default:
        return 'General';
    }
  }

  static Color _categoryColor(MessageCategory c) {
    switch (c) {
      case MessageCategory.medical:
        return const Color(0xFFE53935);
      case MessageCategory.danger:
        return Colors.orangeAccent;
      case MessageCategory.resources:
        return Colors.lightGreenAccent;
      case MessageCategory.logistics:
        return Colors.cyanAccent;
      case MessageCategory.general:
      default:
        return Colors.blueAccent;
    }
  }
}

/// Circular SOS emergency button.
class _SosButton extends StatelessWidget {
  const _SosButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFE53935),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE53935).withOpacity(0.5),
                blurRadius: 16,
                spreadRadius: 0,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sos_rounded, color: Colors.white, size: 36),
              Text(
                'SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
