import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

class Book {
  final String name;
  final String path;
  List<Chapter> chapters;

  Book({required this.name, required this.path, this.chapters = const []});
}

class Chapter {
  final String name;
  final String path;
  int wordCount;

  Chapter({required this.name, required this.path, this.wordCount = 0});

  String get id => name; // Use name as ID for stable reordering
}

class ChapterCache {
  final DateTime lastModified;
  final int wordCount;
  ChapterCache(this.lastModified, this.wordCount);
}

class WritingProvider with ChangeNotifier {
  Directory? _baseDir;
  String? _currentBookPath;
  String? _currentChapterName;
  String _editorContent = "";

  List<String> _books = [];
  List<Chapter> _chapters = [];
  final Map<String, ChapterCache> _chapterWordCountCache = {};

  // State / Sessions
  int _sessionWordsAdded = 0;
  int _sessionSeconds = 0; // Total session time
  int _typingSeconds = 0; // Cumulative time spent actively typing
  int _idleSeconds = 0;   // Cumulative time spent idle
  DateTime _lastInputTime = DateTime.parse("2000-01-01 00:00:00"); 
  
  int _chapterWordCount = 0;
  DateTime? _lastSaveTime;
  Timer? _statsTimer;
  Timer? _autoSaveTimer;
  DateTime? _currentChapterLastHistorySave;
  int? _lastHistoryContentLength;
  String? _lastSavedHistoryContent;

  // Zen & Dopamine features
  bool _isZenMode = false;
  int _dailyWordGoal = 4000;
  int _dailyWordsAdded = 0;
  int? _maxWordCountInSession;
  bool _showDopamineBurst = false;
  bool _hasTriggeredDailyGoalToday = false;
  bool _showHealthBanner = false;
  int _lastHealthBannerTriggerHour = 0;
  bool _isSearchVisible = false;
  bool _autoIndent = true;
  bool _isSaving = false; // 保存状态标志
  DateTime? _lastSaveIndicatorTime; // 上次显示保存成功的时刻

  // Settings
  double _fontSize = 20.0;
  double _lineHeight = 1.8;
  bool _fontBold = false;
  int _letterSpacing = 2;
  String _themeMode = "系统默认"; // 跟随系统, 明亮模式, 暗黑模式
  String _fontFamily = "Noto Sans SC";
  String _bgColorName = "系统默认";
  String _fontColorName = "系统默认";
  String _accentColorName = "琥珀金";
  bool _isTypewriterMode = true;
  double _typewriterOffset = 0.35;
  List<String> _chapterOrder = []; // Saved order of chapter names

  static const Map<String, int?> bgColorMap = {
    "系统默认": null,
    "纯白初雪": 0xFFFFFFFF,
    "米黄羊皮纸": 0xFFFBF5E6,
    "浅灰护眼绿": 0xFFC7EDCC,
    "樱花浅粉": 0xFFFFF0F5,
    "深空灰": 0xFF2D2E2F,
    "深夜幽黑": 0xFF1E2227,
    "极致纯黑": 0xFF000000,
    "深青": 0xFF142B2B,
    "薄绿": 0xFFE0F5E6,
    "梦幻浅紫": 0xFFE6E6FA,
    "自然青柠": 0xFF32CD32,
    "原野深绿": 0xFF2E8B57,
  };

  static const Map<String, int?> fontColorMap = {
    "系统默认": null,
    "沉稳纯黑": 0xFF1A1A1A,
    "深青黯灰": 0xFF3D404A,
    "极简浅灰": 0xFF888888,
    "纯白无瑕": 0xFFFFFFFF,
    "月光银白": 0xFFE0E0E0,
    "柔和米白": 0xFFF5F5F5,
    "雾气浅灰": 0xFFB0B0B0,
    "暗金璀璨": 0xFFD4AF37,
    "梦幻浅紫": 0xFFE6E6FA,
    "自然青柠": 0xFF32CD32,
    "原野深绿": 0xFF2E8B57,
    "深邃海蓝": 0xFF4682B4,
    "琥珀暖橙": 0xFFFF8C00,
  };

  static const Map<String, int> accentColorMap = {
    "琥珀金": 0xFFFFBF00,
    "翡翠绿": 0xFF50C878,
    "宝石蓝": 0xFF007FFF,
    "玫瑰红": 0xFFE0115F,
    "梦幻紫": 0xFF9966CC,
    "活力橙": 0xFFFF4500,
    "极简白": 0xFFFFFFFF,
    "深邃黑": 0xFF000000,
  };

