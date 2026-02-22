import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppI18n {
  const AppI18n(this.locale);

  final Locale locale;

  static const Locale englishLocale = Locale('en');
  static const Locale simplifiedChineseLocale = Locale('zh', 'CN');

  static const List<Locale> supportedLocales = <Locale>[
    englishLocale,
    simplifiedChineseLocale,
  ];

  static const LocalizationsDelegate<AppI18n> delegate = _AppI18nDelegate();

  static AppI18n of(BuildContext context) {
    final instance = Localizations.of<AppI18n>(context, AppI18n);
    assert(instance != null, 'AppI18n is not available in this context.');
    return instance!;
  }

  static Locale normalizeLocale(Locale locale) {
    if (locale.languageCode.toLowerCase() == 'zh') {
      return simplifiedChineseLocale;
    }
    return englishLocale;
  }

  static String localeStorageCode(Locale locale) {
    return normalizeLocale(locale).languageCode == 'zh' ? 'zh_CN' : 'en';
  }

  static Locale localeFromStorageCode(String? rawCode) {
    if (rawCode == null || rawCode.trim().isEmpty) {
      return englishLocale;
    }
    final code = rawCode.trim().toLowerCase();
    if (code == 'zh' ||
        code == 'zh_cn' ||
        code == 'zh-hans' ||
        code == 'zh_hans') {
      return simplifiedChineseLocale;
    }
    return englishLocale;
  }

  static String tr(
    Locale locale,
    String key, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) {
    return AppI18n(normalizeLocale(locale)).t(key, params);
  }

  bool get _useChinese => locale.languageCode == 'zh';

  String t(
    String key, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) {
    final value =
        (_useChinese ? _zhValues : _enValues)[key] ?? _enValues[key] ?? key;
    if (params.isEmpty) {
      return value;
    }
    var text = value;
    for (final entry in params.entries) {
      text = text.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return text;
  }
}

class _AppI18nDelegate extends LocalizationsDelegate<AppI18n> {
  const _AppI18nDelegate();

  @override
  bool isSupported(Locale locale) {
    return locale.languageCode == 'en' || locale.languageCode == 'zh';
  }

  @override
  Future<AppI18n> load(Locale locale) {
    return SynchronousFuture<AppI18n>(AppI18n(AppI18n.normalizeLocale(locale)));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppI18n> old) {
    return false;
  }
}

extension AppI18nX on BuildContext {
  AppI18n get l10n => AppI18n.of(this);
}

const Map<String, String> _enValues = <String, String>{
  'language': 'Language',
  'languageEnglish': 'English',
  'languageSimplifiedChinese': 'Simplified Chinese',
  'homepartyControlTitle': 'HomeParty Control',
  'playlistManagerTitle': 'Playlist Manager',
  'stagePlaylistManagerTitle': 'Stage Playlist Manager',
  'childWindowOnly': 'Only sub-windows are supported.',
  'addInvalidProgramData': 'Add failed: invalid program data.',
  'editInvalidArgs': 'Edit failed: invalid arguments.',
  'editItemMissing': 'Edit failed: item does not exist.',
  'deleteInvalidArgs': 'Delete failed: invalid arguments.',
  'deleteItemMissing': 'Delete failed: item does not exist.',
  'reorderInvalidArgs': 'Reorder failed: invalid arguments.',
  'importInvalidArgs': 'Import failed: invalid arguments.',
  'unknownAction': 'Unknown action: {method}',
  'setDefaultFirst': 'Please set a default background first.',
  'queueEmptyAddFirst': 'Playlist is empty. Add a program first.',
  'chooseDefaultBackgroundDialogTitle':
      'Choose default background (image or video)',
  'unsupportedMediaFormat': 'Unsupported media format.',
  'fileMissingCannotSetDefault':
      'File does not exist. Cannot set default background.',
  'defaultBackgroundSet': 'Default background set: {file}',
  'setDefaultBackgroundFailed': 'Failed to set default background: {error}',
  'addFailedTypeMismatch':
      'Add failed: file type does not match selected playback type.',
  'itemAdded': 'Added: {title} (Artist: {artist})',
  'editPlaybackItemDialogTitle': 'Edit playback item',
  'saveAndValidate': 'Save and validate',
  'editFailedTypeMismatch':
      'Edit failed: file type does not match selected playback type.',
  'editFailedMissingItem': 'Edit failed: item no longer exists.',
  'itemUpdated': 'Updated: {title} (Artist: {artist})',
  'itemDeleted': 'Deleted: {title}',
  'mediaMissingRejectAdd': 'Media file does not exist. Add rejected.',
  'imageNeedsAudioRejectAdd':
      'Image type must provide accompaniment audio. Add rejected.',
  'audioMissingRejectAdd': 'Audio file does not exist. Add rejected.',
  'imageEmptyRejectAdd': 'Image file is empty. Add rejected.',
  'imageDecodeRejectAdd': 'Image cannot be decoded. Add rejected.',
  'audioDecodeRejectAdd': 'Audio cannot be played. Add rejected.',
  'videoInitRejectAdd': 'Video initialization failed. Add rejected.',
  'nowPlaying': 'Now playing: {title} (Artist: {artist})',
  'queueEmptyCannotExport': 'Playlist is empty and cannot be exported.',
  'exportPlaylistDialogTitle': 'Export playlist',
  'exportSuccess': 'Export successful: {path}',
  'exportFailed': 'Export failed: {error}',
  'importPlaylistDialogTitle': 'Import playlist',
  'readFilePathFailed': 'Failed to read file path.',
  'importInvalidFormat': 'Import failed: invalid file format.',
  'importNoItems': 'Import failed: no valid items in file.',
  'importCancelledNoAccess':
      'Import canceled: media file authorization was not completed.',
  'importStillUnauthorized':
      'Import failed: {count} files are still unauthorized. Please multi-select these files in the authorization window.',
  'importCompleted': 'Import completed: {count} items.',
  'importFailed': 'Import failed: {error}',
  'fileAccessRequiredTitle': 'System file access required',
  'importUnauthorizedFilesDialog':
      'The imported list references {count} unauthorized files (e.g. {sampleNames}{suffix}).\n\nClick "Authorize" and then hold Command in the system dialog to select these media files.',
  'cancel': 'Cancel',
  'authorize': 'Authorize',
  'authorizeImportDialogTitle':
      'Authorize media files for imported playlist (multi-select)',
  'playbackKeyConflict':
      'Playback trigger key cannot be the same as reset key.',
  'resetKeyConflict': 'Reset key cannot be the same as playback trigger key.',
  'readyToPlay': 'Ready',
  'notStarted': 'Not started',
  'controlPageTitle': 'Control',
  'shortcutHint': 'Shortcuts: Play next ({playKey}) / Reset default ({resetKey})',
  'switchToDefaultBackground': 'Switch to default background',
  'setDefaultBackground': 'Set default background',
  'validating': 'Validating...',
  'addPlayableFile': 'Add playable file',
  'startPlaybackNext': 'Start playback (next item)',
  'openStagePage': 'Open stage page',
  'processing': 'Processing...',
  'importPlaylist': 'Import playlist',
  'exportPlaylist': 'Export playlist',
  'playbackTriggerKey': 'Playback trigger key:',
  'resetDefaultKey': 'Reset default key:',
  'playlistHelp':
      'Playlist (drag to reorder, each click on "Start playback" or trigger key plays the next item)',
  'defaultSet': 'Set: {file}',
  'notSet': 'Not set',
  'defaultBackgroundStatus': 'Default background: {text}',
  'none': 'None',
  'playbackStatus': 'Playback status: {status}',
  'nextItem': 'Next item: {next}',
  'playbackTriggerKeyValue': 'Playback trigger key: {key}',
  'resetDefaultKeyValue': 'Reset default key: {key}',
  'imageWithAudio': 'Image + Audio: {audio}',
  'videoType': 'Video',
  'artistValue': 'Artist: {artist}',
  'edit': 'Edit',
  'delete': 'Delete',
  'emptyQueueHintControl':
      'Playlist is empty. Click "Add playable file" to create one.',
  'addPlayableDialogTitle': 'Add playable file',
  'addAndValidate': 'Add and validate',
  'pickImage': 'Choose image',
  'pickVideo': 'Choose video',
  'pickAudio': 'Choose accompaniment audio',
  'imageOption': 'Image',
  'videoOption': 'Video',
  'selectImageRequired': 'Choose image (required)',
  'imagePath': 'Image: {path}',
  'selectAudioRequired': 'Choose audio (required)',
  'audioPath': 'Audio: {path}',
  'selectVideoRequired': 'Choose video (required)',
  'videoPath': 'Video: {path}',
  'programTitleOptional': 'Program title (optional, auto-generated if empty)',
  'artistOptional': 'Artist (optional)',
  'videoInitCheckFormat':
      'Video initialization failed. Please check file format or system decoding.',
  'audioPlaybackMuted': 'Audio playback failed. Output is muted.',
  'programEndedNoDefault':
      'Program playback ended, but default background is not set yet.',
  'videoFallbackSwitching':
      'No video output detected. Switching to compatibility mode...',
  'backToControl': 'Back to control',
  'exitFullscreenEsc': 'Exit fullscreen (Esc)',
  'enterFullscreenF11': 'Enter fullscreen',
  'pauseSpace': 'Pause (Space)',
  'resumeSpace': 'Resume (Space)',
  'noBackgroundConfigured': 'No background configured',
  'setDefaultInControlFirst':
      'Set a default media in Control page first.',
  'fileNotFound': 'File not found',
  'cannotOpenImage': 'Cannot open image',
  'videoUnavailable': 'Video unavailable',
  'waitingForProgram': 'Waiting for program from control page.',
  'mediaTypeImageWithAudioAutoReset':
      'Type: Image | Audio: {audioPath} | Auto reset to default after audio ends',
  'mediaTypeImageMuted': 'Type: Image | Audio: muted',
  'mediaTypeVideoAutoReset':
      'Type: Video | Space: pause/resume | Auto reset to default when finished',
  'hotkeysHint': 'Hotkeys: Next ({playKey}) | Reset default ({resetKey})',
  'currentProgram': 'Current: {title}',
  'currentArtist': 'Current artist: {artist}',
  'nextProgram': 'Next: {title}',
  'nextArtist': 'Next artist: {artist}',
  'readPlaylistFailed': 'Failed to read playlist: {error}',
  'addProgramDialogTitle': 'Add program',
  'addAndSave': 'Add and save',
  'editProgramDialogTitle': 'Edit program',
  'saveChanges': 'Save changes',
  'mediaMissingRejectSave': 'Media file does not exist. Save rejected.',
  'imageNeedsAudioRejectSave': 'Image type must provide accompaniment audio.',
  'audioMissingRejectSave': 'Audio file does not exist. Save rejected.',
  'imageEmptyRejectSave': 'Image file is empty. Save rejected.',
  'imageDecodeRejectSave': 'Image cannot be decoded. Save rejected.',
  'audioDecodeRejectSave': 'Audio cannot be played. Save rejected.',
  'videoInitRejectSave': 'Video initialization failed. Save rejected.',
  'operationFailed': 'Operation failed: {error}',
  'invalidHostResponse': 'Main window returned invalid data.',
  'importTooltip': 'Import',
  'exportTooltip': 'Export',
  'refreshTooltip': 'Refresh',
  'closeTooltip': 'Close',
  'addProgram': 'Add program',
  'playlistListHint':
      'Program list (order number shown, supports drag sort/edit/delete)',
  'queueEntryCount': 'Playlist entries: {count}',
  'currentOrder': 'Current order: {order}',
  'nextOrder': 'Next order: {order}',
  'syncing': 'Syncing...',
  'emptyQueueHintManager': 'Playlist is empty. Click "Add program" below.',
};

const Map<String, String> _zhValues = <String, String>{
  'language': '语言',
  'languageEnglish': 'English',
  'languageSimplifiedChinese': '简体中文',
  'homepartyControlTitle': 'HomeParty 控制台',
  'playlistManagerTitle': '播放列表管理',
  'stagePlaylistManagerTitle': '舞台播放列表管理',
  'childWindowOnly': '仅支持子窗口调用。',
  'addInvalidProgramData': '添加失败：节目数据无效。',
  'editInvalidArgs': '编辑失败：参数无效。',
  'editItemMissing': '编辑失败：条目不存在。',
  'deleteInvalidArgs': '删除失败：参数无效。',
  'deleteItemMissing': '删除失败：条目不存在。',
  'reorderInvalidArgs': '排序失败：参数无效。',
  'importInvalidArgs': '导入失败：参数无效。',
  'unknownAction': '未知操作：{method}',
  'setDefaultFirst': '请先设置默认背景。',
  'queueEmptyAddFirst': '播放列表为空，请先添加节目。',
  'chooseDefaultBackgroundDialogTitle': '选择默认背景（图片或视频）',
  'unsupportedMediaFormat': '不支持的媒体格式。',
  'fileMissingCannotSetDefault': '文件不存在，无法设置默认背景。',
  'defaultBackgroundSet': '默认背景已设置：{file}',
  'setDefaultBackgroundFailed': '设置默认背景失败：{error}',
  'addFailedTypeMismatch': '添加失败：文件类型与选择的播放类型不匹配。',
  'itemAdded': '已添加：{title}（演唱者：{artist}）',
  'editPlaybackItemDialogTitle': '编辑播放条目',
  'saveAndValidate': '保存并校验',
  'editFailedTypeMismatch': '编辑失败：文件类型与选择的播放类型不匹配。',
  'editFailedMissingItem': '编辑失败：条目已不存在。',
  'itemUpdated': '已更新：{title}（演唱者：{artist}）',
  'itemDeleted': '已删除：{title}',
  'mediaMissingRejectAdd': '媒体文件不存在，已拒绝添加。',
  'imageNeedsAudioRejectAdd': '图片类型必须提供伴奏音乐，已拒绝添加。',
  'audioMissingRejectAdd': '伴奏文件不存在，已拒绝添加。',
  'imageEmptyRejectAdd': '图片文件为空，已拒绝添加。',
  'imageDecodeRejectAdd': '图片无法解码，已拒绝添加。',
  'audioDecodeRejectAdd': '伴奏文件无法播放，已拒绝添加。',
  'videoInitRejectAdd': '视频初始化失败，已拒绝添加。',
  'nowPlaying': '正在播放：{title}（演唱者：{artist}）',
  'queueEmptyCannotExport': '播放列表为空，无法导出。',
  'exportPlaylistDialogTitle': '导出播放列表',
  'exportSuccess': '导出成功：{path}',
  'exportFailed': '导出失败：{error}',
  'importPlaylistDialogTitle': '导入播放列表',
  'readFilePathFailed': '读取文件路径失败。',
  'importInvalidFormat': '导入失败：文件格式无效。',
  'importNoItems': '导入失败：文件中没有可用条目。',
  'importCancelledNoAccess': '导入已取消：未完成媒体文件访问授权。',
  'importStillUnauthorized':
      '导入失败：仍有 {count} 个文件未授权，请在授权窗口中多选这些媒体文件。',
  'importCompleted': '导入完成，共 {count} 条。',
  'importFailed': '导入失败：{error}',
  'fileAccessRequiredTitle': '需要系统文件权限',
  'importUnauthorizedFilesDialog':
      '导入列表引用了 {count} 个未授权文件（如：{sampleNames}{suffix}）。\n\n点击“去授权”后，请在系统窗口中按住 Command 多选这些媒体文件。',
  'cancel': '取消',
  'authorize': '去授权',
  'authorizeImportDialogTitle': '为导入播放列表授权媒体文件（可多选）',
  'playbackKeyConflict': '播放触发键不能与“切回默认”按键重复。',
  'resetKeyConflict': '“切回默认”按键不能与播放触发键重复。',
  'readyToPlay': '准备播放',
  'notStarted': '未开始',
  'controlPageTitle': '控制台',
  'shortcutHint': '快捷键：播放下一项({playKey}) / 切回默认({resetKey})',
  'switchToDefaultBackground': '切回默认背景',
  'setDefaultBackground': '设置默认背景',
  'validating': '校验中...',
  'addPlayableFile': '添加播放文件',
  'startPlaybackNext': '开始播放（下一项）',
  'openStagePage': '打开舞台页',
  'processing': '处理中...',
  'importPlaylist': '导入播放列表',
  'exportPlaylist': '导出播放列表',
  'playbackTriggerKey': '播放触发按键：',
  'resetDefaultKey': '切回默认按键：',
  'playlistHelp': '播放列表（可拖动调整顺序，每次点击“开始播放”或按触发键自动播放下一项）',
  'defaultSet': '已设置：{file}',
  'notSet': '未设置',
  'defaultBackgroundStatus': '默认背景：{text}',
  'none': '无',
  'playbackStatus': '播放状态：{status}',
  'nextItem': '下一项：{next}',
  'playbackTriggerKeyValue': '播放触发键：{key}',
  'resetDefaultKeyValue': '切回默认键：{key}',
  'imageWithAudio': '图片 + 音乐：{audio}',
  'videoType': '视频',
  'artistValue': '演唱者：{artist}',
  'edit': '编辑',
  'delete': '删除',
  'emptyQueueHintControl': '播放列表为空。点击“添加播放文件”开始创建节目单。',
  'addPlayableDialogTitle': '添加播放文件',
  'addAndValidate': '添加并校验',
  'pickImage': '选择图片',
  'pickVideo': '选择视频',
  'pickAudio': '选择伴奏音乐',
  'imageOption': '图片',
  'videoOption': '视频',
  'selectImageRequired': '选择图片（必选）',
  'imagePath': '图片：{path}',
  'selectAudioRequired': '选择音乐（必选）',
  'audioPath': '音乐：{path}',
  'selectVideoRequired': '选择视频（必选）',
  'videoPath': '视频：{path}',
  'programTitleOptional': '节目标题（可选，留空自动生成）',
  'artistOptional': '演唱者（可选）',
  'videoInitCheckFormat': '视频初始化失败，请检查文件格式或系统解码能力。',
  'audioPlaybackMuted': '伴奏播放失败，当前已静音。',
  'programEndedNoDefault': '节目播放结束，但尚未设置默认背景。',
  'videoFallbackSwitching': '检测到视频画面未输出，正在切换兼容模式...',
  'backToControl': '返回控制台',
  'exitFullscreenEsc': '退出全屏(Esc)',
  'enterFullscreenF11': '进入全屏',
  'pauseSpace': '暂停(Space)',
  'resumeSpace': '继续(Space)',
  'noBackgroundConfigured': '未配置背景',
  'setDefaultInControlFirst': '请先在控制台设置默认背景。',
  'fileNotFound': '文件不存在',
  'cannotOpenImage': '无法打开图片',
  'videoUnavailable': '视频不可播放',
  'waitingForProgram': '等待控制台发送节目。',
  'mediaTypeImageWithAudioAutoReset':
      '类型：图片 | 伴奏：{audioPath} | 伴奏结束后自动切回默认背景',
  'mediaTypeImageMuted': '类型：图片 | 伴奏：静音',
  'mediaTypeVideoAutoReset': '类型：视频 | Space：暂停/继续 | 结束后自动切回默认背景',
  'hotkeysHint': '热键：下一项({playKey}) | 切回默认({resetKey})',
  'currentProgram': '当前节目：{title}',
  'currentArtist': '当前演唱者：{artist}',
  'nextProgram': '下一节目：{title}',
  'nextArtist': '下一演唱者：{artist}',
  'readPlaylistFailed': '读取播放列表失败：{error}',
  'addProgramDialogTitle': '添加节目',
  'addAndSave': '添加并保存',
  'editProgramDialogTitle': '编辑节目',
  'saveChanges': '保存修改',
  'mediaMissingRejectSave': '媒体文件不存在，已拒绝保存。',
  'imageNeedsAudioRejectSave': '图片类型必须提供伴奏音乐。',
  'audioMissingRejectSave': '伴奏文件不存在，已拒绝保存。',
  'imageEmptyRejectSave': '图片文件为空，已拒绝保存。',
  'imageDecodeRejectSave': '图片无法解码，已拒绝保存。',
  'audioDecodeRejectSave': '伴奏文件无法播放，已拒绝保存。',
  'videoInitRejectSave': '视频初始化失败，已拒绝保存。',
  'operationFailed': '操作失败：{error}',
  'invalidHostResponse': '主窗口返回了无效数据。',
  'importTooltip': '导入',
  'exportTooltip': '导出',
  'refreshTooltip': '刷新',
  'closeTooltip': '关闭',
  'addProgram': '添加节目',
  'playlistListHint': '节目列表（按序号显示，支持拖动排序、编辑、删除）',
  'queueEntryCount': '播放列表条目：{count}',
  'currentOrder': '当前序号：{order}',
  'nextOrder': '下一序号：{order}',
  'syncing': '同步中...',
  'emptyQueueHintManager': '播放列表为空，点击右下角“添加节目”。',
};
