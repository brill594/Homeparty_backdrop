import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart';

import 'app_i18n.dart';
import 'app_state.dart';
import 'stage_page.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({
    super.key,
    required this.appState,
    required this.locale,
    required this.onLocaleChanged,
  });

  final AppState appState;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  ControlPageState createState() => ControlPageState();
}

class ControlPageState extends State<ControlPage> {
  String? _pendingTip;
  bool _tipFlushScheduled = false;
  bool _addingItem = false;
  bool _playlistFileBusy = false;

  String _artistOrFallback(MediaItem item, AppI18n l10n) {
    if (item.hasArtist) {
      return item.artist!.trim();
    }
    return l10n.t('notFilled');
  }

  Future<void> _setDefaultBackground() async {
    final l10n = context.l10n;
    final path = await _pickMediaPath(
      dialogTitle: l10n.t('chooseDefaultBackgroundDialogTitle'),
    );
    if (path == null) {
      return;
    }

    final item = widget.appState.createItemFromPath(path);
    if (item == null) {
      _showSnackBar(l10n.t('unsupportedMediaFormat'));
      return;
    }

    if (!File(path).existsSync()) {
      _showSnackBar(l10n.t('fileMissingCannotSetDefault'));
      return;
    }

    try {
      await widget.appState.setDefaultBackground(item);
      _showSnackBar(
        l10n.t('defaultBackgroundSet', <String, Object?>{'file': item.fileName}),
      );
    } catch (error) {
      _showSnackBar(
        l10n.t(
          'setDefaultBackgroundFailed',
          <String, Object?>{'error': '$error'},
        ),
      );
    }
  }

  Future<void> _addPlayableItem() async {
    if (_addingItem) {
      return;
    }
    final l10n = context.l10n;
    final input = await showDialog<_PlayableInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddPlayableDialog(
        dialogTitle: l10n.t('addPlayableDialogTitle'),
        submitButtonText: l10n.t('addAndValidate'),
      ),
    );
    if (input == null) {
      return;
    }

    final item = widget.appState.createItemFromPath(
      input.mediaPath,
      audioPath: input.audioPath,
      title: input.title,
      artist: input.artist,
    );
    if (item == null) {
      _showSnackBar(l10n.t('addFailedTypeMismatch'));
      return;
    }

    setState(() {
      _addingItem = true;
    });
    final validationError = await _validatePlayable(item);
    if (!mounted) {
      return;
    }
    setState(() {
      _addingItem = false;
    });

    if (validationError != null) {
      _showSnackBar(validationError);
      return;
    }