  static const Map<String, String> chineseFontMap = {
    "Noto Sans SC": "思源黑体",
    "Noto Serif SC": "思源宋体",
    "Ma Shan Zheng": "马善政体",
    "Zhi Mang Xing": "智莽星体",
    "Liu Jian Mao Cao": "流江毛草",
    "Long Cang": "龙藏体",
    "ZCOOL XiaoWei": "站酷小薇",
  };

  WritingProvider() {
    _init();
  }

  // Getters
  String? get currentBookName =>
      _currentBookPath != null ? p.basename(_currentBookPath!) : null;
  String? get currentChapterName => _currentChapterName;
  String get editorContent => _editorContent;
  List<String> get books => _books;
  List<Chapter> get chapters => _chapters;
  int get chapterWordCount => _chapterWordCount;
  int get sessionWordsAdded => _sessionWordsAdded;
  int get sessionSeconds => _sessionSeconds;
  int get typingSeconds => _typingSeconds;
  int get idleSeconds => _idleSeconds;
  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  bool get fontBold => _fontBold;
  int get letterSpacing => _letterSpacing;
  String get themeMode => _themeMode;
  String get fontFamily => _fontFamily;
  String get bgColorName => _bgColorName;
  String get fontColorName => _fontColorName;
  String get accentColorName => _accentColorName;
  bool get isTypewriterMode => _isTypewriterMode;
  double get typewriterOffset => _typewriterOffset;
  int? get customBgColor => bgColorMap[_bgColorName];
  int? get customFontColor => fontColorMap[_fontColorName];
  int get customAccentColor => accentColorMap[_accentColorName] ?? 0xFFFFBF00;
  DateTime? get lastSaveTime => _lastSaveTime;
  String get baseDirPath => _baseDir?.path ?? "";

  bool get isZenMode => _isZenMode;
  int get dailyWordGoal => _dailyWordGoal;
  int get dailyWordsAdded => _dailyWordsAdded;
  bool get showDopamineBurst => _showDopamineBurst;
  bool get showHealthBanner => _showHealthBanner;
  bool get isSearchVisible => _isSearchVisible;
  bool get autoIndent => _autoIndent;
  bool get isSaving => _isSaving;

  void setSearchVisible(bool visible) {
    _isSearchVisible = visible;
    notifyListeners();
  }

  void toggleSearch() {
    _isSearchVisible = !_isSearchVisible;
    notifyListeners();
  }

  void setAutoIndent(bool value) {
    _autoIndent = value;
    notifyListeners();
    saveSetting('auto_indent', value);
  }

  /// 一键排版：自动为段落首行加上两个全角空格，并保留原有空行（压缩连续空行为单行）
  void reformatContent() {
    if (_editorContent.isEmpty) return;
    
    // 1. 分段
    final lines = _editorContent.split('\n');
    final List<String> newLines = [];
    for (var line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      
      // 2. 如果没缩进，加上缩进
      if (!trimmed.startsWith('　　') && !trimmed.startsWith('  ')) {
        trimmed = '　　' + trimmed;
      }
      // 3. 将半角双空格替换为全角
      if (trimmed.startsWith('  ')) {
        trimmed = '　　' + trimmed.substring(2).trimLeft();
      }
      
      newLines.add(trimmed);
    }
    
    // 移除所有首尾空行并连接
    _editorContent = newLines.join('\n').trim(); 
    notifyListeners();
  }

  /// 获取经过排版净化的纯净文本
  String getCleanContent(String rawText) {
    if (rawText.isEmpty) return "";
    final lines = rawText.split('\n');
    final List<String> cleanedLines = [];
    
    for (var line in lines) {
      var l = line;
      // 移除开头的全角或半角双空格
      if (l.startsWith('　　')) {
        l = l.substring(2);
      } else if (l.startsWith('  ')) {
        l = l.substring(2);
      }
      cleanedLines.add(l.trimRight());
    }
    
    return cleanedLines.join('\n');
  }

