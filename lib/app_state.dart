import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_i18n.dart';

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
    return '';
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
    '3gp',
    '3g2',
    'avi',
    'asf',
    'flv',
    'f4v',
    'mkv',
    'mpeg',
    'mpg',
    'm2ts',
    'mts',
    'm2v',
    'ts',
    'ogv',
    'wmv',
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

  static const List<String> importAccessPickerExtensions = <String>[
    ...mediaPickerExtensions,
    ...audioExtensions,
  ];

  static const int playlistFileSchemaVersion = 1;

  static const String _kDefaultPath = 'default_media_path';
  static const String _kDefaultType = 'default_media_type';
  static const String _kDefaultAudioPath = 'default_media_audio_path';
  static const String _kLocaleCode = 'locale_code';
  static const String _kManagedMediaBaseName = 'default_media';
  static const String _kManagedAudioBaseName = 'default_audio';
  static const String _kManagedDefaultsFolder = 'defaults';

  static Map<String, dynamic> buildPlaylistFilePayload(
    Iterable<MediaItem> items,
  ) {
    return <String, dynamic>{
      'schemaVersion': playlistFileSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'queue': items.map((item) => item.toJson()).toList(),
    };
  }

  static List<MediaItem>? parsePlaylistFilePayload(dynamic raw) {
    if (raw is List) {
      return _parseQueueList(raw);
    }
    if (raw is! Map) {
      return null;
    }
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final queueRaw = map['queue'];
    if (queueRaw is! List) {
      return null;
    }
    return _parseQueueList(queueRaw);
  }

  static List<MediaItem> _parseQueueList(List<dynamic> rawQueue) {
    final parsed = <MediaItem>[];
    for (final rawItem in rawQueue) {
      final item = MediaItem.fromJson(rawItem);
      if (item != null) {
        parsed.add(item);
      }
    }
    return parsed;
  }

  SharedPreferences? _prefs;
  MediaItem? _defaultBackground;
  MediaItem? _stageOverride;
  Locale _locale = AppI18n.normalizeLocale(PlatformDispatcher.instance.locale);

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

  Locale get locale => _locale;

  String get localeStorageCode => AppI18n.localeStorageCode(_locale);

  MediaItem? get nextQueueItem {
    if (_playQueue.isEmpty) {
      return null;
    }
    final safeIndex = _nextPlayIndex % _playQueue.length;
    return _playQueue[safeIndex];
  }

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _readLocaleFromPrefs();
    await _readDefaultFromPrefs();
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    final normalized = AppI18n.normalizeLocale(locale);
    if (_locale == normalized) {
      return;
    }
    _locale = normalized;
    notifyListeners();
    final prefs = await _ensurePrefs();
    await prefs.setString(_kLocaleCode, AppI18n.localeStorageCode(normalized));
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
    final persistedItem = await _copyDefaultItemIntoManagedStorage(item);
    _defaultBackground = persistedItem;
    await _persistDefaultToPrefs(persistedItem);
    notifyListeners();
  }

  Future<void> clearDefaultBackground() async {
    _defaultBackground = null;
    await _clearPersistedDefaultFromPrefs();
    await _deleteManagedDefaultCopies();
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

  int replacePlayQueue(Iterable<MediaItem> items) {
    _playQueue.clear();
    for (final item in items) {
      _playQueue.add(_normalizedQueueItem(item));
    }
    _nextPlayIndex = 0;
    _playbackReady = false;
    _normalizeNextIndex();
    notifyListeners();
    return _playQueue.length;
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

  Future<void> _clearPersistedDefaultFromPrefs() async {
    final prefs = await _ensurePrefs();
    await prefs.remove(_kDefaultPath);
    await prefs.remove(_kDefaultType);
    await prefs.remove(_kDefaultAudioPath);
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

  Future<void> _readDefaultFromPrefs() async {
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
      await _clearPersistedDefaultFromPrefs();
      return;
    }

    final audioPath = prefs.getString(_kDefaultAudioPath);
    if (!_isReadableFile(path)) {
      _defaultBackground = null;
      await _clearPersistedDefaultFromPrefs();
      return;
    }
    final resolvedAudioPath =
        mediaType == MediaType.image &&
            audioPath != null &&
            audioPath.isNotEmpty &&
            _isReadableFile(audioPath)
        ? audioPath
        : null;
    _defaultBackground = MediaItem(
      type: mediaType,
      path: path,
      audioPath: mediaType == MediaType.image ? resolvedAudioPath : null,
    );
  }

  void _readLocaleFromPrefs() {
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }
    final rawCode = prefs.getString(_kLocaleCode);
    if (rawCode == null || rawCode.trim().isEmpty) {
      _locale = AppI18n.normalizeLocale(PlatformDispatcher.instance.locale);
      return;
    }
    _locale = AppI18n.localeFromStorageCode(rawCode);
  }

  bool _isReadableFile(String path) {
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

  Future<MediaItem> _copyDefaultItemIntoManagedStorage(MediaItem item) async {
    final managedPath = await _copySourceIntoManagedStorage(
      sourcePath: item.path,
      baseName: _kManagedMediaBaseName,
    );
    String? managedAudioPath;
    if (item.type == MediaType.image && item.hasAudioPath) {
      managedAudioPath = await _copySourceIntoManagedStorage(
        sourcePath: item.audioPath!,
        baseName: _kManagedAudioBaseName,
      );
    } else {
      await _deleteManagedCopies(baseName: _kManagedAudioBaseName);
    }
    return MediaItem(
      type: item.type,
      path: managedPath,
      audioPath: item.type == MediaType.image ? managedAudioPath : null,
      title: item.title,
      artist: item.artist,
    );
  }

  Future<String> _copySourceIntoManagedStorage({
    required String sourcePath,
    required String baseName,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('default media does not exist', sourcePath);
    }
    final targetDir = await _ensureManagedDefaultsDirectory();
    final extension = _normalizedExtension(sourcePath);
    final fileName = extension.isEmpty ? baseName : '$baseName.$extension';
    final targetPath = '${targetDir.path}${Platform.pathSeparator}$fileName';

    if (sourceFile.absolute.path == File(targetPath).absolute.path) {
      return targetPath;
    }

    await _deleteManagedCopies(baseName: baseName, targetDirectory: targetDir);
    await sourceFile.copy(targetPath);
    return targetPath;
  }

  Future<Directory> _ensureManagedDefaultsDirectory() async {
    final rootPath = _managedDataRootPath();
    final path = '$rootPath${Platform.pathSeparator}$_kManagedDefaultsFolder';
    final directory = Directory(path);
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _deleteManagedDefaultCopies() async {
    await _deleteManagedCopies(baseName: _kManagedMediaBaseName);
    await _deleteManagedCopies(baseName: _kManagedAudioBaseName);
  }

  Future<void> _deleteManagedCopies({
    required String baseName,
    Directory? targetDirectory,
  }) async {
    final directory =
        targetDirectory ??
        Directory(
          '${_managedDataRootPath()}${Platform.pathSeparator}$_kManagedDefaultsFolder',
        );
    if (!await directory.exists()) {
      return;
    }
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name == baseName || name.startsWith('$baseName.')) {
        await entity.delete();
      }
    }
  }

  String _managedDataRootPath() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return '${Directory.systemTemp.path}${Platform.pathSeparator}homeparty_backdrop';
    }
    if (Platform.isMacOS) {
      return '$home${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}homeparty_backdrop';
    }
    return '$home${Platform.pathSeparator}.homeparty_backdrop';
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
    final baseTitle = _normalizedTextOrNull(preferredTitle) ?? _queueBaseTitle();
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

  String _queueBaseTitle() {
    return _locale.languageCode == 'zh' ? '节目' : 'Program';
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

  Map<String, dynamic> buildQueueSnapshot() {
    return <String, dynamic>{
      'queue': _playQueue.map((item) => item.toJson()).toList(),
      'nextPlayIndex': _nextPlayIndex,
      'currentQueueIndex': _currentQueueIndex(),
      'playbackReady': _playbackReady,
    };
  }

  int? _currentQueueIndex() {
    final stageItem = _stageOverride;
    if (stageItem == null || _playQueue.isEmpty) {
      return null;
    }
    for (var i = 0; i < _playQueue.length; i++) {
      if (_isSameMediaSource(_playQueue[i], stageItem)) {
        return i;
      }
    }
    return null;
  }
}
