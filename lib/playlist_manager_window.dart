import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_i18n.dart';
import 'app_state.dart';
import 'playlist_window_protocol.dart';

class PlaylistManagerWindowApp extends StatelessWidget {
  const PlaylistManagerWindowApp({
    super.key,
    required this.windowId,
    required this.arguments,
  });

  final int windowId;
  final Map<String, dynamic> arguments;

  @override
  Widget build(BuildContext context) {
    final hostWindowId = _toInt(arguments['hostWindowId']) ?? 0;
    final rawLocaleCode = arguments['locale']?.toString();
    final locale = rawLocaleCode == null || rawLocaleCode.trim().isEmpty
        ? AppI18n.normalizeLocale(WidgetsBinding.instance.platformDispatcher.locale)
        : AppI18n.localeFromStorageCode(rawLocaleCode);
    return MaterialApp(
      title: AppI18n.tr(locale, 'playlistManagerTitle'),
      debugShowCheckedModeBanner: false,
      locale: locale,
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
      home: PlaylistManagerWindow(
        windowController: WindowController.fromWindowId(windowId),
        hostWindowId: hostWindowId,
        locale: locale,
      ),
    );
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
}

class PlaylistManagerWindow extends StatefulWidget {
  const PlaylistManagerWindow({
    super.key,
    required this.windowController,
    required this.hostWindowId,
    required this.locale,
  });

  final WindowController windowController;
  final int hostWindowId;
  final Locale locale;

  @override
  State<PlaylistManagerWindow> createState() => _PlaylistManagerWindowState();
}

class _PlaylistManagerWindowState extends State<PlaylistManagerWindow> {
  final List<MediaItem> _queue = <MediaItem>[];

  Timer? _autoRefreshTimer;
  bool _loading = true;
  bool _submitting = false;
  bool _playlistFileBusy = false;
  bool _snapshotRequestInFlight = false;
  String? _errorText;
  int? _currentQueueIndex;
  int _nextPlayIndex = 0;
  bool _playbackReady = false;

