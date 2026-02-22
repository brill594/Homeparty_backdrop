import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_i18n.dart';
import 'app_state.dart';
import 'control_page.dart';
import 'playlist_manager_window.dart';
import 'playlist_window_protocol.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (args.isNotEmpty && args.first == 'multi_window') {
    final windowId = args.length > 1 ? int.tryParse(args[1]) : null;
    final rawArguments = args.length > 2 ? args[2] : '';
    final arguments = _decodeWindowArguments(rawArguments);
    final windowKind = arguments['kind']?.toString();
    if (windowId != null && windowKind == 'playlist_manager') {
      runApp(
        PlaylistManagerWindowApp(windowId: windowId, arguments: arguments),
      );
      return;
    }
  }

  // macOS Runner config reminder:
  // 1) Add com.apple.security.files.user-selected.read-write=true
  //    in both macos/Runner/DebugProfile.entitlements and
  //    macos/Runner/Release.entitlements for file import/export.
  // 2) Default background is copied into the app private directory
  //    to survive restarts under macOS sandbox permissions.
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

Map<String, dynamic> _decodeWindowArguments(String rawArguments) {
  if (rawArguments.isEmpty) {
    return <String, dynamic>{};
  }
  try {
    final decoded = jsonDecode(rawArguments);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {
    return <String, dynamic>{};
  }
  return <String, dynamic>{};
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
  late Locale _locale;

  @override
  void initState() {
    super.initState();
    _locale = widget.appState.locale;
    HardwareKeyboard.instance.addHandler(_onHardwareKeyEvent);
    DesktopMultiWindow.setMethodHandler(_onWindowMethodCall);
    unawaited(_waitForMainWindowReady());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);
    DesktopMultiWindow.setMethodHandler(null);
    super.dispose();
  }

  Future<dynamic> _onWindowMethodCall(MethodCall call, int fromWindowId) async {
    if (fromWindowId <= 0) {
      return _buildWindowResponse(ok: false, error: _tr('childWindowOnly'));
    }
    switch (call.method) {
      case PlaylistWindowMethods.getSnapshot:
        return _buildWindowResponse(ok: true);
      case PlaylistWindowMethods.addItem:
        final args = _toMap(call.arguments);
        final item = MediaItem.fromJson(args?[PlaylistWindowPayloadKeys.item]);
        if (item == null) {
          return _buildWindowResponse(ok: false, error: _tr('addInvalidProgramData'));
        }
        widget.appState.addQueueItem(item);
        return _buildWindowResponse(ok: true);
      case PlaylistWindowMethods.updateItem:
        final args = _toMap(call.arguments);
        final index = _toInt(args?[PlaylistWindowPayloadKeys.index]);
        final item = MediaItem.fromJson(args?[PlaylistWindowPayloadKeys.item]);
        if (index == null || item == null) {
          return _buildWindowResponse(ok: false, error: _tr('editInvalidArgs'));
        }
        final updated = widget.appState.updateQueueItemAt(index, item);
        if (updated == null) {
          return _buildWindowResponse(ok: false, error: _tr('editItemMissing'));
        }
        return _buildWindowResponse(ok: true);
      case PlaylistWindowMethods.deleteItem:
        final args = _toMap(call.arguments);
        final index = _toInt(args?[PlaylistWindowPayloadKeys.index]);
        if (index == null) {
          return _buildWindowResponse(ok: false, error: _tr('deleteInvalidArgs'));
        }
        final removed = widget.appState.removeQueueItemAt(index);
        if (!removed) {
          return _buildWindowResponse(ok: false, error: _tr('deleteItemMissing'));
        }
        return _buildWindowResponse(ok: true);
      case PlaylistWindowMethods.reorder:
        final args = _toMap(call.arguments);
        final oldIndex = _toInt(args?[PlaylistWindowPayloadKeys.oldIndex]);
        final newIndex = _toInt(args?[PlaylistWindowPayloadKeys.newIndex]);
        if (oldIndex == null || newIndex == null) {
          return _buildWindowResponse(ok: false, error: _tr('reorderInvalidArgs'));
        }
        widget.appState.reorderPlayQueue(oldIndex, newIndex);
        return _buildWindowResponse(ok: true);
      case PlaylistWindowMethods.replaceQueue:
        final args = _toMap(call.arguments);
        final rawQueue = args?[PlaylistWindowPayloadKeys.queue];
        if (rawQueue is! List) {
          return _buildWindowResponse(ok: false, error: _tr('importInvalidArgs'));
        }
        final queueItems = <MediaItem>[];
        for (final rawItem in rawQueue) {
          final item = MediaItem.fromJson(rawItem);
          if (item != null) {
            queueItems.add(item);
          }
        }
        widget.appState.replacePlayQueue(queueItems);
        return _buildWindowResponse(ok: true);
    }
    return _buildWindowResponse(
      ok: false,
      error: _tr('unknownAction', <String, Object?>{'method': call.method}),
    );
  }

  Map<String, dynamic> _buildWindowResponse({required bool ok, String? error}) {
    return <String, dynamic>{
      'ok': ok,
      'error': error,
      'snapshot': widget.appState.buildQueueSnapshot(),
    };
  }

  Map<String, dynamic>? _toMap(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  int? _toInt(dynamic raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  Future<void> _waitForMainWindowReady() async {
    await widget.windowReady;
    if (!mounted) {
      return;
    }
    _windowReady = true;
  }

  String _tr(
    String key, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) {
    return AppI18n.tr(_locale, key, params);
  }

  Future<void> _onLocaleChanged(Locale nextLocale) async {
    final normalized = AppI18n.normalizeLocale(nextLocale);
    if (_locale != normalized && mounted) {
      setState(() {
        _locale = normalized;
      });
    }
    await widget.appState.setLocale(normalized);
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
        _controlPageKey.currentState?.showLightweightTip(_tr('setDefaultFirst'));
      }
      return true;
    }

    if (triggerKey == widget.appState.playbackTriggerKey) {
      final result = widget.appState.startAndPlayNext();
      if (result == StartPlaybackResult.queueEmpty) {
        _controlPageKey.currentState?.showLightweightTip(
          _tr('queueEmptyAddFirst'),
        );
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
      title: _tr('homepartyControlTitle'),
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: AppI18n.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppI18n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFF101010),
        useMaterial3: true,
      ),
      home: ControlPage(
        key: _controlPageKey,
        appState: widget.appState,
        locale: _locale,
        onLocaleChanged: _onLocaleChanged,
      ),
    );
  }
}