    final addedItem = widget.appState.addQueueItem(item);
    _showSnackBar(
      l10n.t('itemAdded', <String, Object?>{
        'title': addedItem.displayTitle,
        'artist': _artistOrFallback(addedItem, l10n),
      }),
    );
  }

  Future<void> _editPlayableItem(int index) async {
    if (_addingItem) {
      return;
    }
    final queue = widget.appState.playQueue;
    if (index < 0 || index >= queue.length) {
      return;
    }
    final current = queue[index];
    final l10n = context.l10n;

    final input = await showDialog<_PlayableInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddPlayableDialog(
        dialogTitle: l10n.t('editPlaybackItemDialogTitle'),
        submitButtonText: l10n.t('saveAndValidate'),
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

    final nextItem = widget.appState.createItemFromPath(
      input.mediaPath,
      audioPath: input.audioPath,
      title: input.title,
      artist: input.artist,
    );
    if (nextItem == null) {
      _showSnackBar(l10n.t('editFailedTypeMismatch'));
      return;
    }

    setState(() {
      _addingItem = true;
    });
    final validationError = await _validatePlayable(nextItem);
    if (!mounted) {
      return;
    }
    setState(() {
      _addingItem = false;
    });
    if (validationError != null) {
      _showSnackBar(validationError);
      return;
    }

    final updatedItem = widget.appState.updateQueueItemAt(index, nextItem);
    if (updatedItem == null) {
      _showSnackBar(l10n.t('editFailedMissingItem'));
      return;
    }
    _showSnackBar(
      l10n.t('itemUpdated', <String, Object?>{
        'title': updatedItem.displayTitle,
        'artist': _artistOrFallback(updatedItem, l10n),
      }),
    );
  }

  void _deletePlayableItem(int index) {
    final l10n = context.l10n;
    final queue = widget.appState.playQueue;
    if (index < 0 || index >= queue.length) {
      return;
    }
    final title = queue[index].displayTitle;
    final removed = widget.appState.removeQueueItemAt(index);
    if (removed) {
      _showSnackBar(l10n.t('itemDeleted', <String, Object?>{'title': title}));
    }
  }

  Future<String?> _validatePlayable(MediaItem item) async {
    final l10n = context.l10n;
    if (!File(item.path).existsSync()) {
      return l10n.t('mediaMissingRejectAdd');
    }

    if (item.type == MediaType.video) {
      return _validateVideo(item.path);
    }

    if (!item.hasAudioPath) {
      return l10n.t('imageNeedsAudioRejectAdd');
    }
    final audioPath = item.audioPath!;
    if (!File(audioPath).existsSync()) {
      return l10n.t('audioMissingRejectAdd');
    }

    final imageError = await _validateImage(item.path);
    if (imageError != null) {
      return imageError;
    }
    return _validateAudio(audioPath);
  }

  Future<String?> _validateImage(String path) async {
    final l10n = context.l10n;
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) {
        return l10n.t('imageEmptyRejectAdd');
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      return null;
    } catch (_) {
      return l10n.t('imageDecodeRejectAdd');
    }
  }

  Future<String?> _validateAudio(String path) async {
    final l10n = context.l10n;
    final player = AudioPlayer();
    try {
      await player.setFilePath(path);
      await player.stop();
      return null;
    } catch (_) {
      return l10n.t('audioDecodeRejectAdd');
    } finally {
      await player.dispose();
    }
  }

  Future<String?> _validateVideo(String path) async {
    final l10n = context.l10n;
    final player = Player();
    try {
      await player.open(Media(Uri.file(path).toString()), play: false);
      await player.stop();
      return null;
    } catch (_) {
      return l10n.t('videoInitRejectAdd');
    } finally {
      await player.dispose();
    }
  }

  void _startNextPlayback() {
    final l10n = context.l10n;
    final result = widget.appState.startAndPlayNext();
    if (result == StartPlaybackResult.queueEmpty) {
      _showSnackBar(l10n.t('queueEmptyAddFirst'));
      return;
    }

    final current = widget.appState.stageOverride;
    if (current != null) {
      _showSnackBar(
        l10n.t('nowPlaying', <String, Object?>{
          'title': current.displayTitle,
          'artist': _artistOrFallback(current, l10n),
        }),
      );
    }
  }

  Future<void> _openStagePage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StagePage(appState: widget.appState),
      ),
    );
  }

  void _switchBackToDefaultBackground() {
    final l10n = context.l10n;
    final result = widget.appState.resetToDefaultBackground();
    if (result == ResetToDefaultResult.defaultNotSet) {
      _showSnackBar(l10n.t('setDefaultFirst'));
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    widget.appState.reorderPlayQueue(oldIndex, newIndex);
  }

  Future<void> _exportPlaylist() async {
    final l10n = context.l10n;
    if (_playlistFileBusy) {
      return;
    }
    if (widget.appState.playQueue.isEmpty) {
      _showSnackBar(l10n.t('queueEmptyCannotExport'));
      return;
    }
    setState(() {
      _playlistFileBusy = true;
    });
    try {
      final suggestedName =
          'playlist_${DateTime.now().toIso8601String().replaceAll(':', '-')}.json';
      var savePath = await FilePicker.platform.saveFile(
        dialogTitle: l10n.t('exportPlaylistDialogTitle'),
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
      final exportPayload = AppState.buildPlaylistFilePayload(
        widget.appState.playQueue,
      );
      final jsonText = const JsonEncoder.withIndent(
        '  ',
      ).convert(exportPayload);
      await File(savePath).writeAsString('$jsonText\n');
      _showSnackBar(
        l10n.t('exportSuccess', <String, Object?>{'path': savePath}),
      );
    } catch (error) {
      _showSnackBar(
        l10n.t('exportFailed', <String, Object?>{'error': '$error'}),
      );
    } finally {
      if (mounted) {
        setState(() {
          _playlistFileBusy = false;
        });
      }
    }
  }

  Future<void> _importPlaylist() async {
    final l10n = context.l10n;
    if (_playlistFileBusy) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: l10n.t('importPlaylistDialogTitle'),
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
      _showSnackBar(l10n.t('readFilePathFailed'));
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _playlistFileBusy = true;
    });
    try {
      final rawText = await File(importPath).readAsString();
      final decoded = jsonDecode(rawText);
      final importedItems = AppState.parsePlaylistFilePayload(decoded);
      if (importedItems == null) {
        _showSnackBar(l10n.t('importInvalidFormat'));
        return;
      }
      if (importedItems.isEmpty) {
        _showSnackBar(l10n.t('importNoItems'));
        return;
      }
      var inaccessiblePaths = _collectInaccessiblePaths(importedItems);
      if (inaccessiblePaths.isNotEmpty) {
        final granted = await _requestImportFileAccess(inaccessiblePaths);
        if (!granted) {
          _showSnackBar(l10n.t('importCancelledNoAccess'));
          return;
        }
        inaccessiblePaths = _collectInaccessiblePaths(importedItems);
        if (inaccessiblePaths.isNotEmpty) {
          _showSnackBar(
            l10n.t(
              'importStillUnauthorized',
              <String, Object?>{'count': inaccessiblePaths.length},
            ),
          );
          return;
        }
      }
      widget.appState.replacePlayQueue(importedItems);
      _showSnackBar(
        l10n.t('importCompleted', <String, Object?>{'count': importedItems.length}),
      );
    } catch (error) {
      _showSnackBar(
        l10n.t('importFailed', <String, Object?>{'error': '$error'}),
      );
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
          title: Text(l10n.t('fileAccessRequiredTitle')),
          content: Text(
            l10n.t('importUnauthorizedFilesDialog', <String, Object?>{
              'count': inaccessiblePaths.length,
              'sampleNames': sampleNames,
              'suffix': suffix,
            }),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.t('authorize')),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return false;
    }
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: l10n.t('authorizeImportDialogTitle'),
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

  Future<String?> _pickMediaPath({required String dialogTitle}) async {
    final l10n = context.l10n;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowMultiple: false,
      withData: false,
      allowedExtensions: AppState.mediaPickerExtensions,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final path = result.files.single.path;
    if (path == null || path.isEmpty) {
      _showSnackBar(l10n.t('readFilePathFailed'));
      return null;
    }
    return path;
  }

  void showLightweightTip(String text) {
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (isCurrent) {
      _showSnackBar(text);
      return;
    }
    _pendingTip = text;
  }

  void _flushPendingTipIfNeeded() {
    if (_tipFlushScheduled) {
      return;
    }
    final pendingTip = _pendingTip;
    if (pendingTip == null) {
      return;
    }
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (!isCurrent) {
      return;
    }
    _tipFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tipFlushScheduled = false;
      if (!mounted) {
        return;
      }
      final message = _pendingTip;
      _pendingTip = null;
      if (message == null) {
        return;
      }
      _showSnackBar(message);
    });
  }

  void _showSnackBar(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _updatePlaybackTriggerKey(LetterTriggerKey? value) {
    if (value == null) {
      return;
    }
    final updated = widget.appState.setPlaybackTriggerKey(value);
    if (!updated) {
      _showSnackBar(context.l10n.t('playbackKeyConflict'));
    }
  }

  void _updateResetTriggerKey(LetterTriggerKey? value) {
    if (value == null) {
      return;
    }
    final updated = widget.appState.setResetTriggerKey(value);
    if (!updated) {
      _showSnackBar(context.l10n.t('resetKeyConflict'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        _flushPendingTipIfNeeded();
        final l10n = context.l10n;
        final defaultItem = widget.appState.defaultBackground;
        final queue = widget.appState.playQueue;
        final nextItem = widget.appState.nextQueueItem;
        final readyText = widget.appState.playbackReady
            ? l10n.t('readyToPlay')
            : l10n.t('notStarted');
        final playbackKey = widget.appState.playbackTriggerKey;
        final resetKey = widget.appState.resetTriggerKey;
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.t('controlPageTitle')),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Text(
                    l10n.t('shortcutHint', <String, Object?>{
                      'playKey': playbackKey.label,
                      'resetKey': resetKey.label,
                    }),
                  ),
                ),
              ),
              PopupMenuButton<Locale>(
                tooltip: l10n.t('language'),
                icon: const Icon(Icons.language),
                initialValue: widget.locale,
                onSelected: widget.onLocaleChanged,
                itemBuilder: (context) => <PopupMenuEntry<Locale>>[
                  PopupMenuItem<Locale>(
                    value: AppI18n.englishLocale,
                    child: Text(l10n.t('languageEnglish')),
                  ),
                  PopupMenuItem<Locale>(
                    value: AppI18n.simplifiedChineseLocale,
                    child: Text(l10n.t('languageSimplifiedChinese')),
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _switchBackToDefaultBackground,
            icon: const Icon(Icons.home_filled),
            label: Text(l10n.t('switchToDefaultBackground')),
          ),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _DefaultStatusCard(defaultItem: defaultItem),
                const SizedBox(height: 10),
                _PlaybackStatusCard(
                  statusText: readyText,
                  playbackKeyLabel: playbackKey.label,
                  resetKeyLabel: resetKey.label,
                  nextItem: nextItem,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    SizedBox(
                      width: 260,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _setDefaultBackground,
                        icon: const Icon(Icons.wallpaper_outlined),
                        label: Text(l10n.t('setDefaultBackground')),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _addingItem || _playlistFileBusy
                            ? null
                            : _addPlayableItem,
                        icon: const Icon(Icons.add_circle_outline),
                        label: Text(
                          _addingItem
                              ? l10n.t('validating')
                              : l10n.t('addPlayableFile'),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _startNextPlayback,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(l10n.t('startPlaybackNext')),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _openStagePage,
                        icon: const Icon(Icons.slideshow),
                        label: Text(l10n.t('openStagePage')),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _playlistFileBusy ? null : _importPlaylist,
                        icon: const Icon(Icons.upload_file),
                        label: Text(
                          _playlistFileBusy
                              ? l10n.t('processing')
                              : l10n.t('importPlaylist'),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _playlistFileBusy ? null : _exportPlaylist,
                        icon: const Icon(Icons.download),
                        label: Text(l10n.t('exportPlaylist')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(l10n.t('playbackTriggerKey')),
                        const SizedBox(width: 12),
                        DropdownButton<LetterTriggerKey>(
                          value: playbackKey,
                          onChanged: _updatePlaybackTriggerKey,
                          items: LetterTriggerKey.values.map((key) {
                            return DropdownMenuItem<LetterTriggerKey>(
                              value: key,
                              child: Text(key.label),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(l10n.t('resetDefaultKey')),
                        const SizedBox(width: 12),
                        DropdownButton<LetterTriggerKey>(
                          value: resetKey,
                          onChanged: _updateResetTriggerKey,
                          items: LetterTriggerKey.values.map((key) {
                            return DropdownMenuItem<LetterTriggerKey>(
                              value: key,
                              child: Text(key.label),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.t('playlistHelp'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: queue.isEmpty
                      ? const _EmptyQueue()
                      : ReorderableListView.builder(
                          itemCount: queue.length,
                          buildDefaultDragHandles: false,
                          onReorder: _onReorder,
                          itemBuilder: (context, index) {
                            final item = queue[index];
                            return _QueueTile(
                              key: ObjectKey(item),
                              item: item,
                              index: index,
                              onEdit: () => _editPlayableItem(index),
                              onDelete: () => _deletePlayableItem(index),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DefaultStatusCard extends StatelessWidget {
  const _DefaultStatusCard({required this.defaultItem});

  final MediaItem? defaultItem;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasDefault = defaultItem != null;
    final text = hasDefault
        ? l10n.t('defaultSet', <String, Object?>{'file': defaultItem!.fileName})
        : l10n.t('notSet');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Icon(
              hasDefault ? Icons.check_circle : Icons.info_outline,
              color: hasDefault ? Colors.greenAccent : Colors.amberAccent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.t('defaultBackgroundStatus', <String, Object?>{'text': text}),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackStatusCard extends StatelessWidget {
  const _PlaybackStatusCard({
    required this.statusText,
    required this.playbackKeyLabel,
    required this.resetKeyLabel,
    required this.nextItem,
  });

  final String statusText;
  final String playbackKeyLabel;
  final String resetKeyLabel;
  final MediaItem? nextItem;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final nextArtist = nextItem != null && nextItem!.hasArtist
        ? nextItem!.artist!.trim()
        : l10n.t('notFilled');
    final nextText = nextItem == null
        ? l10n.t('none')
        : '${nextItem!.displayTitle} ($nextArtist)';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF151A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2D3A3A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.t('playbackStatus', <String, Object?>{'status': statusText}),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(l10n.t('nextItem', <String, Object?>{'next': nextText})),
            const SizedBox(height: 4),
            Text(
              l10n.t(
                'playbackTriggerKeyValue',
                <String, Object?>{'key': playbackKeyLabel},
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.t(
                'resetDefaultKeyValue',
                <String, Object?>{'key': resetKeyLabel},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    super.key,
    required this.item,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  final MediaItem item;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mediaInfo = item.type == MediaType.image
        ? l10n.t('imageWithAudio', <String, Object?>{
            'audio': item.audioPath?.split('/').last ?? l10n.t('notSet'),
          })
        : l10n.t('videoType');
    final artistText = item.hasArtist ? item.artist!.trim() : l10n.t('notFilled');
    return Material(
      key: key,
      color: const Color(0xFF171717),
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        leading: Icon(item.type == MediaType.video ? Icons.movie : Icons.image),
        title: Text(item.displayTitle),
        subtitle: Text(
          '${l10n.t('artistValue', <String, Object?>{'artist': artistText})}\n$mediaInfo',
        ),
        isThreeLine: true,
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

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

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
        child: Text(l10n.t('emptyQueueHintControl'), textAlign: TextAlign.center),
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

class _AddPlayableDialog extends StatefulWidget {
  const _AddPlayableDialog({
    required this.dialogTitle,
    required this.submitButtonText,
    this.initialValue,
  });

  final String dialogTitle;
  final String submitButtonText;
  final _PlayableInput? initialValue;

  @override
  State<_AddPlayableDialog> createState() => _AddPlayableDialogState();
}

class _AddPlayableDialogState extends State<_AddPlayableDialog> {
  late MediaType _selectedType;
  String? _imagePath;
  String? _videoPath;
  String? _audioPath;
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;

  @override
  void initState() {
    super.initState();
    final initialValue = widget.initialValue;
    _selectedType = initialValue?.type ?? MediaType.image;
    if (initialValue?.type == MediaType.video) {
      _videoPath = initialValue?.mediaPath;
    } else {
      _imagePath = initialValue?.mediaPath;
      _audioPath = initialValue?.audioPath;
    }
    _titleController = TextEditingController(text: initialValue?.title ?? '');
    _artistController = TextEditingController(text: initialValue?.artist ?? '');
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
        width: 520,
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
          child: Text(widget.submitButtonText),
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
