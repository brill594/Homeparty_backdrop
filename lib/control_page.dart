import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import 'app_state.dart';
import 'stage_page.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({super.key, required this.appState});

  final AppState appState;

  @override
  ControlPageState createState() => ControlPageState();
}

class ControlPageState extends State<ControlPage> {
  String? _pendingTip;
  bool _tipFlushScheduled = false;
  bool _addingItem = false;
  bool _playlistFileBusy = false;

  Future<void> _setDefaultBackground() async {
    final path = await _pickMediaPath(dialogTitle: '选择默认背景（图片或视频）');
    if (path == null) {
      return;
    }

    final item = widget.appState.createItemFromPath(path);
    if (item == null) {
      _showSnackBar('不支持的媒体格式。');
      return;
    }

    if (!File(path).existsSync()) {
      _showSnackBar('文件不存在，无法设置默认背景。');
      return;
    }

    try {
      await widget.appState.setDefaultBackground(item);
      _showSnackBar('默认背景已设置：${item.fileName}');
    } catch (error) {
      _showSnackBar('设置默认背景失败：$error');
    }
  }

  Future<void> _addPlayableItem() async {
    if (_addingItem) {
      return;
    }
    final input = await showDialog<_PlayableInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _AddPlayableDialog(),
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
      _showSnackBar('添加失败：文件类型与选择的播放类型不匹配。');
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
      '已添加：${addedItem.displayTitle}（演唱者：${addedItem.displayArtist}）',
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

    final input = await showDialog<_PlayableInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddPlayableDialog(
        dialogTitle: '编辑播放条目',
        submitButtonText: '保存并校验',
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
      _showSnackBar('编辑失败：文件类型与选择的播放类型不匹配。');
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
      _showSnackBar('编辑失败：条目已不存在。');
      return;
    }
    _showSnackBar(
      '已更新：${updatedItem.displayTitle}（演唱者：${updatedItem.displayArtist}）',
    );
  }

  void _deletePlayableItem(int index) {
    final queue = widget.appState.playQueue;
    if (index < 0 || index >= queue.length) {
      return;
    }
    final title = queue[index].displayTitle;
    final removed = widget.appState.removeQueueItemAt(index);
    if (removed) {
      _showSnackBar('已删除：$title');
    }
  }

  Future<String?> _validatePlayable(MediaItem item) async {
    if (!File(item.path).existsSync()) {
      return '媒体文件不存在，已拒绝添加。';
    }

    if (item.type == MediaType.video) {
      return _validateVideo(item.path);
    }

    if (!item.hasAudioPath) {
      return '图片类型必须提供伴奏音乐，已拒绝添加。';
    }
    final audioPath = item.audioPath!;
    if (!File(audioPath).existsSync()) {
      return '伴奏文件不存在，已拒绝添加。';
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
        return '图片文件为空，已拒绝添加。';
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      return null;
    } catch (_) {
      return '图片无法解码，已拒绝添加。';
    }
  }

  Future<String?> _validateAudio(String path) async {
    final player = AudioPlayer();
    try {
      await player.setFilePath(path);
      await player.stop();
      return null;
    } catch (_) {
      return '伴奏文件无法播放，已拒绝添加。';
    } finally {
      await player.dispose();
    }
  }