  Future<void> _init() async {
    await _loadSettings();
    final prefs = await SharedPreferences.getInstance();

    _dailyWordGoal = prefs.getInt('daily_word_goal') ?? 4000;
    final todayKey = _getTodayKey();
    _dailyWordsAdded = prefs.getInt(todayKey) ?? 0;
    if (_dailyWordsAdded >= _dailyWordGoal) {
      _hasTriggeredDailyGoalToday = true;
    }

    final customPath = prefs.getString('custom_base_path');
    if (customPath != null && await Directory(customPath).exists()) {
      _baseDir = Directory(customPath);
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      _baseDir = Directory(p.join(docsDir.path, "NovelWriterLibrary"));
      if (!await _baseDir!.exists()) {
        await _baseDir!.create(recursive: true);
      }
    }

    await _refreshBookList();
    await _restoreLastState();
    _startTimers();
  }

  String _getTodayKey() {
    final now = DateTime.now();
    return "daily_words_${now.year}-${now.month}-${now.day}";
  }

  Future<void> updateBaseDir(String newPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_base_path', newPath);
    _baseDir = Directory(newPath);
    _currentBookPath = null;
    _currentChapterName = null;
    _editorContent = "";
    _books = [];
    _chapters = [];
    await _refreshBookList();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _fontSize = prefs.getDouble('font_size') ?? 20.0;
    _lineHeight = prefs.getDouble('line_height') ?? 1.5;
    _fontBold = prefs.getBool('font_bold') ?? false;
    _letterSpacing = prefs.getInt('letter_spacing') ?? 2;
    _themeMode = prefs.getString('theme_mode') ?? "系统默认";
    _fontFamily = prefs.getString('font_family') ?? "Noto Sans SC";
    _bgColorName = prefs.getString('bg_color_name') ?? "系统默认";
    _fontColorName = prefs.getString('font_color_name') ?? "系统默认";
    _accentColorName = prefs.getString('accent_color_name') ?? "琥珀金";
    _isTypewriterMode = prefs.getBool('is_typewriter_mode') ?? true;
    _typewriterOffset = prefs.getDouble('typewriter_offset') ?? 0.35;
    _autoIndent = prefs.getBool('auto_indent') ?? true;
    notifyListeners();
  }

