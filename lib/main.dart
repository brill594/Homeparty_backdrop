import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'control_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // macOS Runner config reminder:
  // 1) Add com.apple.security.files.user-selected.read-only=true
  //    in both macos/Runner/DebugProfile.entitlements and
  //    macos/Runner/Release.entitlements for file access.
  // 2) For production persistence, store security-scoped bookmarks
  //    instead of only storing plain file paths.
  await windowManager.ensureInitialized();

  final appState = AppState();
  await appState.initialize();
  final windowReadyCompleter = Completer<void>();

  const options = WindowOptions(
    title: 'HomeParty Backdrop',
    minimumSize: Size(980, 680),
    size: Size(1140, 780),
    center: true,
    backgroundColor: Color(0xFF101010),
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
    if (!windowReadyCompleter.isCompleted) {
      windowReadyCompleter.complete();
    }
  });

  runApp(
    HomepartyApp(appState: appState, windowReady: windowReadyCompleter.future),
  );
}

class HomepartyApp extends StatefulWidget {
  const HomepartyApp({
    super.key,
    required this.appState,
    required this.windowReady,
  });

  final AppState appState;
  final Future<void> windowReady;

  @override
  State<HomepartyApp> createState() => _HomepartyAppState();
}

class _HomepartyAppState extends State<HomepartyApp> {
  final GlobalKey<ControlPageState> _controlPageKey =
      GlobalKey<ControlPageState>();
  static const List<HotKeyModifier> _resetModifiers = <HotKeyModifier>[
    HotKeyModifier.meta,
    HotKeyModifier.shift,
  ];
  static const List<HotKeyModifier> _playNextModifiers = <HotKeyModifier>[
    HotKeyModifier.meta,
  ];

  PlaybackTriggerKey? _registeredPlaybackTriggerKey;
  int _hotkeyRegisterToken = 0;
  bool _windowReady = false;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onAppStateChanged);
    unawaited(_registerHotKeysAfterWindowReady());
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    _hotkeyRegisterToken++;
    unawaited(_unregisterAllHotKeysSafely());
    super.dispose();
  }

  void _onAppStateChanged() {
    if (!_windowReady) {
      return;
    }
    if (_registeredPlaybackTriggerKey != widget.appState.playbackTriggerKey) {
      unawaited(_registerAllHotKeysSafely());
    }
  }

  Future<void> _registerHotKeysAfterWindowReady() async {
    await widget.windowReady;
    if (!mounted) {
      return;
    }
    _windowReady = true;
    await _registerAllHotKeysSafely();
  }

  Future<void> _registerAllHotKeysSafely() async {
    final token = ++_hotkeyRegisterToken;
    final desiredKey = widget.appState.playbackTriggerKey;

    final resetStageHotKey = HotKey(
      key: PhysicalKeyboardKey.keyB,
      modifiers: _resetModifiers,
      scope: HotKeyScope.system,
    );
    final playNextHotKey = HotKey(
      key: desiredKey.physicalKey,
      modifiers: _playNextModifiers,
      scope: HotKeyScope.system,
    );

    try {
      await hotKeyManager.unregisterAll();
      if (!mounted || token != _hotkeyRegisterToken) {
        return;
      }

      await hotKeyManager.register(
        resetStageHotKey,
        keyDownHandler: (_) {
          final result = widget.appState.resetToDefaultBackground();
          if (result == ResetToDefaultResult.defaultNotSet) {
            _controlPageKey.currentState?.showLightweightTip(
              'Default background is not set yet.',
            );
          }
        },
      );
      if (!mounted || token != _hotkeyRegisterToken) {
        return;
      }

      await hotKeyManager.register(
        playNextHotKey,
        keyDownHandler: (_) {
          final result = widget.appState.startAndPlayNext();
          if (result == StartPlaybackResult.queueEmpty) {
            _controlPageKey.currentState?.showLightweightTip('播放列表为空，请先添加节目。');
          }
        },
      );
      if (!mounted || token != _hotkeyRegisterToken) {
        return;
      }

      _registeredPlaybackTriggerKey = desiredKey;
    } catch (e, stack) {
      debugPrint('Hotkey register error: $e');
      debugPrint('$stack');
    }
  }

  Future<void> _unregisterAllHotKeysSafely() async {
    try {
      await hotKeyManager.unregisterAll();
    } catch (e, stack) {
      debugPrint('Hotkey unregister error: $e');
      debugPrint('$stack');
    } finally {
      _registeredPlaybackTriggerKey = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeParty Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFF101010),
        useMaterial3: true,
      ),
      home: ControlPage(key: _controlPageKey, appState: widget.appState),
    );
  }
}
