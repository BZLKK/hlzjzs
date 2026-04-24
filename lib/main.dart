import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'writing_provider.dart';
import 'widgets/chapter_sidebar.dart';
import 'widgets/writing_editor.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/search_dialog.dart';
import 'widgets/export_dialog.dart';
import 'widgets/history_dialog.dart';

import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

final GlobalKey<WritingEditorState> writingEditorKey =
    GlobalKey<WritingEditorState>();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setPreventClose(true);
  });

  await WindowsSingleInstance.ensureSingleInstance(
    args,
    "zjzs_hl_writer_unique_id",
    onSecondWindow: (List<String> args) {
      windowManager.show();
      windowManager.focus();
    },
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => WritingProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<WritingProvider>().themeMode;

    ThemeData lightTheme = ThemeData(
      brightness: Brightness.light,
      primarySwatch: Colors.deepOrange,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      cardColor: Colors.white,
      dividerColor: Colors.grey[300],
    );

    ThemeData darkTheme = ThemeData(
      brightness: Brightness.dark,
      primarySwatch: Colors.deepOrange,
      scaffoldBackgroundColor: const Color(0xFF161616),
      cardColor: const Color(0xFF0D0D0D),
      dividerColor: const Color(0xFF262626),
    );


    return MaterialApp(
      title: 'HL作家助手',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _getThemeMode(themeMode),
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      home: const MainPage(),
    );
  }

  ThemeMode _getThemeMode(String mode) {
    switch (mode) {
      case "明亮模式":
        return ThemeMode.light;
      case "暗黑模式":
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WindowListener {
  double _sidebarWidth = 250.0;
  bool _isSidebarVisible = true;
  Offset _searchOffset = const Offset(
    -40,
    80,
  ); // x is right-aligned if negative, but I'll use simple pos

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      // 提升关闭体验：立即隐藏窗口，避免肉眼感觉卡顿
      await windowManager.hide();

      // 关掉软件前最后抢救：刷出防抖缓存的最后几百毫秒打的字
      writingEditorKey.currentState?.flushContent();
      try {
        if (mounted) {
          final provider = context.read<WritingProvider>();
          await provider.saveCurrentChapter();
        }
      } catch (e) {
        debugPrint("Close flush error: $e");
      } finally {
        await windowManager.destroy();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WritingProvider>();
    final isZenMode = provider.isZenMode;

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
            const SearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.f11): const ToggleZenModeIntent(),
      },
      child: Actions(
        actions: {
          SearchIntent: SearchAction(context),
          ToggleZenModeIntent: ToggleZenModeAction(provider),
        },
        child: Scaffold(
          appBar: isZenMode ? null : _buildAppBar(context),
          body: Stack(
            children: [
              Row(
                children: [
                  if (!isZenMode && _isSidebarVisible) ...[
                    SizedBox(
                      width: _sidebarWidth,
                      child: const ChapterSidebar(),
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            _sidebarWidth += details.delta.dx;
                            if (_sidebarWidth < 150) _sidebarWidth = 150;
                            if (_sidebarWidth > 600) _sidebarWidth = 600;
                          });
                        },
                        child: Container(
                          width: 4,
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Stack(
                      children: [
                        WritingEditor(key: writingEditorKey),
                        if (!isZenMode)
                          Positioned(
                            left: 0,
                            top: MediaQuery.of(context).size.height / 2 - 20,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isSidebarVisible = !_isSidebarVisible;
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).cardColor.withAlpha(204),
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(8),
                                      bottomRight: Radius.circular(8),
                                    ),
                                    border: Border.all(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                  ),
                                  height: 40,
                                  width: 24,
                                  child: Icon(
                                    _isSidebarVisible
                                        ? Icons.chevron_left
                                        : Icons.chevron_right,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (provider.showHealthBanner)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    elevation: 6,
                    color: Colors.teal.shade700,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 16.0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.self_improvement,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              "您已连续写作 1 小时。为了您的视力与颈椎，站起来伸个懒腰，喝杯水，稍作休息吧！",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => provider.hideHealthBanner(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (provider.isSearchVisible)
                Positioned(
                  top: _searchOffset.dy,
                  right: _searchOffset.dx.abs(),
                  child: SearchPanel(
                    onDrag: (delta) {
                      setState(() {
                        _searchOffset += delta;
                        // Basic bounds
                        if (_searchOffset.dy < 0)
                          _searchOffset = Offset(_searchOffset.dx, 0);
                        if (_searchOffset.dx > 0)
                          _searchOffset = Offset(0, _searchOffset.dy);
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final provider = context.read<WritingProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      toolbarHeight: 48,
      backgroundColor: isDark ? const Color(0xFF252526) : Colors.white,
      elevation: 0.5,
      title: PopupMenuButton<String>(
        tooltip: "主菜单",
        position: PopupMenuPosition.under,
        onSelected: (value) {
          if (value == "settings") _showSettings(context);
          if (value == "export") _showExportDialog(context, provider);
          if (value == "about") _showAboutDialog(context);
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: "settings",
            child: ListTile(
              leading: Icon(Icons.settings),
              title: Text("个性化设置"),
            ),
          ),
          const PopupMenuItem(
            value: "export",
            child: ListTile(
              leading: Icon(Icons.rocket_launch),
              title: Text("导出书稿"),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: "about",
            child: ListTile(leading: Icon(Icons.info), title: Text("关于")),
          ),
        ],
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu, size: 24),
            SizedBox(width: 8),
            Text(
              "菜单",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.content_copy, color: Colors.green),
          onPressed: () async {
            // 确保同步
            writingEditorKey.currentState?.flushContent();
            
            final provider = context.read<WritingProvider>();
            if (provider.editorContent.isEmpty) return;
            
            final cleanText = provider.getCleanContent(provider.editorContent);
            await Clipboard.setData(ClipboardData(text: cleanText));
            
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text("全章内容已净化并复制到剪贴板"),
                  backgroundColor: Colors.green[800],
                  behavior: SnackBarBehavior.floating,
                )
              );
            }
          },
          tooltip: "一键复制全章 (已净化)",
        ),
        IconButton(
          icon: const Icon(Icons.format_indent_increase, color: Colors.blue),
          onPressed: () {
            provider.reformatContent();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("已完成自动排版"),
                duration: Duration(seconds: 1),
              ),
            );
          },
          tooltip: "一键排版 (自动缩进与去空行)",
        ),
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => _showSearch(context),
          tooltip: "查找与替换 (Ctrl+F)",
        ),
        IconButton(
          icon: const Icon(Icons.history, color: Colors.grey),
          onPressed: () => _showHistory(context, provider),
          tooltip: "时光机 (历史版本)",
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("关于"),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "HL作家助手 v1.0",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text("这是一款专注于沉浸式打字的无干扰写作软件。"),
            SizedBox(height: 12),
            Text(
              "作者邮箱: hzlkkk@gmail.com",
              style: TextStyle(color: Colors.blue),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context, WritingProvider provider) {
    if (provider.currentBookName == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请先选择书籍")));
      return;
    }
    showDialog(
      context: context,
      builder: (context) => ExportDialog(provider: provider),
    );
  }

  void _showSearch(BuildContext context) {
    context.read<WritingProvider>().toggleSearch();
  }

  void _showSettings(BuildContext context) {
    showDialog(context: context, builder: (context) => const SettingsDialog());
  }

  void _showHistory(BuildContext context, WritingProvider provider) {
    if (provider.currentBookName == null ||
        provider.currentChapterName == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请先选择章节")));
      return;
    }
    showDialog(
      context: context,
      builder: (context) => HistoryDialog(provider: provider),
    );
  }
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class SearchAction extends Action<SearchIntent> {
  final BuildContext context;
  SearchAction(this.context);
  @override
  Object? invoke(SearchIntent intent) {
    context.read<WritingProvider>().toggleSearch();
    return null;
  }
}

class ToggleZenModeIntent extends Intent {
  const ToggleZenModeIntent();
}

class ToggleZenModeAction extends Action<ToggleZenModeIntent> {
  final WritingProvider provider;
  ToggleZenModeAction(this.provider);

  @override
  Object? invoke(ToggleZenModeIntent intent) {
    final isNewZen = !provider.isZenMode;
    provider.setZenMode(isNewZen);
    windowManager.setFullScreen(isNewZen);
    return null;
  }
}