  Future<void> saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is double) await prefs.setDouble(key, value);
    if (value is int) await prefs.setInt(key, value);
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);

    await _loadSettings();
  }

  void _startTimers() {
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _sessionSeconds++;

      final now = DateTime.now();
      // If last input was within 60 seconds, consider active
      if (now.difference(_lastInputTime).inSeconds < 60) {
        _typingSeconds++;
      } else {
        _idleSeconds++;
      }

      // Hourly Health Reminder check (90 minutes)
      if (_sessionSeconds > 0 && _sessionSeconds % 5400 == 0) {
        final currentHour = _sessionSeconds ~/ 3600;
        if (_lastHealthBannerTriggerHour != currentHour) {
          _lastHealthBannerTriggerHour = currentHour;
          _triggerHealthBanner();
        }
      }
      notifyListeners();
    });

    _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      saveCurrentChapter();
    });
  }

  Future<void> _refreshBookList() async {
    if (_baseDir == null) return;
    final entities = await _baseDir!.list().toList();
    _books = entities
        .whereType<Directory>()
        .map((e) => p.basename(e.path))
        .toList();
    notifyListeners();
  }

  Future<void> _refreshChapterList() async {
    if (_currentBookPath == null) return;
    try {
      final dir = Directory(_currentBookPath!);
      final entities = await dir.list().toList();

      // 1. Load the manual order if it exists
      await _loadOrder();

      final Map<String, Chapter> chapterMap = {};
      for (var entity in entities) {
        try {
          if (entity is File &&
              (entity.path.endsWith(".md") || entity.path.endsWith(".txt"))) {
            final fileName = p.basename(entity.path);
            if (fileName.startsWith('.')) {
              continue; // Skip order file and other hidden files
            }

            final stat = await entity.stat();
            final cache = _chapterWordCountCache[entity.path];
            int count;
            if (cache != null && cache.lastModified == stat.modified) {
              count = cache.wordCount;
            } else {
              final content = await entity.readAsString();
              count = getRealWordCount(content);
              _chapterWordCountCache[entity.path] = ChapterCache(
                stat.modified,
                count,
              );
            }

            final name = p.basenameWithoutExtension(entity.path);
            chapterMap[name] = Chapter(
              name: name,
              path: entity.path,
              wordCount: count,
            );
          }
        } catch (e) {
          debugPrint("Refresh chapter item error for ${entity.path}: $e");
        }
      }

      // 2. Build the list following the order
      final List<Chapter> sortedChapters = [];
      final Set<String> matchedNames = {};

      for (var name in _chapterOrder) {
        if (chapterMap.containsKey(name)) {
          sortedChapters.add(chapterMap[name]!);
          matchedNames.add(name);
        }
      }

      // 3. Add any chapters not in the order file (e.g., added externally)
      final List<String> remainingNames = chapterMap.keys
          .where((n) => !matchedNames.contains(n))
          .toList();
      remainingNames.sort(); // Natural sort for new files
      for (var name in remainingNames) {
        sortedChapters.add(chapterMap[name]!);
        _chapterOrder.add(name);
      }

      _chapters = sortedChapters;
      if (remainingNames.isNotEmpty) {
        await _saveOrder();
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Refresh chapters error: $e");
    }
  }

  Future<void> _loadOrder() async {
    if (_currentBookPath == null) return;
    final orderFile = File(p.join(_currentBookPath!, ".order.txt"));
    if (await orderFile.exists()) {
      final lines = await orderFile.readAsLines();
      _chapterOrder = lines.where((l) => l.trim().isNotEmpty).toList();
    } else {
      _chapterOrder = [];
    }
  }

  Future<void> _saveOrder() async {
    if (_currentBookPath == null) return;
    final orderFile = File(p.join(_currentBookPath!, ".order.txt"));
    final tempFile = File(p.join(_currentBookPath!, ".order.tmp"));
    await tempFile.writeAsString(_chapterOrder.join("\n"));
    await tempFile.rename(orderFile.path);
  }

  Future<void> reorderChapters(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final Chapter chapter = _chapters.removeAt(oldIndex);
    _chapters.insert(newIndex, chapter);

    // Update the persistent order list
    _chapterOrder = _chapters.map((c) => c.name).toList();
    await _saveOrder();
    notifyListeners();
  }

  Future<void> sortChapters(bool ascending) async {
    if (_currentBookPath == null) return;

    final regex = RegExp(r'(\d+)');

    _chapters.sort((a, b) {
      final matchA = regex.firstMatch(a.name);
      final matchB = regex.firstMatch(b.name);

      if (matchA != null && matchB != null) {
        final valA = int.parse(matchA.group(1)!);
        final valB = int.parse(matchB.group(1)!);
        if (ascending) return valA.compareTo(valB);
        return valB.compareTo(valA);
      }

      if (ascending) {
        return a.name.compareTo(b.name);
      } else {
        return b.name.compareTo(a.name);
      }
    });

    _chapterOrder = _chapters.map((c) => c.name).toList();
    await _saveOrder();
    notifyListeners();
  }

  int getRealWordCount(String text) {
    return text.replaceAll(RegExp(r'\s+'), '').replaceAll('　', '').length;
  }

  int get writingSpeed {
    if (_typingSeconds == 0) return 0;
    return (_sessionWordsAdded / _typingSeconds * 3600).round();
  }

  Future<void> createBook(String name) async {
    final path = p.join(_baseDir!.path, name);
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create();
      await _refreshBookList();
      await loadBook(name);
    }
  }

  Future<void> loadBook(String name) async {
    _currentBookPath = p.join(_baseDir!.path, name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_book', name);

    _currentChapterName = null;
    _editorContent = "";
    _chapterWordCount = 0;

    await _refreshChapterList();
    notifyListeners();
  }

  Future<void> renameBook(String oldName, String newName) async {
    final oldPath = p.join(_baseDir!.path, oldName);
    final newPath = p.join(_baseDir!.path, newName);
    final dir = Directory(oldPath);
    if (await dir.exists() && oldName != newName) {
      await dir.rename(newPath);
      if (_currentBookPath == oldPath) {
        _currentBookPath = newPath;
      }
      await _refreshBookList();
    }
  }

  Future<void> createChapter(String name) async {
    if (_currentBookPath == null) return;
    final prefix = "第${_chapters.length + 1}章";
    final fullName = name.trim().isNotEmpty ? "$prefix $name" : prefix;
    final fileName = "$fullName.txt";
    final file = File(p.join(_currentBookPath!, fileName));
    if (!await file.exists()) {
      final currentIndent = autoIndent ? "　　" : "";
      await file.writeAsString(currentIndent);
      // Add to the beginning of the order (descending by default)
      _chapterOrder.insert(0, fullName);
      await _saveOrder();

      await _refreshChapterList();
      await loadChapter(fullName);
    }
  }

  Future<void> loadChapter(String name) async {
    if (_currentBookPath == null) return;
    await saveCurrentChapter();

    final txtFile = File(p.join(_currentBookPath!, "$name.txt"));
    final mdFile = File(p.join(_currentBookPath!, "$name.md"));
    final file = await txtFile.exists() ? txtFile : mdFile;

    if (await file.exists()) {
      _currentChapterName = name;
      _editorContent = await file.readAsString();
      _chapterWordCount = getRealWordCount(_editorContent);
      _currentChapterLastHistorySave = null;
      _lastHistoryContentLength = null;
      _lastSavedHistoryContent = _editorContent;
      _maxWordCountInSession = _chapterWordCount;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_chapter', name);
      notifyListeners();
    }
  }

  void updateContent(String content, {bool isRestore = false}) {
    final newCount = getRealWordCount(content);
    final diff = newCount - _chapterWordCount;
    
    if (diff != 0 && !isRestore) {
      _lastInputTime = DateTime.now(); // Record activity
    }

    if (diff > 0 && !isRestore) {
      // 过滤大面积粘贴：如果一次性新增超过 100 字，视为外部导入，不计入本次写作进度统计
      if (diff < 100) {
        _sessionWordsAdded += diff;
        _dailyWordsAdded += diff;
        _persistDailyWords();

        // 检查每日目标达成情况
        if (_dailyWordsAdded >= _dailyWordGoal && !_hasTriggeredDailyGoalToday) {
          _hasTriggeredDailyGoalToday = true;
          _triggerDopamineBurst();
        }
      }
    } else if (diff <= -50 && !isRestore) {
      if (_currentChapterName != null && _editorContent.isNotEmpty) {
        _createHistoryBackup(_currentChapterName!, _editorContent);
      }
    }
    
    // 强制保护：如果当前字数比本章历史最高点少了 100 字以上（可能是多次连续 Undo 导致的），强制备份
    _maxWordCountInSession ??= _chapterWordCount;
    if (newCount > _maxWordCountInSession!) {
      _maxWordCountInSession = newCount;
    } else if (!isRestore && newCount < _maxWordCountInSession! - 100) {
      if (_currentChapterName != null && _editorContent.isNotEmpty && _editorContent.length > content.length) {
        _createHistoryBackup(_currentChapterName!, _editorContent);
        _maxWordCountInSession = newCount; // 备份后重置，防止刷屏
      }
    }

    if (newCount > (_lastHistoryContentLength ?? 0) + 200) {
      if (_currentChapterName != null) {
        _createHistoryBackup(_currentChapterName!, content);
        _lastHistoryContentLength = newCount;
      }
    }

    _editorContent = content;
    _chapterWordCount = newCount;
    notifyListeners();
  }

  Future<void> saveCurrentChapter() async {
    if (_currentBookPath == null || _currentChapterName == null) return;
    // Prefer TXT now as per user request
    final file = File(p.join(_currentBookPath!, "$_currentChapterName.txt"));
    final tempFile = File(
      p.join(_currentBookPath!, ".$_currentChapterName.txt.tmp"),
    );
    await tempFile.writeAsString(_editorContent);
    await tempFile.rename(file.path);
    _lastSaveTime = DateTime.now();
    _isSaving = true;
    _lastSaveIndicatorTime = DateTime.now();
    notifyListeners();

    // 2秒后清除保存状态，用于 UI 指示
    Future.delayed(const Duration(seconds: 2), () {
      if (_lastSaveIndicatorTime != null && 
          DateTime.now().difference(_lastSaveIndicatorTime!).inSeconds >= 2) {
        _isSaving = false;
        notifyListeners();
      }
    });

    int lenDiff = _lastHistoryContentLength != null
        ? (_editorContent.length - _lastHistoryContentLength!).abs()
        : 9999;

    // 如果超过15分钟，并且自从上次备份以来字数变动超过50个字符，才产生新的备份
    if (_currentChapterLastHistorySave == null ||
        (DateTime.now().difference(_currentChapterLastHistorySave!).inMinutes >=
                15 &&
            lenDiff >= 50)) {
      await _createHistoryBackup(_currentChapterName!, _editorContent);
      _currentChapterLastHistorySave = DateTime.now();
      _lastHistoryContentLength = _editorContent.length;
    }

    // Update word count in listing
    final index = _chapters.indexWhere((c) => c.name == _currentChapterName);
    if (index != -1) {
      _chapters[index].wordCount = _chapterWordCount;
    }
    notifyListeners();
  }

  Future<void> deleteChapter(String name) async {
    if (_currentBookPath == null) return;
    try {
      final mdFile = File(p.join(_currentBookPath!, "$name.md"));
      final txtFile = File(p.join(_currentBookPath!, "$name.txt"));

      if (await mdFile.exists()) await mdFile.delete();
      if (await txtFile.exists()) await txtFile.delete();

      _chapterOrder.remove(name);
      _chapterWordCountCache.remove(txtFile.path);
      _chapterWordCountCache.remove(mdFile.path);
      await _saveOrder();

      if (_currentChapterName == name) {
        _currentChapterName = null;
        _editorContent = "";
        _chapterWordCount = 0;
      }
      await _refreshChapterList();
    } catch (e) {
      debugPrint("Delete chapter error: $e");
    }
  }

  Future<void> renameChapter(String oldName, String newName) async {
    if (_currentBookPath == null) return;
    try {
      final oldMd = File(p.join(_currentBookPath!, "$oldName.md"));
      final oldTxt = File(p.join(_currentBookPath!, "$oldName.txt"));
      final newFile = File(p.join(_currentBookPath!, "$newName.txt"));

      if (await oldMd.exists()) {
        await oldMd.rename(newFile.path);
      } else if (await oldTxt.exists()) {
        await oldTxt.rename(newFile.path);
      }

      // Update order list
      final index = _chapterOrder.indexOf(oldName);
      if (index != -1) {
        _chapterOrder[index] = newName;
        _chapterWordCountCache.remove(oldMd.path);
        _chapterWordCountCache.remove(oldTxt.path);
        await _saveOrder();
      }

      if (_currentChapterName == oldName) {
        _currentChapterName = newName;
      }
      await _refreshChapterList();
    } catch (e) {
      debugPrint("Rename chapter error: $e");
    }
  }

  Future<void> exportBookAsTxt(String exportPath) async {
    if (_currentBookPath == null) return;
    final buffer = StringBuffer();
    for (var chapter in _chapters) {
      final file = File(chapter.path);
      final content = await file.readAsString();
      // 使用标准 \n，避免 Windows 与 Unix 混淆
      buffer.write("\n\n${chapter.name}\n\n");
      buffer.write(content);
    }
    final exportFile = File(exportPath);
    await exportFile.writeAsString(buffer.toString());
  }

  Future<String> getDesktopPath() async {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile == null) {
        return (await getApplicationDocumentsDirectory()).path;
      }

      List<String> variants = [
        p.join(userProfile, 'Desktop'),
        p.join(userProfile, '桌面'),
        p.join(userProfile, 'OneDrive', 'Desktop'),
        p.join(userProfile, 'OneDrive', '桌面'),
      ];

      for (var path in variants) {
        if (await Directory(path).exists()) return path;
      }
      return userProfile;
    }
    return (await getApplicationDocumentsDirectory()).path;
  }

  Future<void> _restoreLastState() async {
    final prefs = await SharedPreferences.getInstance();
    final lastBook = prefs.getString('last_book');
    final lastChapter = prefs.getString('last_chapter');

    if (lastBook != null && _books.contains(lastBook)) {
      await loadBook(lastBook);
      if (lastChapter != null) {
        final chapterExists = _chapters.any((c) => c.name == lastChapter);
        if (chapterExists) {
          await loadChapter(lastChapter);
        }
      }
    }
  }

  Future<void> replaceAll(
    String term,
    String replacement,
    bool isWholeBook,
  ) async {
    if (term.isEmpty) return;
    await saveCurrentChapter();

    final regex = RegExp(RegExp.escape(term), caseSensitive: false);

    if (isWholeBook) {
      if (_currentBookPath == null) return;
      
      // 创建“后悔药”全书备份
      await _createBookSnapshot("全书替换前备份");
      
      for (var chapter in _chapters) {
        final chapterFile = File(chapter.path);
        if (await chapterFile.exists()) {
          try {
            final content = await chapterFile.readAsString();
            if (content.contains(regex)) {
              final newContent = content.replaceAll(regex, replacement);
              final tempFile = File("${chapter.path}.tmp");
              await tempFile.writeAsString(newContent);
              await tempFile.rename(chapter.path);
            }
          } catch (e) {
            debugPrint("Replace in chapter error ${chapter.path}: $e");
          }
        }
      }
      // Reload current chapter if it was affected
      if (_currentChapterName != null) {
        await loadChapter(_currentChapterName!);
      } else {
        await _refreshChapterList();
      }
    } else {
      updateContent(_editorContent.replaceAll(regex, replacement));
      await saveCurrentChapter();
    }
    notifyListeners();
  }

  Future<List<String>> searchWholeBook(String term) async {
    if (_currentBookPath == null || term.isEmpty) return [];
    List<String> results = [];
    try {
      for (var chapter in _chapters) {
        final file = File(chapter.path);
        final content = await file.readAsString();
        if (content.contains(term)) {
          results.add(chapter.name);
        }
      }
    } catch (e) {
      debugPrint("Search error: $e");
    }
    return results;
  }

  Future<void> _createHistoryBackup(String chapterName, String content) async {
    if (_currentBookPath == null) return;
    
    // 内容重复检查：如果和上一个历史备份完全一样，就没必要存了
    if (content == _lastSavedHistoryContent) return;
    
    try {
      final historyDir = Directory(p.join(_currentBookPath!, ".history"));
      if (!await historyDir.exists()) {
        await historyDir.create();
      }

      final now = DateTime.now();
      String formattedDate =
          "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
      final backupPath = p.join(
        historyDir.path,
        "${chapterName}_$formattedDate.txt",
      );
      final tempFile = File("$backupPath.tmp");

      await tempFile.writeAsString(content);
      await tempFile.rename(backupPath);
      
      _lastSavedHistoryContent = content; // 更新最后一次备份的内容缓存

      await _cleanOldBackups(historyDir, chapterName);
    } catch (e) {
      debugPrint("Backup error: $e");
    }
  }

  /// 创建当前书籍的完整快照（全书备份）
  Future<void> _createBookSnapshot(String reason) async {
    if (_currentBookPath == null) return;
    try {
      final historyDir = Directory(p.join(_currentBookPath!, ".history"));
      if (!await historyDir.exists()) await historyDir.create();

      final now = DateTime.now();
      final formattedDate =
          "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
      
      final snapshotDirName = "全书快照_${formattedDate}_$reason";
      final snapshotDir = Directory(p.join(historyDir.path, snapshotDirName));
      await snapshotDir.create();

      // 复制所有章节文件
      for (var chapter in _chapters) {
        final originFile = File(chapter.path);
        if (await originFile.exists()) {
          await originFile.copy(p.join(snapshotDir.path, p.basename(chapter.path)));
        }
      }
      
      // 复制排序文件
      final orderFile = File(p.join(_currentBookPath!, ".order.txt"));
      if (await orderFile.exists()) {
        await orderFile.copy(p.join(snapshotDir.path, ".order.txt"));
      }
      
      debugPrint("Snapshot created: ${snapshotDir.path}");
    } catch (e) {
      debugPrint("Snapshot creation error: $e");
    }
  }

  Future<void> _cleanOldBackups(
    Directory historyDir,
    String chapterName,
  ) async {
    final prefix = "${chapterName}_";
    final entities = await historyDir.list().toList();
    List<File> chapterBackups = entities
        .whereType<File>()
        .where(
          (e) =>
              p.basename(e.path).startsWith(prefix) && e.path.endsWith('.txt'),
        )
        .toList();

    if (chapterBackups.length > 100) {
      chapterBackups.sort(
        (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
      );
      final extras = chapterBackups.length - 100;
      for (int i = 0; i < extras; i++) {
        try {
          await chapterBackups[i].delete();
        } catch (e) {
          debugPrint("Delete old backup error: $e");
        }
      }
    }
  }

  Future<List<File>> getChapterHistory(String chapterName) async {
    if (_currentBookPath == null) return [];
    try {
      final historyDir = Directory(p.join(_currentBookPath!, ".history"));
      if (!await historyDir.exists()) return [];

      final prefix = "${chapterName}_";
      final entities = await historyDir.list().toList();
      List<File> chapterBackups = entities
          .whereType<File>()
          .where(
            (e) =>
                p.basename(e.path).startsWith(prefix) &&
                e.path.endsWith('.txt'),
          )
          .toList();

      // Sort newest first
      chapterBackups.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
      return chapterBackups;
    } catch (e) {
      debugPrint("Get history error: $e");
      return [];
    }
  }

  Future<void> restoreFromHistory(File backupFile) async {
    if (_currentChapterName == null || !await backupFile.exists()) return;

    // Safety snapshot before restoring
    final now = DateTime.now();
    final formattedDate =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}_还原前备份";
    final historyDir = Directory(p.join(_currentBookPath!, ".history"));
    if (!await historyDir.exists()) await historyDir.create();

    final preRestorePath = p.join(
      historyDir.path,
      "${_currentChapterName!}_$formattedDate.txt",
    );
    final tempPreFile = File("$preRestorePath.tmp");
    await tempPreFile.writeAsString(_editorContent);
    await tempPreFile.rename(preRestorePath);

    await _cleanOldBackups(historyDir, _currentChapterName!);

    // Explicitly update save timer to avoid accidental overwrites
    _currentChapterLastHistorySave = DateTime.now();

    final content = await backupFile.readAsString();
    updateContent(content, isRestore: true);
    await saveCurrentChapter();
  }

  // --- New features ---
  void setZenMode(bool isZen) {
    _isZenMode = isZen;
    notifyListeners();
  }

  void setDailyWordGoal(int goal) {
    _dailyWordGoal = goal;
    if (_dailyWordsAdded < _dailyWordGoal) {
      _hasTriggeredDailyGoalToday = false;
    }
    notifyListeners();
    // 异步保存，不阻塞UI滑动
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('daily_word_goal', goal);
    });
  }

  Future<void> _persistDailyWords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_getTodayKey(), _dailyWordsAdded);
  }

  void _triggerDopamineBurst() {
    _showDopamineBurst = true;
    notifyListeners();
    Timer(const Duration(seconds: 4), () {
      _showDopamineBurst = false;
      notifyListeners();
    });
  }

  void _triggerHealthBanner() {
    _showHealthBanner = true;
    notifyListeners();
    Timer(const Duration(seconds: 8), () {
      _showHealthBanner = false;
      notifyListeners();
    });
  }

  void hideHealthBanner() {
    _showHealthBanner = false;
    notifyListeners();
  }

  Future<String> exportSettingsToDesktop() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final Map<String, dynamic> config = {};

    for (String key in keys) {
      // Filter out transient per-day stats
      if (key.startsWith('daily_words_')) continue;
      // Filter out last session state if you want a clean config, or keep it.
      // Usually better to keep UI settings but maybe skip current book/chapter to avoid path issues.
      if (key == 'last_book' || key == 'last_chapter') continue;

      config[key] = prefs.get(key);
    }

    final desktopPath = await getDesktopPath();
    final now = DateTime.now();
    final dateStr =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";
    String fileName = "HL作家助手配置备份_$dateStr.json";
    String fullPath = p.join(desktopPath, fileName);

    // Anti-overwrite check
    if (await File(fullPath).exists()) {
      fileName =
          "HL作家助手配置备份_${dateStr}_${now.hour}${now.minute}${now.second}.json";
      fullPath = p.join(desktopPath, fileName);
    }

    final file = File(fullPath);
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(config));
    return fullPath;
  }

  Future<void> importSettings(String path) async {
    final file = File(path);
    if (!await file.exists()) return;

    final String content = await file.readAsString();
    final Map<String, dynamic> config = jsonDecode(content);
    final prefs = await SharedPreferences.getInstance();

    for (var entry in config.entries) {
      final key = entry.key;
      final val = entry.value;

      if (val is String) {
        await prefs.setString(key, val);
      } else if (val is int) {
        await prefs.setInt(key, val);
      } else if (val is double) {
        await prefs.setDouble(key, val);
      } else if (val is bool) {
        await prefs.setBool(key, val);
      }
    }

    // After import, check if the base path still exists on this machine
    final importedPath = prefs.getString('custom_base_path');
    if (importedPath != null && !await Directory(importedPath).exists()) {
      await prefs.remove('custom_base_path'); // Revert to default
    }

    await _loadSettings();
    notifyListeners();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _autoSaveTimer?.cancel();
    super.dispose();
  }
}