  Future<String?> _validateVideo(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      return null;
    } catch (_) {
      return '视频初始化失败，已拒绝添加。';
    } finally {
      await controller.dispose();
    }
  }

  void _startNextPlayback() {
    final result = widget.appState.startAndPlayNext();
    if (result == StartPlaybackResult.queueEmpty) {
      _showSnackBar('播放列表为空，请先添加节目。');
      return;
    }

    final current = widget.appState.stageOverride;
    if (current != null) {
      _showSnackBar(
        '正在播放：${current.displayTitle}（演唱者：${current.displayArtist}）',
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
    final result = widget.appState.resetToDefaultBackground();
    if (result == ResetToDefaultResult.defaultNotSet) {
      _showSnackBar('请先设置默认背景。');
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    widget.appState.reorderPlayQueue(oldIndex, newIndex);
  }

  Future<void> _exportPlaylist() async {
    if (_playlistFileBusy) {
      return;
    }
    if (widget.appState.playQueue.isEmpty) {
      _showSnackBar('播放列表为空，无法导出。');
      return;
    }
    setState(() {
      _playlistFileBusy = true;
    });
    try {
      final suggestedName =
          'playlist_${DateTime.now().toIso8601String().replaceAll(':', '-')}.json';
      var savePath = await FilePicker.platform.saveFile(
        dialogTitle: '导出播放列表',
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
      _showSnackBar('导出成功：$savePath');
    } catch (error) {
      _showSnackBar('导出失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _playlistFileBusy = false;
        });
      }
    }
  }

  Future<void> _importPlaylist() async {
    if (_playlistFileBusy) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入播放列表',
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
      _showSnackBar('读取文件路径失败。');
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
        _showSnackBar('导入失败：文件格式无效。');
        return;
      }
      if (importedItems.isEmpty) {
        _showSnackBar('导入失败：文件中没有可用条目。');
        return;
      }
      var inaccessiblePaths = _collectInaccessiblePaths(importedItems);
      if (inaccessiblePaths.isNotEmpty) {
        final granted = await _requestImportFileAccess(inaccessiblePaths);
        if (!granted) {
          _showSnackBar('导入已取消：未完成媒体文件访问授权。');
          return;
        }
        inaccessiblePaths = _collectInaccessiblePaths(importedItems);
        if (inaccessiblePaths.isNotEmpty) {
          _showSnackBar(
            '导入失败：仍有 ${inaccessiblePaths.length} 个文件未授权，请在授权窗口中多选这些媒体文件。',
          );
          return;
        }
      }
      widget.appState.replacePlayQueue(importedItems);
      _showSnackBar('导入完成，共 ${importedItems.length} 条。');
    } catch (error) {
      _showSnackBar('导入失败：$error');
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
    final sampleNames = inaccessiblePaths
        .take(3)
        .map(_fileNameFromPath)
        .join('、');
    final suffix = inaccessiblePaths.length > 3 ? ' 等文件' : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('需要系统文件权限'),
          content: Text(
            '导入列表引用了 ${inaccessiblePaths.length} 个未授权文件（如：$sampleNames$suffix）。\n\n点击“去授权”后，请在系统窗口中按住 Command 多选这些媒体文件。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('去授权'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return false;
    }
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '为导入播放列表授权媒体文件（可多选）',
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
      _showSnackBar('读取文件路径失败。');
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
      _showSnackBar('播放触发键不能与“切回默认”按键重复。');
    }
  }

  void _updateResetTriggerKey(LetterTriggerKey? value) {
    if (value == null) {
      return;
    }
    final updated = widget.appState.setResetTriggerKey(value);
    if (!updated) {
      _showSnackBar('“切回默认”按键不能与播放触发键重复。');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        _flushPendingTipIfNeeded();
        final defaultItem = widget.appState.defaultBackground;
        final queue = widget.appState.playQueue;
        final nextItem = widget.appState.nextQueueItem;
        final readyText = widget.appState.playbackReady ? '准备播放' : '未开始';
        final playbackKey = widget.appState.playbackTriggerKey;
        final resetKey = widget.appState.resetTriggerKey;
        return Scaffold(
          appBar: AppBar(
            title: const Text('ControlPage'),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Text(
                    '快捷键：播放下一项(${playbackKey.label}) / 切回默认(${resetKey.label})',
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _switchBackToDefaultBackground,
            icon: const Icon(Icons.home_filled),
            label: const Text('切回默认背景'),
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
                        label: const Text('设置默认背景'),
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
                        label: Text(_addingItem ? '校验中...' : '添加播放文件'),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _startNextPlayback,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('开始播放（下一项）'),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _openStagePage,
                        icon: const Icon(Icons.slideshow),
                        label: const Text('打开舞台页'),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _playlistFileBusy ? null : _importPlaylist,
                        icon: const Icon(Icons.upload_file),
                        label: Text(_playlistFileBusy ? '处理中...' : '导入播放列表'),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _playlistFileBusy ? null : _exportPlaylist,
                        icon: const Icon(Icons.download),
                        label: const Text('导出播放列表'),
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
                        const Text('播放触发按键：'),
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
                        const Text('切回默认按键：'),
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
                  '播放列表（可拖动调整顺序，每次点击“开始播放”或按触发键自动播放下一项）',
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
    final hasDefault = defaultItem != null;
    final text = hasDefault ? '已设置：${defaultItem!.fileName}' : '未设置';
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
                '默认背景：$text',
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
    final nextText = nextItem == null
        ? '无'
        : '${nextItem!.displayTitle}（${nextItem!.displayArtist}）';
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
              '播放状态：$statusText',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text('下一项：$nextText'),
            const SizedBox(height: 4),
            Text('播放触发键：$playbackKeyLabel'),
            const SizedBox(height: 2),
            Text('切回默认键：$resetKeyLabel'),
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
    final mediaInfo = item.type == MediaType.image
        ? '图片 + 音乐：${item.audioPath?.split('/').last ?? '未设置'}'
        : '视频';
    return Material(
      key: key,
      color: const Color(0xFF171717),
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        leading: Icon(item.type == MediaType.video ? Icons.movie : Icons.image),
        title: Text(item.displayTitle),
        subtitle: Text('演唱者：${item.displayArtist}\n$mediaInfo'),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: const Center(
        child: Text('播放列表为空。点击“添加播放文件”开始创建节目单。', textAlign: TextAlign.center),
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
    this.dialogTitle = '添加播放文件',
    this.submitButtonText = '添加并校验',
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
    final path = await _pickFile(
      title: '选择图片',
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
    final path = await _pickFile(
      title: '选择视频',
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
    final path = await _pickFile(
      title: '选择伴奏音乐',
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
                segments: const <ButtonSegment<MediaType>>[
                  ButtonSegment<MediaType>(
                    value: MediaType.image,
                    label: Text('图片'),
                  ),
                  ButtonSegment<MediaType>(
                    value: MediaType.video,
                    label: Text('视频'),
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
                  label: const Text('选择图片（必选）'),
                ),
                if (_imagePath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('图片：$_imagePath'),
                  ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _pickAudio,
                  icon: const Icon(Icons.music_note),
                  label: const Text('选择音乐（必选）'),
                ),
                if (_audioPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('音乐：$_audioPath'),
                  ),
              ] else ...<Widget>[
                FilledButton.tonalIcon(
                  onPressed: _pickVideo,
                  icon: const Icon(Icons.movie),
                  label: const Text('选择视频（必选）'),
                ),
                if (_videoPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('视频：$_videoPath'),
                  ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '节目标题（可选，留空自动生成）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _artistController,
                decoration: const InputDecoration(
                  labelText: '演唱者（可选）',
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
          child: const Text('取消'),
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