  String _tr(
    String key, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) {
    return AppI18n.tr(widget.locale, key, params);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_configureWindow());
    unawaited(_refreshSnapshot(showLoading: true));
    _autoRefreshTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted || _submitting) {
        return;
      }
      unawaited(_refreshSnapshot());
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _configureWindow() async {
    await windowManager.ensureInitialized();
    final windowTitle = _tr('stagePlaylistManagerTitle');
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        title: windowTitle,
        minimumSize: Size(520, 620),
        size: Size(560, 760),
        center: true,
        alwaysOnTop: true,
        backgroundColor: Color(0xFF101010),
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
        await windowManager.setAlwaysOnTop(true);
      },
    );
  }

  Future<void> _refreshSnapshot({bool showLoading = false}) async {
    if (_snapshotRequestInFlight) {
      return;
    }
    _snapshotRequestInFlight = true;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final response = await DesktopMultiWindow.invokeMethod(
        widget.hostWindowId,
        PlaylistWindowMethods.getSnapshot,
      );
      final parsed = _parseResponse(response);
      _applySnapshot(parsed.snapshot);
      if (!parsed.ok && parsed.error != null) {
        _showSnackBar(parsed.error!);
      }
      if (mounted) {
        setState(() {
          _errorText = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorText = _tr('readPlaylistFailed', <String, Object?>{'error': '$error'});
        });
      }
    } finally {
      _snapshotRequestInFlight = false;
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _addPlayableItem() async {
    if (_submitting) {
      return;
    }
    final input = await showDialog<_PlayableInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddOrEditPlayableDialog(
        dialogTitle: _tr('addProgramDialogTitle'),
        submitText: _tr('addAndSave'),
      ),
    );
    if (input == null) {
      return;
    }
    final item = _createItemFromInput(input);
    if (item == null) {
      _showSnackBar(_tr('addFailedTypeMismatch'));
      return;
    }
    final validationError = await _validatePlayable(item);
    if (validationError != null) {
      _showSnackBar(validationError);
      return;
    }
    await _invokeMutation(PlaylistWindowMethods.addItem, <String, dynamic>{
      PlaylistWindowPayloadKeys.item: item.toJson(),
    });
  }

  Future<void> _editPlayableItem(int index) async {
    if (_submitting || index < 0 || index >= _queue.length) {
      return;
    }
    final current = _queue[index];
    final input = await showDialog<_PlayableInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddOrEditPlayableDialog(
        dialogTitle: _tr('editProgramDialogTitle'),
        submitText: _tr('saveChanges'),
        initialValue: _PlayableInput(
          type: current.type,
          mediaPath: current.path,
          audioPath: current.audioPath,
          title: current.title,
          artist: current.artist,
        ),
      ),
    );
    if (input == null) {
      return;
    }
    final item = _createItemFromInput(input);
    if (item == null) {
      _showSnackBar(_tr('editFailedTypeMismatch'));
      return;
    }
    final validationError = await _validatePlayable(item);
    if (validationError != null) {
      _showSnackBar(validationError);
      return;
    }
    await _invokeMutation(PlaylistWindowMethods.updateItem, <String, dynamic>{
      PlaylistWindowPayloadKeys.index: index,
      PlaylistWindowPayloadKeys.item: item.toJson(),
    });
  }

  Future<void> _deletePlayableItem(int index) async {
    if (_submitting || index < 0 || index >= _queue.length) {
      return;
    }
    await _invokeMutation(PlaylistWindowMethods.deleteItem, <String, dynamic>{
      PlaylistWindowPayloadKeys.index: index,
    });
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (_submitting) {
      return;
    }
    await _invokeMutation(PlaylistWindowMethods.reorder, <String, dynamic>{
      PlaylistWindowPayloadKeys.oldIndex: oldIndex,
      PlaylistWindowPayloadKeys.newIndex: newIndex,
    });
  }

  Future<void> _exportPlaylist() async {
    if (_submitting || _playlistFileBusy) {
      return;
    }
    if (_queue.isEmpty) {
      _showSnackBar(_tr('queueEmptyCannotExport'));
      return;
    }
    if (mounted) {
      setState(() {
        _playlistFileBusy = true;
      });
    }
    try {
      final suggestedName =
          'playlist_${DateTime.now().toIso8601String().replaceAll(':', '-')}.json';
      var savePath = await FilePicker.platform.saveFile(
        dialogTitle: _tr('exportPlaylistDialogTitle'),
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
      );
      if (savePath == null || savePath.trim().isEmpty) {
        return;
      }
      savePath = savePath.trim();
      if (!savePath.toLowerCase().endsWith('.json')) {
        savePath = '$savePath.json';
      }
      final payload = AppState.buildPlaylistFilePayload(_queue);
      final text = const JsonEncoder.withIndent('  ').convert(payload);
      await File(savePath).writeAsString('$text\n');
      _showSnackBar(_tr('exportSuccess', <String, Object?>{'path': savePath}));
    } catch (error) {
      _showSnackBar(_tr('exportFailed', <String, Object?>{'error': '$error'}));
    } finally {
      if (mounted) {
        setState(() {
          _playlistFileBusy = false;
        });
      }
    }
  }

  Future<void> _importPlaylist() async {
    if (_submitting || _playlistFileBusy) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: _tr('importPlaylistDialogTitle'),
      type: FileType.custom,
      allowMultiple: false,
      withData: false,
      allowedExtensions: const <String>['json'],
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final importPath = result.files.single.path;
    if (importPath == null || importPath.isEmpty) {
      _showSnackBar(_tr('readFilePathFailed'));
      return;
    }
    if (!mounted) {
      return;
    }
    if (mounted) {
      setState(() {
        _playlistFileBusy = true;
      });
    }
    try {
      final rawText = await File(importPath).readAsString();
      final decoded = jsonDecode(rawText);
      final importedItems = AppState.parsePlaylistFilePayload(decoded);
      if (importedItems == null) {
        _showSnackBar(_tr('importInvalidFormat'));
        return;
      }
      if (importedItems.isEmpty) {
        _showSnackBar(_tr('importNoItems'));
        return;
      }
      var inaccessiblePaths = _collectInaccessiblePaths(importedItems);
      if (inaccessiblePaths.isNotEmpty) {
        final granted = await _requestImportFileAccess(inaccessiblePaths);
        if (!granted) {
          _showSnackBar(_tr('importCancelledNoAccess'));
          return;
        }
        inaccessiblePaths = _collectInaccessiblePaths(importedItems);
        if (inaccessiblePaths.isNotEmpty) {
          _showSnackBar(_tr(
            'importStillUnauthorized',
            <String, Object?>{'count': inaccessiblePaths.length},
          ));
          return;
        }
      }
      await _invokeMutation(
        PlaylistWindowMethods.replaceQueue,
        <String, dynamic>{
          PlaylistWindowPayloadKeys.queue: importedItems
              .map((item) => item.toJson())
              .toList(),
        },
      );
      _showSnackBar(
        _tr('importCompleted', <String, Object?>{'count': importedItems.length}),
      );
    } catch (error) {
      _showSnackBar(_tr('importFailed', <String, Object?>{'error': '$error'}));
    } finally {
      if (mounted) {
        setState(() {
          _playlistFileBusy = false;
        });
      }
    }
  }

  Set<String> _collectInaccessiblePaths(Iterable<MediaItem> items) {
    final paths = <String>{};
    for (final item in items) {
      if (!_isReadablePath(item.path)) {
        paths.add(item.path);
      }
      if (item.type == MediaType.image && item.hasAudioPath) {
        final audioPath = item.audioPath!;
        if (!_isReadablePath(audioPath)) {
          paths.add(audioPath);
        }
      }
    }
    return paths;
  }

  Future<bool> _requestImportFileAccess(Set<String> inaccessiblePaths) async {
    if (!mounted || inaccessiblePaths.isEmpty) {
      return inaccessiblePaths.isEmpty;
    }
    final l10n = context.l10n;
    final sampleNames = inaccessiblePaths
        .take(3)
        .map(_fileNameFromPath)
        .join(l10n.locale.languageCode == 'zh' ? '、' : ', ');
    final suffix = inaccessiblePaths.length > 3
        ? (l10n.locale.languageCode == 'zh' ? ' 等文件' : ' and more files')
        : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_tr('fileAccessRequiredTitle')),
          content: Text(
            _tr('importUnauthorizedFilesDialog', <String, Object?>{
              'count': inaccessiblePaths.length,
              'sampleNames': sampleNames,
              'suffix': suffix,
            }),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_tr('authorize')),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return false;
    }
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: _tr('authorizeImportDialogTitle'),
      type: FileType.custom,
      allowMultiple: true,
      withData: false,
      allowedExtensions: AppState.importAccessPickerExtensions,
    );
    return picked != null && picked.files.isNotEmpty;
  }

  String _fileNameFromPath(String path) {
    if (path.isEmpty) {
      return path;
    }
    return path.split(Platform.pathSeparator).last;
  }

  bool _isReadablePath(String path) {
    if (path.isEmpty) {
      return false;
    }
    final file = File(path);
    if (!file.existsSync()) {
      return false;
    }
    RandomAccessFile? raf;
    try {
      raf = file.openSync(mode: FileMode.read);
      raf.readSync(1);
      return true;
    } catch (_) {
      return false;
    } finally {
      raf?.closeSync();
    }
  }

  MediaItem? _createItemFromInput(_PlayableInput input) {
    final extension = _normalizedExtension(input.mediaPath);
    if (AppState.imageExtensions.contains(extension)) {
      return MediaItem(
        type: MediaType.image,
        path: input.mediaPath,
        audioPath: input.audioPath,
        title: input.title,
        artist: input.artist,
      );
    }
    if (AppState.videoExtensions.contains(extension)) {
      return MediaItem(
        type: MediaType.video,
        path: input.mediaPath,
        title: input.title,
        artist: input.artist,
      );
    }
    return null;
  }

  Future<void> _invokeMutation(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    if (mounted) {
      setState(() {
        _submitting = true;
      });
    }
    try {
      final response = await DesktopMultiWindow.invokeMethod(
        widget.hostWindowId,
        method,
        arguments,
      );
      final parsed = _parseResponse(response);
      _applySnapshot(parsed.snapshot);
      if (!parsed.ok && parsed.error != null) {
        _showSnackBar(parsed.error!);
      }
    } catch (error) {
      _showSnackBar(_tr('operationFailed', <String, Object?>{'error': '$error'}));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  _HostResponse _parseResponse(dynamic raw) {
    if (raw is! Map) {
      return _HostResponse(
        ok: false,
        error: _tr('invalidHostResponse'),
        snapshot: _buildCurrentSnapshot(),
      );
    }
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final snapshotRaw = map['snapshot'];
    final snapshot = _parseSnapshot(snapshotRaw) ?? _buildCurrentSnapshot();
    final ok = map['ok'] == true;
    final error = map['error']?.toString();
    return _HostResponse(ok: ok, error: error, snapshot: snapshot);
  }

  Map<String, dynamic> _buildCurrentSnapshot() {
    return <String, dynamic>{
      'queue': _queue.map((item) => item.toJson()).toList(),
      'nextPlayIndex': _nextPlayIndex,
      'currentQueueIndex': _currentQueueIndex,
      'playbackReady': _playbackReady,
    };
  }

  Map<String, dynamic>? _parseSnapshot(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  void _applySnapshot(Map<String, dynamic> snapshot) {
    final rawQueue = snapshot['queue'];
    final parsedQueue = <MediaItem>[];
    if (rawQueue is List) {
      for (final item in rawQueue) {
        final parsed = MediaItem.fromJson(item);
        if (parsed != null) {
          parsedQueue.add(parsed);
        }
      }
    }
    final nextPlayIndex = _toInt(snapshot['nextPlayIndex']) ?? 0;
    final currentQueueIndex = _toInt(snapshot['currentQueueIndex']);
    final playbackReady = snapshot['playbackReady'] == true;
    if (!mounted) {
      return;
    }
    setState(() {
      _queue
        ..clear()
        ..addAll(parsedQueue);
      _nextPlayIndex = nextPlayIndex;
      _currentQueueIndex = currentQueueIndex;
      _playbackReady = playbackReady;
    });
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

  String _normalizedExtension(String path) {
    final parts = path.split('.');
    if (parts.length < 2) {
      return '';
    }
    return parts.last.toLowerCase();
  }

  Future<String?> _validatePlayable(MediaItem item) async {
    if (!File(item.path).existsSync()) {
      return _tr('mediaMissingRejectSave');
    }
    if (item.type == MediaType.video) {
      return _validateVideo(item.path);
    }
    if (!item.hasAudioPath) {
      return _tr('imageNeedsAudioRejectSave');
    }
    final audioPath = item.audioPath!;
    if (!File(audioPath).existsSync()) {
      return _tr('audioMissingRejectSave');
    }
    final imageError = await _validateImage(item.path);
    if (imageError != null) {
      return imageError;
    }
    return _validateAudio(audioPath);
  }

  Future<String?> _validateImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) {
        return _tr('imageEmptyRejectSave');
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      return null;
    } catch (_) {
      return _tr('imageDecodeRejectSave');
    }
  }

  Future<String?> _validateAudio(String path) async {
    final player = AudioPlayer();
    try {
      await player.setFilePath(path);
      await player.stop();
      return null;
    } catch (_) {
      return _tr('audioDecodeRejectSave');
    } finally {
      await player.dispose();
    }
  }

  Future<String?> _validateVideo(String path) async {
    final player = Player();
    try {
      await player.open(Media(Uri.file(path).toString()), play: false);
      await player.stop();
      return null;
    } catch (_) {
      return _tr('videoInitRejectSave');
    } finally {
      await player.dispose();
    }
  }

  void _showSnackBar(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasQueue = _queue.isNotEmpty;
    final safeNextIndex = hasQueue ? _nextPlayIndex % _queue.length : null;
    final safeCurrentIndex = hasQueue && _currentQueueIndex != null
        ? _currentQueueIndex! % _queue.length
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('stagePlaylistManagerTitle')),
        actions: <Widget>[
          IconButton(
            onPressed: _submitting || _playlistFileBusy
                ? null
                : _importPlaylist,
            tooltip: l10n.t('importTooltip'),
            icon: const Icon(Icons.upload_file),
          ),
          IconButton(
            onPressed: _submitting || _playlistFileBusy
                ? null
                : _exportPlaylist,
            tooltip: l10n.t('exportTooltip'),
            icon: const Icon(Icons.download),
          ),
          IconButton(
            onPressed: _submitting || _playlistFileBusy
                ? null
                : () => _refreshSnapshot(showLoading: true),
            tooltip: l10n.t('refreshTooltip'),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => widget.windowController.close(),
            tooltip: l10n.t('closeTooltip'),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _submitting || _playlistFileBusy ? null : _addPlayableItem,
        icon: const Icon(Icons.add),
        label: Text(
          _submitting || _playlistFileBusy
              ? l10n.t('processing')
              : l10n.t('addProgram'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _QueueStatusCard(
              loading: _loading,
              errorText: _errorText,
              queueLength: _queue.length,
              playbackReady: _playbackReady,
              currentOrder: safeCurrentIndex == null
                  ? null
                  : safeCurrentIndex + 1,
              nextOrder: safeNextIndex == null ? null : safeNextIndex + 1,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.t('playlistListHint'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _queue.isEmpty
                  ? const _EmptyQueueHint()
                  : ReorderableListView.builder(
                      itemCount: _queue.length,
                      buildDefaultDragHandles: false,
                      onReorder: _onReorder,
                      itemBuilder: (context, index) {
                        final item = _queue[index];
                        return _QueueItemTile(
                          key: ObjectKey(item),
                          item: item,
                          index: index,
                          isCurrent: index == safeCurrentIndex,
                          isNext: index == safeNextIndex,
                          onEdit: _submitting
                              ? null
                              : () => _editPlayableItem(index),
                          onDelete: _submitting
                              ? null
                              : () => _deletePlayableItem(index),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HostResponse {
  const _HostResponse({
    required this.ok,
    required this.error,
    required this.snapshot,
  });

  final bool ok;
  final String? error;
  final Map<String, dynamic> snapshot;
}

class _QueueStatusCard extends StatelessWidget {
  const _QueueStatusCard({
    required this.loading,
    required this.errorText,
    required this.queueLength,
    required this.playbackReady,
    required this.currentOrder,
    required this.nextOrder,
  });

  final bool loading;
  final String? errorText;
  final int queueLength;
  final bool playbackReady;
  final int? currentOrder;
  final int? nextOrder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final readyText = playbackReady ? l10n.t('readyToPlay') : l10n.t('notStarted');
    final currentText = currentOrder == null ? l10n.t('none') : '$currentOrder';
    final nextText = nextOrder == null ? l10n.t('none') : '$nextOrder';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF171B1B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3434)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.t('queueEntryCount', <String, Object?>{'count': queueLength})),
            const SizedBox(height: 4),
            Text(l10n.t('playbackStatus', <String, Object?>{'status': readyText})),
            const SizedBox(height: 4),
            Text(l10n.t('currentOrder', <String, Object?>{'order': currentText})),
            const SizedBox(height: 2),
            Text(l10n.t('nextOrder', <String, Object?>{'order': nextText})),
            if (loading) ...<Widget>[
              const SizedBox(height: 6),
              Text(l10n.t('syncing')),
            ],
            if (errorText != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(errorText!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
    );
  }
}

class _QueueItemTile extends StatelessWidget {
  const _QueueItemTile({
    super.key,
    required this.item,
    required this.index,
    required this.isCurrent,
    required this.isNext,
    required this.onEdit,
    required this.onDelete,
  });

  final MediaItem item;
  final int index;
  final bool isCurrent;
  final bool isNext;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tileColor = isCurrent
        ? const Color(0xFF215236)
        : isNext
        ? const Color(0xFF204141)
        : const Color(0xFF171717);
    return Material(
      key: key,
      color: tileColor,
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: Colors.white12,
          child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
        ),
        title: Text(item.displayTitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.t('edit'),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.t('delete'),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_indicator),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyQueueHint extends StatelessWidget {
  const _EmptyQueueHint();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Center(
        child: Text(l10n.t('emptyQueueHintManager'), textAlign: TextAlign.center),
      ),
    );
  }
}

class _PlayableInput {
  const _PlayableInput({
    required this.type,
    required this.mediaPath,
    this.audioPath,
    this.title,
    this.artist,
  });

  final MediaType type;
  final String mediaPath;
  final String? audioPath;
  final String? title;
  final String? artist;
}

class _AddOrEditPlayableDialog extends StatefulWidget {
  const _AddOrEditPlayableDialog({
    required this.dialogTitle,
    required this.submitText,
    this.initialValue,
  });

  final String dialogTitle;
  final String submitText;
  final _PlayableInput? initialValue;

  @override
  State<_AddOrEditPlayableDialog> createState() =>
      _AddOrEditPlayableDialogState();
}

class _AddOrEditPlayableDialogState extends State<_AddOrEditPlayableDialog> {
  late MediaType _selectedType;
  String? _imagePath;
  String? _videoPath;
  String? _audioPath;
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _selectedType = initial?.type ?? MediaType.image;
    if (initial?.type == MediaType.video) {
      _videoPath = initial?.mediaPath;
    } else {
      _imagePath = initial?.mediaPath;
      _audioPath = initial?.audioPath;
    }
    _titleController = TextEditingController(text: initial?.title ?? '');
    _artistController = TextEditingController(text: initial?.artist ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final l10n = context.l10n;
    final path = await _pickFile(
      title: l10n.t('pickImage'),
      extensions: AppState.imageExtensions,
    );
    if (path == null) {
      return;
    }
    setState(() {
      _imagePath = path;
    });
  }

  Future<void> _pickVideo() async {
    final l10n = context.l10n;
    final path = await _pickFile(
      title: l10n.t('pickVideo'),
      extensions: AppState.videoExtensions,
    );
    if (path == null) {
      return;
    }
    setState(() {
      _videoPath = path;
    });
  }

  Future<void> _pickAudio() async {
    final l10n = context.l10n;
    final path = await _pickFile(
      title: l10n.t('pickAudio'),
      extensions: AppState.audioExtensions,
    );
    if (path == null) {
      return;
    }
    setState(() {
      _audioPath = path;
    });
  }

  Future<String?> _pickFile({
    required String title,
    required List<String> extensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: title,
      type: FileType.custom,
      allowMultiple: false,
      withData: false,
      allowedExtensions: extensions,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final path = result.files.single.path;
    if (path == null || path.isEmpty) {
      return null;
    }
    return path;
  }

  bool get _canSubmit {
    if (_selectedType == MediaType.video) {
      return _videoPath != null && _videoPath!.isNotEmpty;
    }
    return _imagePath != null &&
        _imagePath!.isNotEmpty &&
        _audioPath != null &&
        _audioPath!.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.dialogTitle),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SegmentedButton<MediaType>(
                segments: <ButtonSegment<MediaType>>[
                  ButtonSegment<MediaType>(
                    value: MediaType.image,
                    label: Text(l10n.t('imageOption')),
                  ),
                  ButtonSegment<MediaType>(
                    value: MediaType.video,
                    label: Text(l10n.t('videoOption')),
                  ),
                ],
                selected: <MediaType>{_selectedType},
                onSelectionChanged: (selection) {
                  setState(() {
                    _selectedType = selection.first;
                  });
                },
              ),
              const SizedBox(height: 14),
              if (_selectedType == MediaType.image) ...<Widget>[
                FilledButton.tonalIcon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image),
                  label: Text(l10n.t('selectImageRequired')),
                ),
                if (_imagePath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.t('imagePath', <String, Object?>{'path': _imagePath}),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _pickAudio,
                  icon: const Icon(Icons.music_note),
                  label: Text(l10n.t('selectAudioRequired')),
                ),
                if (_audioPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.t('audioPath', <String, Object?>{'path': _audioPath}),
                    ),
                  ),
              ] else ...<Widget>[
                FilledButton.tonalIcon(
                  onPressed: _pickVideo,
                  icon: const Icon(Icons.movie),
                  label: Text(l10n.t('selectVideoRequired')),
                ),
                if (_videoPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.t('videoPath', <String, Object?>{'path': _videoPath}),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: l10n.t('programTitleOptional'),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _artistController,
                decoration: InputDecoration(
                  labelText: l10n.t('artistOptional'),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: _canSubmit
              ? () {
                  final title = _normalizedTextOrNull(_titleController.text);
                  final artist = _normalizedTextOrNull(_artistController.text);
                  if (_selectedType == MediaType.image) {
                    Navigator.of(context).pop(
                      _PlayableInput(
                        type: MediaType.image,
                        mediaPath: _imagePath!,
                        audioPath: _audioPath!,
                        title: title,
                        artist: artist,
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).pop(
                    _PlayableInput(
                      type: MediaType.video,
                      mediaPath: _videoPath!,
                      title: title,
                      artist: artist,
                    ),
                  );
                }
              : null,
          child: Text(widget.submitText),
        ),
      ],
    );
  }

  String? _normalizedTextOrNull(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
