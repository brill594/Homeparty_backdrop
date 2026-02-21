import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MediaType { image, video }

enum ResetToDefaultResult { switched, alreadyUsingDefault, defaultNotSet }

enum StartPlaybackResult { played, queueEmpty }

enum LetterTriggerKey {
  a,
  b,
  c,
  d,
  e,
  f,
  g,
  h,
  i,
  j,
  k,
  l,
  m,
  n,
  o,
  p,
  q,
  r,
  s,
  t,
  u,
  v,
  w,
  x,
  y,
  z,
}

const List<PhysicalKeyboardKey> _letterPhysicalKeys = <PhysicalKeyboardKey>[
  PhysicalKeyboardKey.keyA,
  PhysicalKeyboardKey.keyB,
  PhysicalKeyboardKey.keyC,
  PhysicalKeyboardKey.keyD,
  PhysicalKeyboardKey.keyE,
  PhysicalKeyboardKey.keyF,
  PhysicalKeyboardKey.keyG,
  PhysicalKeyboardKey.keyH,
  PhysicalKeyboardKey.keyI,
  PhysicalKeyboardKey.keyJ,
  PhysicalKeyboardKey.keyK,
  PhysicalKeyboardKey.keyL,
  PhysicalKeyboardKey.keyM,
  PhysicalKeyboardKey.keyN,
  PhysicalKeyboardKey.keyO,
  PhysicalKeyboardKey.keyP,
  PhysicalKeyboardKey.keyQ,
  PhysicalKeyboardKey.keyR,
  PhysicalKeyboardKey.keyS,
  PhysicalKeyboardKey.keyT,
  PhysicalKeyboardKey.keyU,
  PhysicalKeyboardKey.keyV,
  PhysicalKeyboardKey.keyW,
  PhysicalKeyboardKey.keyX,
  PhysicalKeyboardKey.keyY,
  PhysicalKeyboardKey.keyZ,
];

extension LetterTriggerKeyX on LetterTriggerKey {
  String get label {
    return name.toUpperCase();
  }

  PhysicalKeyboardKey get physicalKey {
    return _letterPhysicalKeys[index];
  }

  static LetterTriggerKey? fromPhysicalKey(PhysicalKeyboardKey key) {
    final index = _letterPhysicalKeys.indexOf(key);
    if (index < 0) {
      return null;
    }
    return LetterTriggerKey.values[index];
  }
}

@immutable
class MediaItem {
  const MediaItem({
    required this.type,
    required this.path,
    this.audioPath,
    this.title,
    this.artist,
  });

  final MediaType type;
  final String path;

  // Optional. Only used when [type] is image.
  final String? audioPath;
  final String? title;
  final String? artist;

  bool get hasAudioPath => audioPath != null && audioPath!.isNotEmpty;

  bool get hasTitle => title != null && title!.trim().isNotEmpty;

  bool get hasArtist => artist != null && artist!.trim().isNotEmpty;

  bool get existsOnDisk => File(path).existsSync();

  String get fileName => path.split(Platform.pathSeparator).last;

  String get displayTitle {
    if (hasTitle) {
      return title!.trim();
    }
    return fileName;
  }

  String get displayArtist {
    if (hasArtist) {
      return artist!.trim();
    }
    return '未填写';
  }

  String get typeLabel => type == MediaType.image ? 'Image' : 'Video';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.name,
      'path': path,
      'audioPath': audioPath,
      'title': title,
      'artist': artist,
    };
  }

  static MediaItem? fromJson(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final typeName = map['type']?.toString();
    final path = map['path']?.toString();
    if (typeName == null || path == null || path.isEmpty) {
      return null;
    }

    MediaType? mediaType;
    for (final value in MediaType.values) {
      if (value.name == typeName) {
        mediaType = value;
        break;
      }
    }
    if (mediaType == null) {
      return null;
    }

    final rawAudioPath = map['audioPath']?.toString();
    final audioPath = rawAudioPath == null || rawAudioPath.isEmpty
        ? null
        : rawAudioPath;
    final rawTitle = map['title']?.toString();
    final rawArtist = map['artist']?.toString();
    return MediaItem(
      type: mediaType,
      path: path,
      audioPath: audioPath,
      title: rawTitle == null || rawTitle.trim().isEmpty ? null : rawTitle,
      artist: rawArtist == null || rawArtist.trim().isEmpty ? null : rawArtist,
    );
  }
}

