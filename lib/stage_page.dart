import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';

class StagePage extends StatefulWidget {
  const StagePage({super.key, required this.appState});

  final AppState appState;

  @override
  State<StagePage> createState() => _StagePageState();
}

class _StagePageState extends State<StagePage> {
  static const Duration _overlayAutoHideDelay = Duration(seconds: 3);

  final AudioPlayer _audioPlayer = AudioPlayer();
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'stage_keyboard');

  VideoPlayerController? _videoController;
  MediaItem? _activeMedia;
  bool _activeUsingOverride = false;
  int _activePlaySignal = -1;

  bool _isFullscreen = false;
  bool _isVideoPlaying = false;
  bool _isVideoLooping = true;
  String? _playbackNotice;
  int _syncToken = 0;
  Timer? _overlayHideTimer;
  bool _overlayVisible = true;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onAppStateChanged);
    unawaited(_configureStageWindowAtLaunch());
    unawaited(WakelockPlus.enable());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
    _restartOverlayAutoHideTimer();
    _onAppStateChanged();
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    _syncToken++;

    final oldVideoController = _videoController;
    _videoController = null;
    oldVideoController?.removeListener(_onVideoStateChanged);
    oldVideoController?.dispose();

    _audioPlayer.dispose();
    _keyboardFocusNode.dispose();
    _overlayHideTimer?.cancel();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _configureStageWindowAtLaunch() async {
    await windowManager.show();
    await windowManager.focus();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    _onUserInteraction();
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.space) {
      unawaited(_toggleVideoPauseResume());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(_setFullscreen(false));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f11) {
      unawaited(_setFullscreen(true));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _setFullscreen(bool fullscreen) async {
    await windowManager.setFullScreen(fullscreen);
    final fullScreen = await windowManager.isFullScreen();
    if (!mounted) {
      return;
    }
    setState(() {
      _isFullscreen = fullScreen;
    });
  }

  void _onAppStateChanged() {
    final nextMedia = widget.appState.currentStageMedia;
    final nextUsingOverride = widget.appState.isUsingStageOverride;
    final nextPlaySignal = widget.appState.playSignalVersion;
    final unchanged =
        _isSameMedia(_activeMedia, nextMedia) &&
        _activeUsingOverride == nextUsingOverride &&
        _activePlaySignal == nextPlaySignal;
    if (unchanged) {
      return;
    }

    _activeMedia = nextMedia;
    _activeUsingOverride = nextUsingOverride;
    _activePlaySignal = nextPlaySignal;
    _onUserInteraction();

    final token = ++_syncToken;
    unawaited(_switchPlaybackForMedia(nextMedia, token));
  }

  bool _isSameMedia(MediaItem? a, MediaItem? b) {
    if (a == null && b == null) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    return a.type == b.type && a.path == b.path && a.audioPath == b.audioPath;
  }

  Future<void> _switchPlaybackForMedia(MediaItem? media, int token) async {
    await _stopAndDisposePlaybackResources();

    if (!mounted || token != _syncToken) {
      return;
    }
    _playbackNotice = null;

    if (media == null) {
      setState(() {});
      return;
    }

    if (media.type == MediaType.video) {
      final controller = VideoPlayerController.file(File(media.path));
      try {
        await controller.initialize();
        if (!mounted || token != _syncToken) {
          await controller.dispose();
          return;
        }
        controller.addListener(_onVideoStateChanged);
        await controller.setLooping(_isVideoLooping);
        await controller.play();
        _videoController = controller;
        _isVideoPlaying = true;
      } catch (_) {
        _playbackNotice = '视频初始化失败，请检查文件格式或系统解码能力。';
        await controller.dispose();
      }
    } else if (media.hasAudioPath) {
      final audioPath = media.audioPath!;
      try {
        await _audioPlayer.setFilePath(audioPath);
        await _audioPlayer.setLoopMode(LoopMode.one);
        await _audioPlayer.play();
      } catch (_) {
        _playbackNotice = '伴奏播放失败，当前已静音。';
        await _audioPlayer.stop();
      }
    }

    if (!mounted || token != _syncToken) {
      return;
    }
    setState(() {});
  }

  Future<void> _stopAndDisposePlaybackResources() async {
    final oldVideoController = _videoController;
    _videoController = null;
    if (oldVideoController != null) {
      oldVideoController.removeListener(_onVideoStateChanged);
      await oldVideoController.pause();
      await oldVideoController.dispose();
    }

    _isVideoPlaying = false;
    await _audioPlayer.stop();
  }

  void _onVideoStateChanged() {
    final controller = _videoController;
    if (controller == null) {
      return;
    }
    final playing = controller.value.isPlaying;
    if (playing == _isVideoPlaying) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isVideoPlaying = playing;
    });
  }

  Future<void> _toggleVideoPauseResume() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isVideoPlaying = controller.value.isPlaying;
    });
  }

  Future<void> _toggleVideoLooping() async {
    final next = !_isVideoLooping;
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      await controller.setLooping(next);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isVideoLooping = next;
    });
  }

  void _switchToDefaultBackground() {
    _onUserInteraction();
    final result = widget.appState.resetToDefaultBackground();
    if (result == ResetToDefaultResult.defaultNotSet) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先设置默认背景。')));
    }
  }

  void _onUserInteraction() {
    _restartOverlayAutoHideTimer();
    if (_overlayVisible || !mounted) {
      return;
    }
    setState(() {
      _overlayVisible = true;
    });
  }

  void _restartOverlayAutoHideTimer() {
    _overlayHideTimer?.cancel();
    _overlayHideTimer = Timer(_overlayAutoHideDelay, () {
      if (!mounted || !_overlayVisible) {
        return;
      }
      setState(() {
        _overlayVisible = false;
      });
    });
  }

  Widget _buildAutoHideOverlay(Widget child) {
    return AnimatedOpacity(
      opacity: _overlayVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(ignoring: !_overlayVisible, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.appState.currentStageMedia;
    final isVideo = media?.type == MediaType.video;
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: MouseRegion(
        onEnter: (_) => _onUserInteraction(),
        onHover: (_) => _onUserInteraction(),
        cursor: SystemMouseCursors.none,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _onUserInteraction(),
          onPanDown: (_) => _onUserInteraction(),
          onTap: _keyboardFocusNode.requestFocus,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: <Widget>[
                Positioned.fill(child: _buildStageContent(media)),
                Positioned(
                  top: 20,
                  left: 20,
                  child: _buildAutoHideOverlay(
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        FilledButton.tonal(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('返回控制台'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _setFullscreen(!_isFullscreen),
                          child: Text(
                            _isFullscreen ? '退出全屏(Esc)' : '进入全屏(F11)',
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: _switchToDefaultBackground,
                          child: const Text('切回默认背景'),
                        ),
                        if (isVideo) ...<Widget>[
                          FilledButton.tonal(
                            onPressed: _toggleVideoPauseResume,
                            child: Text(
                              _isVideoPlaying ? '暂停(Space)' : '继续(Space)',
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: _toggleVideoLooping,
                            child: Text(_isVideoLooping ? '循环: 开' : '循环: 关'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: _buildAutoHideOverlay(_buildMediaInfo(media)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStageContent(MediaItem? media) {
    if (media == null) {
      return const _StageEmpty(
        title: 'No background configured',
        subtitle: 'Set a default media in ControlPage first.',
      );
    }

    if (!media.existsOnDisk) {
      return _StageEmpty(title: 'File not found', subtitle: media.path);
    }

    if (media.type == MediaType.image) {
      return Image.file(
        File(media.path),
        fit: BoxFit.cover,
        errorBuilder: (_, error, stackTrace) {
          return _StageEmpty(title: 'Cannot open image', subtitle: media.path);
        },
      );
    }

    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      if (_playbackNotice != null) {
        return _StageEmpty(title: '视频不可播放', subtitle: _playbackNotice!);
      }
      return const Center(child: CircularProgressIndicator());
    }

    final size = controller.value.size;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaInfo(MediaItem? media) {
    final title = media == null
        ? 'Now showing: none'
        : 'Now showing: ${media.fileName}';
    final subtitle = media == null
        ? 'Waiting for media from ControlPage.'
        : media.type == MediaType.image
        ? media.hasAudioPath
              ? 'Type: image | Audio: ${media.audioPath}'
              : 'Type: image | Audio: mute'
        : 'Type: video | Loop: ${_isVideoLooping ? 'on' : 'off'} | Space: pause/resume';
    final keyTips =
        'Hotkeys: Next(${widget.appState.playbackTriggerKey.label}) | Default(${widget.appState.resetTriggerKey.label})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_playbackNotice != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                _playbackNotice!,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (_playbackNotice != null) const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 2),
                Text(keyTips, style: const TextStyle(color: Colors.white60)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StageEmpty extends StatelessWidget {
  const _StageEmpty({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
