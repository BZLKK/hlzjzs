import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../writing_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_quill/quill_delta.dart';

class WritingEditor extends StatefulWidget {
  const WritingEditor({super.key});

  @override
  WritingEditorState createState() => WritingEditorState();
}

class WritingEditorState extends State<WritingEditor> {
  QuillController? _controller;
  String? _lastChapter;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceSync;
  String _lastPlainText = "";
  bool _isAutoInserting = false;
  DateTime _lastAutoInsertTime = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _statsOffset = const Offset(24, 24);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _debounceSync?.cancel();
    _controller?.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initController(String content) {
    Document doc;
    if (content.trim().isEmpty) {
      doc = Document();
    } else {
      // 使用 fromDelta 可以避免初始加载被录入撤销栈
      doc = Document.fromDelta(Delta()..insert(content)..insert('\n'));
    }

    _controller?.removeListener(_onChanged);
    _controller?.dispose(); // 彻底释放旧控制器，从而清空撤销栈

    _controller = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );

    _lastPlainText = _controller!.document.toPlainText();
    _controller!.addListener(_onChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller != null) {
        _focusNode.requestFocus();
      }
    });
  }

  void _onChanged() {
    if (_controller == null) return;
    final provider = context.read<WritingProvider>();

    final plainText = _controller!.document.toPlainText();

    bool wasAdded = false;
    if (_isAutoInserting) {
      _lastPlainText = plainText;
      _isAutoInserting = false;
    } else if (_lastPlainText != plainText) {
      wasAdded = plainText.length > _lastPlainText.length;
      final selection = _controller!.selection;

      // 使用最高鲁棒性的左右差分法计算改动点，免疫任何输入法带来的 selection 异步延迟
      int diffIndex = 0;
      while (diffIndex < _lastPlainText.length &&
          diffIndex < plainText.length &&
          plainText[diffIndex] == _lastPlainText[diffIndex]) {
        diffIndex++;
      }

      if (diffIndex < plainText.length) {
        final lengthDiff = plainText.length - _lastPlainText.length;
        final char = plainText[diffIndex];
        final now = DateTime.now();

        if (wasAdded) {
          // 0. 新章节第一行首字缩进保护 (针对全新文档)
          if (diffIndex == 0 &&
              (_lastPlainText.isEmpty || _lastPlainText == "\n") &&
              char != '\n' &&
              provider.autoIndent) {
            _isAutoInserting = true;
            Future.microtask(() {
              if (mounted && _controller != null) {
                _controller!.document.insert(0, '　　');
                final currentSelection = _controller!.selection;
                _controller!.updateSelection(
                  TextSelection.collapsed(
                      offset: currentSelection.baseOffset + 2),
                  ChangeSource.local,
                );
              }
            });
          }

          // 1. 智能缩进 (处理回车换行)
          if (char == '\n' && provider.autoIndent) {
            _isAutoInserting = true;

            // 修复缩进错误放置在上一行末尾的问题：
            // quill 在插入换行符后，光标(selection.baseOffset)会准确移动到新行的开头。
            // 直接在这里插入全角空格可以保证正确作用于新生成的段落。
            int targetIndex = diffIndex;
            if (selection.isValid && selection.isCollapsed) {
              targetIndex = selection.baseOffset;
            } else {
              targetIndex = (diffIndex + 1 < plainText.length)
                  ? diffIndex + 1
                  : diffIndex;
            }

            Future.microtask(() {
              if (mounted && _controller != null) {
                _controller!.document.insert(targetIndex, '　　');
                _controller!.updateSelection(
                  TextSelection.collapsed(offset: targetIndex + 2),
                  ChangeSource.local,
                );
              }
            });
          }
          // 2. 智能标点与跳出逻辑 (仅限制单字符插入且选区折叠时)
          else if (selection.isCollapsed && lengthDiff == 1) {
            const charMap = {
              '“': '”',
              '‘': '’',
              '"': '"',
              "'": "'",
              '（': '）',
              '《': '》',
              '【': '】',
              '「': '」',
              '『': '』',
              '(': ')',
              '[': ']',
              '{': '}',
            };

            // 针对中文双标点失调进行智能翻转纠错
            String finalChar = char;
            bool isSwap = false;
            if (char == '”' || char == '’') {
              if (diffIndex == 0) {
                isSwap = true;
              } else {
                final prevChar = plainText[diffIndex - 1];
                // prevChar.trim().isEmpty correctly catches \u3000 (全角空格) which RegExp(r'\s') might miss in Dart.
                if (prevChar.trim().isEmpty ||
                    [
                      '“',
                      '《',
                      '（',
                      '‘',
                      '「',
                      '『',
                      '：',
                      ':',
                      '，',
                      ',',
                      '。',
                      '.',
                    ].contains(prevChar)) {
                  isSwap = true;
                }
              }
              if (isSwap) {
                finalChar = (char == '”') ? '“' : '‘';
              }
            }

            if (charMap.containsKey(finalChar)) {
              final closing = charMap[finalChar]!;
              if (now.difference(_lastAutoInsertTime).inMilliseconds >= 150) {
                if (!(diffIndex + 1 < plainText.length &&
                    plainText[diffIndex + 1] == closing)) {
                  _isAutoInserting = true;
                  _lastAutoInsertTime = now;
                  final targetIndex = diffIndex;
                  Future.microtask(() {
                    if (mounted && _controller != null) {
                      if (isSwap) {
                        _controller!.document.replace(
                          targetIndex,
                          1,
                          '$finalChar$closing',
                        );
                        _controller!.updateSelection(
                          TextSelection.collapsed(offset: targetIndex + 1),
                          ChangeSource.local,
                        );
                      } else {
                        _controller!.document.insert(targetIndex + 1, closing);
                        _controller!.updateSelection(
                          TextSelection.collapsed(offset: targetIndex + 1),
                          ChangeSource.local,
                        );
                      }
                    }
                  });
                }
              }
            }
            // 跳过逻辑 (Type-over)
            // 若在此处打出了闭合标点，且该处本来就有一个一模一样的标点（即形成了连续两个重复字符），则删掉多余的一个。
            else if ([
              '”',
              '’',
              '"',
              "'",
              '）',
              '》',
              '】',
              '」',
              '』',
              ')',
              ']',
              '}',
            ].contains(char)) {
              if (diffIndex > 0 && plainText[diffIndex - 1] == char) {
                _isAutoInserting = true;
                final targetIndex = diffIndex;
                Future.microtask(() {
                  if (mounted && _controller != null) {
                    _controller!.document.delete(targetIndex, 1);
                  }
                });
              }
            }
          }
        }
      }
      _lastPlainText = plainText;
    }

    _debounceSync?.cancel();
    _debounceSync = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final provider = context.read<WritingProvider>();
      final finalPlainText = _controller!.document.toPlainText();
      final cleanText = finalPlainText.endsWith('\n')
          ? finalPlainText.substring(0, finalPlainText.length - 1)
          : finalPlainText;
      provider.updateContent(cleanText);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients && _focusNode.hasFocus) {
        final provider = context.read<WritingProvider>();
        final screenHeight = MediaQuery.of(context).size.height;
        final selection = _controller!.selection;

        // 【关键修复】：只有在选区是“折叠”状态且确实发生了输入增长时才向滚动
        if (selection.isCollapsed && wasAdded) {
          final maxScroll = _scrollController.position.maxScrollExtent;
          final currentScroll = _scrollController.offset;

          if (provider.isTypewriterMode) {
            final targetScroll =
                maxScroll - (provider.typewriterOffset - 0.1) * screenHeight;

            if (maxScroll - currentScroll <
                (1.1 - provider.typewriterOffset) * screenHeight) {
              _scrollController.animateTo(
                targetScroll.clamp(0.0, maxScroll),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          }
        }
      }
    });
  }

  void flushContent() {
    if (_debounceSync?.isActive ?? false) {
      _debounceSync?.cancel();
      final provider = context.read<WritingProvider>();
      if (_controller != null) {
        final finalPlainText = _controller!.document.toPlainText();
        final cleanText = finalPlainText.endsWith('\n')
            ? finalPlainText.substring(0, finalPlainText.length - 1)
            : finalPlainText;
        provider.updateContent(cleanText);
      }
    }
  }

  void selectRange(int offset, int length) {
    if (_controller == null) return;
    _controller!.updateSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + length),
      ChangeSource.local,
    );
  }

  void scrollToMatch(int offset) {
    if (_controller == null || !_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final totalLength = _controller!.document.length;

    if (totalLength > 0) {
      // 粗略估算目标位置
      double targetScroll = (offset / totalLength) * maxScroll;

      // 稍微往上偏移一点，避免目标卡在屏幕最边缘
      final viewportHeight = _scrollController.position.viewportDimension;
      targetScroll = targetScroll - (viewportHeight * 0.3);

      _scrollController.animateTo(
        targetScroll.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void replaceSelection(String replacement) {
    if (_controller == null) return;
    final selection = _controller!.selection;
    if (selection.start < 0) return;

    _controller!.replaceText(
      selection.start,
      selection.end - selection.start,
      replacement,
      TextSelection.collapsed(offset: selection.start + replacement.length),
    );
  }

  void _copyCleanText(WritingProvider provider) async {
    if (_controller == null) return;
    final selection = _controller!.selection;
    if (selection.isCollapsed || selection.start < 0) return;

    final fullText = _controller!.document.toPlainText();
    // 确保选区在有效范围内
    final start = selection.start.clamp(0, fullText.length);
    final end = selection.end.clamp(0, fullText.length);
    String text = fullText.substring(start, end);

    // 净化排版逻辑：移除首行两个全角/半角空格
    final lines = text.split('\n');
    final cleanedLines = lines.map((line) {
      var l = line;
      if (l.startsWith('　　')) {
        l = l.substring(2);
      } else if (l.startsWith('  ')) {
        l = l.substring(2);
      }
      return l.trimRight();
    }).toList();

    final cleanText = cleanedLines.join('\n');

    await Clipboard.setData(ClipboardData(text: cleanText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已净化排版格式并复制到剪贴板'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WritingProvider>();

    if (_lastChapter != provider.currentChapterName) {
      _initController(provider.editorContent);
      _lastChapter = provider.currentChapterName;
    } else {
      // 检测内容是否被外部（如“全部替换”功能）修改了
      // 只有在当前没有处于防抖同步状态时，才强制从 Provider 同步内容，避免覆盖正在输入的文字
      final currentText = _controller?.document.toPlainText() ?? "";
      final cleanCurrentText = currentText.endsWith('\n')
          ? currentText.substring(0, currentText.length - 1)
          : currentText;

      if (provider.editorContent != cleanCurrentText &&
          !(_debounceSync?.isActive ?? false)) {
        _initController(provider.editorContent);
      }
    }

    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    _controller!.readOnly = provider.currentChapterName == null;

    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    control: true,
                  ): () {
                    provider.saveCurrentChapter();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已手动保存'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  const SingleActivator(
                    LogicalKeyboardKey.keyC,
                    control: true,
                  ): () =>
                      _copyCleanText(provider),
                  const SingleActivator(
                    LogicalKeyboardKey.keyV,
                    control: true,
                  ): () async {
                    if (_controller == null ||
                        provider.currentChapterName == null) {
                      return;
                    }
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data != null && data.text != null) {
                      final text = data.text!.replaceAll('\r\n', '\n');
                      final selection = _controller!.selection;
                      final index = selection.start;
                      final length = selection.end - selection.start;

                      _controller!.replaceText(
                        index,
                        length,
                        text,
                        TextSelection.collapsed(offset: index + text.length),
                      );
                    }
                  },
                },
                child: Container(
                  color: theme.scaffoldBackgroundColor, // The "Desk"
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 40,
                          left: 12,
                          right: 12,
                          bottom: 40, // 外部只保留必要的底部边距
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 950,
                            minHeight: screenHeight - 80, // 让纸张至少有一屏幕那么高
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: provider.customBgColor != null
                                  ? Color(provider.customBgColor!)
                                  : theme.cardColor, // The "Paper"
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(
                                    theme.brightness == Brightness.dark
                                        ? 150
                                        : 40,
                                  ),
                                  blurRadius: 25,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: QuillEditor.basic(
                                controller: _controller!,
                                focusNode: _focusNode,
                                config: QuillEditorConfig(
                                  scrollable:
                                      false, // Handled by outer SingleChildScrollView
                                  expands: false,
                                  textSelectionThemeData:
                                      TextSelectionThemeData(
                                        cursorColor: Color(
                                          provider.customAccentColor,
                                        ),
                                        selectionColor: Color(
                                          provider.customAccentColor,
                                        ).withAlpha(40),
                                      ),
                                  autoFocus: true,
                                  padding: EdgeInsets.fromLTRB(
                                    20,
                                    40,
                                    20,
                                    screenHeight * 0.7,
                                  ), // 留白减少到20，底部加入打字机偏移留白，使纸张效果延伸
                                  placeholder: "请开始写作...",
                                  customStyles: DefaultStyles(
                                    paragraph: DefaultTextBlockStyle(
                                      GoogleFonts.getFont(
                                        provider.fontFamily,
                                        fontSize: provider.fontSize,
                                        height: provider.lineHeight,
                                        fontWeight: provider.fontBold
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        letterSpacing: provider.letterSpacing
                                            .toDouble(),
                                        color: provider.customFontColor != null
                                            ? Color(provider.customFontColor!)
                                            : theme.textTheme.bodyLarge?.color,
                                      ),
                                      const HorizontalSpacing(0, 0),
                                      // 如果开启了缩进，设置较大的段间距来“视觉模拟”空行
                                      provider.autoIndent
                                          ? const VerticalSpacing(20, 0)
                                          : const VerticalSpacing(12, 0),
                                      const VerticalSpacing(0, 0),
                                      null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!provider.isZenMode) ...[
              _buildGoalProgressBar(context, provider),
            ],
          ],
        ),
        Positioned(
          top: 24,
          left: 24,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildNavButton(
                icon: Icons.undo,
                tooltip: "撤销 (Ctrl+Z)",
                onPressed: () => _controller?.undo(),
              ),
              const SizedBox(width: 8),
              _buildNavButton(
                icon: Icons.redo,
                tooltip: "恢复 (Ctrl+Y)",
                onPressed: () => _controller?.redo(),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 24,
          left: 24,
          child: _buildSessionTimer(context, provider),
        ),
        Positioned(
          top: 24,
          right: 24,
          child: IconButton(
            icon: Icon(
              provider.isZenMode ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.grey.withAlpha(provider.isZenMode ? 100 : 50),
              size: 32,
            ),
            tooltip: provider.isZenMode ? "退出沉浸模式 (F11)" : "进入沉浸模式 (F11)",
            onPressed: () {
              final isNewZen = !provider.isZenMode;
              provider.setZenMode(isNewZen);
              windowManager.setFullScreen(isNewZen);
            },
          ),
        ),
        if (provider.showDopamineBurst)
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                builder: (context, value, child) {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.amberAccent.withAlpha(
                          ((value > 0.5 ? 1.0 - value : value) * 255).toInt(),
                        ),
                        width: 8 * value,
                      ),
                      gradient: RadialGradient(
                        colors: [
                          Colors.transparent,
                          Colors.amber.withAlpha(
                            ((value > 0.5 ? 1.0 - value : value) * 0.1 * 255)
                                .toInt(),
                          ),
                        ],
                        radius: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Opacity(
                        opacity: value > 0.6
                            ? (1.0 - value) * 2.5
                            : value * 1.5,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 80,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "🎉 达成今日目标: ${provider.dailyWordGoal} 字！",
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                                shadows: [
                                  Shadow(color: Colors.black54, blurRadius: 4),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        if (!provider.isZenMode)
          Positioned(
            right: _statsOffset.dx,
            bottom: _statsOffset.dy,
            child: _buildFloatingStats(context, provider),
          ),
      ],
    );
  }

  Widget _buildGoalProgressBar(BuildContext context, WritingProvider provider) {
    double progress = provider.dailyWordGoal > 0
        ? (provider.dailyWordsAdded / provider.dailyWordGoal)
        : 0;
    progress = progress.clamp(0.0, 1.0);

    return Container(
      height: 3,
      width: double.infinity,
      color: Colors.grey.withAlpha(25),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orangeAccent.withAlpha(127), Colors.deepOrange],
            ),
          ),
        ),
      ),
    );
  }

  bool _isStatsExpanded = false;

  Widget _buildFloatingStats(BuildContext context, WritingProvider provider) {
    final typingDuration = Duration(seconds: provider.typingSeconds);
    final typingTimeStr = DateFormat(
      'HH:mm:ss',
    ).format(DateTime(0).add(typingDuration));

    final idleDuration = Duration(seconds: provider.idleSeconds);
    final idleTimeStr = DateFormat(
      'HH:mm:ss',
    ).format(DateTime(0).add(idleDuration));

    final saveTimeStr = provider.lastSaveTime != null
        ? DateFormat('HH:mm:ss').format(provider.lastSaveTime!)
        : "未保存";

    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _statsOffset = Offset(
            (_statsOffset.dx - details.delta.dx).clamp(
              0.0,
              MediaQuery.of(context).size.width - 100,
            ),
            (_statsOffset.dy - details.delta.dy).clamp(
              0.0,
              MediaQuery.of(context).size.height - 50,
            ),
          );
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_isStatsExpanded)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2C3E50).withAlpha(240),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(80),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "码字统计",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _isStatsExpanded = false),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white70,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 16),
                  _buildStatRow(
                    "本次码字",
                    "${provider.sessionWordsAdded}",
                    Colors.white,
                  ),
                  _buildStatRow(
                    "时速",
                    "${provider.writingSpeed}",
                    Colors.amberAccent,
                  ),
                  _buildStatRow("打字时间", typingTimeStr, Colors.white),
                  _buildStatRow("空闲时间", idleTimeStr, Colors.white70),
                  const Divider(color: Colors.white24, height: 16),
                  Text(
                    "💾 $saveTimeStr\n今日进度: ${provider.dailyWordsAdded} / ${provider.dailyWordGoal}",
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          GestureDetector(
            onTap: () => setState(() => _isStatsExpanded = !_isStatsExpanded),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: provider.customBgColor != null
                      ? Color(provider.customBgColor!).withAlpha(230)
                      : Theme.of(context).cardColor.withAlpha(230),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(40),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: Color(provider.customAccentColor).withAlpha(80),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      provider.isSaving
                          ? Icons.cloud_upload
                          : Icons.query_stats,
                      size: 16,
                      color: provider.isSaving
                          ? Colors.green
                          : Color(provider.customAccentColor),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "${provider.sessionWordsAdded} 字 | ${provider.writingSpeed} /时",
                      style: TextStyle(
                        color: Color(provider.customAccentColor),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTimer(BuildContext context, WritingProvider provider) {
    final duration = Duration(seconds: provider.sessionSeconds);
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black38 : Colors.black.withAlpha(15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black26,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time_filled,
            size: 16,
            color: isDark ? Colors.amberAccent : Colors.orangeAccent,
          ),
          const SizedBox(width: 8),
          Text(
            "$hours:$minutes:$seconds",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black54,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 24),
      color: Colors.grey.withAlpha(120),
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(8),
    );
  }

  Widget _buildStatRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              fontFamily: 'Courier',
            ),
          ),
        ],
      ),
    );
  }
}