class AppState extends ChangeNotifier {
  static const List<String> imageExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
    'bmp',
    'gif',
    'heic',
  ];

  static const List<String> videoExtensions = <String>[
    'mp4',
    'mov',
    'm4v',
    'avi',
    'mkv',
    'webm',
  ];

  static const List<String> audioExtensions = <String>[
    'mp3',
    'aac',
    'm4a',
    'wav',
    'flac',
    'ogg',
  ];

  static const List<String> mediaPickerExtensions = <String>[
    ...imageExtensions,
    ...videoExtensions,
  ];

  static const String _kDefaultPath = 'default_media_path';
  static const String _kDefaultType = 'default_media_type';
  static const String _kDefaultAudioPath = 'default_media_audio_path';
  static const String _kQueueDefaultTitle = '节目';

  SharedPreferences? _prefs;
  MediaItem? _defaultBackground;
  MediaItem? _stageOverride;

  final List<MediaItem> _playQueue = <MediaItem>[];
  int _nextPlayIndex = 0;
  bool _playbackReady = false;
  LetterTriggerKey _playbackTriggerKey = LetterTriggerKey.n;
  LetterTriggerKey _resetTriggerKey = LetterTriggerKey.b;
  int _playSignalVersion = 0;

  MediaItem? get defaultBackground => _defaultBackground;

  MediaItem? get stageOverride => _stageOverride;

  bool get isUsingStageOverride => _stageOverride != null;

  MediaItem? get currentStageMedia => _stageOverride ?? _defaultBackground;

  List<MediaItem> get playQueue => List<MediaItem>.unmodifiable(_playQueue);

  bool get playbackReady => _playbackReady;

  int get nextPlayIndex => _nextPlayIndex;

  LetterTriggerKey get playbackTriggerKey => _playbackTriggerKey;

  LetterTriggerKey get resetTriggerKey => _resetTriggerKey;

  int get playSignalVersion => _playSignalVersion;

  MediaItem? get nextQueueItem {
    if (_playQueue.isEmpty) {
      return null;
    }
    final safeIndex = _nextPlayIndex % _playQueue.length;
    return _playQueue[safeIndex];
  }

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _readDefaultFromPrefs();
    notifyListeners();
  }

  bool setPlaybackTriggerKey(LetterTriggerKey key) {
    if (key == _resetTriggerKey) {
      return false;
    }
    if (_playbackTriggerKey == key) {
      return true;
    }
    _playbackTriggerKey = key;
    notifyListeners();
    return true;
  }

  bool setResetTriggerKey(LetterTriggerKey key) {
    if (key == _playbackTriggerKey) {
      return false;
    }
    if (_resetTriggerKey == key) {
      return true;
    }
    _resetTriggerKey = key;
    notifyListeners();
    return true;
  }

  MediaItem? createItemFromPath(
    String path, {
    String? audioPath,
    String? title,
    String? artist,
  }) {
    final extension = _normalizedExtension(path);
    if (imageExtensions.contains(extension)) {
      return MediaItem(
        type: MediaType.image,
        path: path,
        audioPath: audioPath,
        title: title,
        artist: artist,
      );
    }
    if (videoExtensions.contains(extension)) {
      return MediaItem(
        type: MediaType.video,
        path: path,
        title: title,
        artist: artist,
      );
    }
    return null;
  }

  Future<void> setDefaultBackground(MediaItem item) async {
    _defaultBackground = item;
    await _persistDefaultToPrefs(item);
    notifyListeners();
  }

  Future<void> clearDefaultBackground() async {
    _defaultBackground = null;
    final prefs = await _ensurePrefs();
    await prefs.remove(_kDefaultPath);
    await prefs.remove(_kDefaultType);
    await prefs.remove(_kDefaultAudioPath);
    notifyListeners();
  }

  MediaItem addQueueItem(MediaItem item) {
    _playQueue.removeWhere((oldItem) {
      return oldItem.type == item.type &&
          oldItem.path == item.path &&
          oldItem.audioPath == item.audioPath;
    });
    final normalizedItem = _normalizedQueueItem(item);
    _playQueue.add(normalizedItem);
    _normalizeNextIndex();
    notifyListeners();
    return normalizedItem;
  }

  bool removeQueueItemAt(int index) {
    if (index < 0 || index >= _playQueue.length) {
      return false;
    }
    _playQueue.removeAt(index);
    if (_playQueue.isEmpty) {
      _nextPlayIndex = 0;
    } else if (index < _nextPlayIndex) {
      _nextPlayIndex -= 1;
    }
    _normalizeNextIndex();
    notifyListeners();
    return true;
  }

  MediaItem? updateQueueItemAt(int index, MediaItem nextItem) {
    if (index < 0 || index >= _playQueue.length) {
      return null;
    }
    final updatedItem = _normalizedQueueItem(nextItem, excludeIndex: index);
    final currentStage = _stageOverride;
    final oldItem = _playQueue[index];
    _playQueue[index] = updatedItem;
    if (currentStage != null && _isSameMediaSource(currentStage, oldItem)) {
      _stageOverride = updatedItem;
    }
    notifyListeners();
    return updatedItem;
  }

  void reorderPlayQueue(int oldIndex, int newIndex) {
    if (_playQueue.isEmpty || oldIndex < 0 || oldIndex >= _playQueue.length) {
      return;
    }
    if (newIndex < 0) {
      newIndex = 0;
    }
    if (newIndex > _playQueue.length) {
      newIndex = _playQueue.length;
    }
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (newIndex == oldIndex) {
      return;
    }
    final item = _playQueue.removeAt(oldIndex);
    _playQueue.insert(newIndex, item);
    _normalizeNextIndex();
    notifyListeners();
  }

  void playOnStage(MediaItem item, {bool fromQueue = false}) {
    _stageOverride = item;
    _playSignalVersion++;
    if (!fromQueue) {
      addQueueItem(item);
      return;
    }
    notifyListeners();
  }

  StartPlaybackResult startAndPlayNext() {
    if (_playQueue.isEmpty) {
      return StartPlaybackResult.queueEmpty;
    }

    _playbackReady = true;
    _normalizeNextIndex();
    final next = _playQueue[_nextPlayIndex];
    _stageOverride = next;
    _playSignalVersion++;
    _nextPlayIndex = (_nextPlayIndex + 1) % _playQueue.length;
    notifyListeners();
    return StartPlaybackResult.played;
  }

  ResetToDefaultResult resetToDefaultBackground() {
    if (_defaultBackground == null) {
      return ResetToDefaultResult.defaultNotSet;
    }
    if (_stageOverride == null) {
      return ResetToDefaultResult.alreadyUsingDefault;
    }
    _stageOverride = null;
    notifyListeners();
    return ResetToDefaultResult.switched;
  }

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> _persistDefaultToPrefs(MediaItem item) async {
    final prefs = await _ensurePrefs();
    await prefs.setString(_kDefaultPath, item.path);
    await prefs.setString(_kDefaultType, item.type.name);
    if (item.type == MediaType.image && item.hasAudioPath) {
      await prefs.setString(_kDefaultAudioPath, item.audioPath!);
    } else {
      await prefs.remove(_kDefaultAudioPath);
    }
  }

  void _readDefaultFromPrefs() {
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }

    final path = prefs.getString(_kDefaultPath);
    final typeName = prefs.getString(_kDefaultType);
    if (path == null || path.isEmpty || typeName == null) {
      _defaultBackground = null;
      return;
    }

    final mediaType = _mediaTypeFromName(typeName);
    if (mediaType == null) {
      _defaultBackground = null;
      return;
    }

    final audioPath = prefs.getString(_kDefaultAudioPath);
    _defaultBackground = MediaItem(
      type: mediaType,
      path: path,
      audioPath: mediaType == MediaType.image ? audioPath : null,
    );
  }

  void _normalizeNextIndex() {
    if (_playQueue.isEmpty) {
      _nextPlayIndex = 0;
      return;
    }
    _nextPlayIndex = _nextPlayIndex % _playQueue.length;
  }

  MediaItem _normalizedQueueItem(MediaItem item, {int? excludeIndex}) {
    final resolvedTitle = _resolveUniqueQueueTitle(
      item.title,
      excludeIndex: excludeIndex,
    );
    final resolvedArtist = _normalizedTextOrNull(item.artist);
    return MediaItem(
      type: item.type,
      path: item.path,
      audioPath: item.audioPath,
      title: resolvedTitle,
      artist: resolvedArtist,
    );
  }

  String _resolveUniqueQueueTitle(String? preferredTitle, {int? excludeIndex}) {
    final baseTitle =
        _normalizedTextOrNull(preferredTitle) ?? _kQueueDefaultTitle;
    final usedTitles = <String>{};
    for (var i = 0; i < _playQueue.length; i++) {
      if (excludeIndex != null && i == excludeIndex) {
        continue;
      }
      usedTitles.add(_playQueue[i].displayTitle);
    }

    if (!usedTitles.contains(baseTitle)) {
      return baseTitle;
    }

    var suffix = 2;
    while (usedTitles.contains('$baseTitle$suffix')) {
      suffix++;
    }
    return '$baseTitle$suffix';
  }

  String? _normalizedTextOrNull(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  bool _isSameMediaSource(MediaItem a, MediaItem b) {
    return a.type == b.type && a.path == b.path && a.audioPath == b.audioPath;
  }

  String _normalizedExtension(String path) {
    final parts = path.split('.');
    if (parts.length < 2) {
      return '';
    }
    return parts.last.toLowerCase();
  }

  MediaType? _mediaTypeFromName(String typeName) {
    for (final type in MediaType.values) {
      if (type.name == typeName) {
        return type;
      }
    }
    return null;
  }
}
