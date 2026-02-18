import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _windowReady = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKeyEvent);
    unawaited(_waitForMainWindowReady());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);
    super.dispose();
  }

  Future<void> _waitForMainWindowReady() async {
    await widget.windowReady;
    if (!mounted) {
      return;
    }
    _windowReady = true;
  }

  bool _onHardwareKeyEvent(KeyEvent event) {
    if (!_windowReady) {
      return false;
    }
    if (event is KeyRepeatEvent || event is! KeyDownEvent) {
      return false;
    }
    if (_hasModifierKeyPressed()) {
      return false;
    }

    final triggerKey = LetterTriggerKeyX.fromPhysicalKey(event.physicalKey);
    if (triggerKey == null) {
      return false;
    }

    if (triggerKey == widget.appState.resetTriggerKey) {
      final result = widget.appState.resetToDefaultBackground();
      if (result == ResetToDefaultResult.defaultNotSet) {
        _controlPageKey.currentState?.showLightweightTip('请先设置默认背景。');
      }
      return true;
    }

    if (triggerKey == widget.appState.playbackTriggerKey) {
      final result = widget.appState.startAndPlayNext();
      if (result == StartPlaybackResult.queueEmpty) {
        _controlPageKey.currentState?.showLightweightTip('播放列表为空，请先添加节目。');
      }
      return true;
    }

    return false;
  }

  bool _hasModifierKeyPressed() {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed;
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
