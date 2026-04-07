import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../writing_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

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
      doc = Document()..insert(0, content);
    }

    _controller?.removeListener(_onChanged);

    if (_controller == null) {
      _controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } else {
      _controller!.document = doc;
    }

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

    final plainText = _controller!.document.toPlainText();

    bool wasAdded = false;
    if (_isAutoInserting) {
      _lastPlainText = plainText;
      _isAutoInserting = false;
    } else if (_lastPlainText != plainText) {
      wasAdded = plainText.length > _lastPlainText.length;
      final selection = _controller!.selection;
      if (selection.isCollapsed) {
        final lengthDiff = plainText.length - _lastPlainText.length;

        // 经改进：仅在输入单个字符时触发纠正与补全
        if (lengthDiff == 1) {
          int minLen = _lastPlainText.length;
          int diffIndex = 0;
          while (diffIndex < minLen && plainText[diffIndex] == _lastPlainText[diffIndex]) {
            diffIndex++;
          }
          
          if (diffIndex < plainText.length) {
            String char = plainText[diffIndex];
            
            const charMap = {
              '“': '”', '‘': '’', '"': '"', "'": "'", 
              '（': '）', '《': '》', '【': '】', '「': '」', '『': '』',
              '(': ')', '[': ']', '{': '}'
            };

            // 【智能修正逻辑】：如果由于输入法状态失调，在“开头位置”误打出了个“闭合引号”
            bool needsSwap = false;
            if (char == '”' || char == '’') {
              if (diffIndex == 0) {
                 needsSwap = true;
              } else {
                 final prevChar = plainText[diffIndex - 1];
                 if (RegExp(r'\s').hasMatch(prevChar) || ['“', '《', '（', '‘', '「', '『'].contains(prevChar)) {
                    needsSwap = true;
                 }
              }
              if (needsSwap) {
                 char = (char == '”') ? '“' : '‘';
              }
            }
            
            if (charMap.containsKey(char)) {
              final closing = charMap[char]!;
              final now = DateTime.now();
              
              // 增加时间冷却 (150ms) 和重复补全检测，彻底杜绝“三引号”顽疾
              if (now.difference(_lastAutoInsertTime).inMilliseconds < 150) {
                return;
              }
              
              // 关键预防：如果光标后面已经是这个闭合标点，则不再重复插入
              if (diffIndex + 1 < plainText.length && plainText[diffIndex + 1] == closing) {
                return;
              }

              _isAutoInserting = true;
              _lastAutoInsertTime = now;
              final targetIndex = diffIndex;
              final isSwap = needsSwap;
              final finalChar = char;
              
              Future.microtask(() {
                if (mounted && _controller != null) {
                  // 合并原子操作：如果是需要修正的，一次性替换为“开启+闭合”对
                  if (isSwap) {
                    _controller!.document.replace(targetIndex, 1, '$finalChar$closing');
                  } else {
                    // 如果不需要修正，正常插入闭合标点
                    _controller!.document.insert(targetIndex + 1, closing);
                  }
                  
                  _controller!.updateSelection(
                    TextSelection.collapsed(offset: targetIndex + 1),
                    ChangeSource.local,
                  );
                }
              });
            } 
            // B. 跳过逻辑 (Type-over)
            else if (['”', '’', '"', "'", '）', '》', '】', '」', '』', ')', ']', '}'].contains(char)) {
              if (diffIndex + 1 < plainText.length && plainText[diffIndex + 1] == char) {
                _isAutoInserting = true;
                final targetIndex = diffIndex;
                Future.microtask(() {
                  if (mounted && _controller != null) {
                    _controller!.document.delete(targetIndex + 1, 1);
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



  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WritingProvider>();

    if (_lastChapter != provider.currentChapterName) {
      _initController(provider.editorContent);
      _lastChapter = provider.currentChapterName;
    }

    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    _controller!.readOnly = provider.currentChapterName == null;

    final theme = Theme.of(context);
    final statsColor = Colors.green[700];
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
                  color: provider.customBgColor != null
                      ? Color(provider.customBgColor!)
                      : theme.scaffoldBackgroundColor,
                  child: Material(
                    color: Colors.transparent,
                    child: QuillEditor.basic(
                      controller: _controller!,
                      focusNode: _focusNode,
                      scrollController: _scrollController,
                      config: QuillEditorConfig(
                        textSelectionThemeData: TextSelectionThemeData(
                          cursorColor: Color(provider.customAccentColor),
                          selectionColor: Color(
                            provider.customAccentColor,
                          ).withAlpha(40),
                        ),
                        autoFocus: true,
                        expands: true,
                        padding: EdgeInsets.only(
                          left: 250.0,
                          right: 250.0,
                          top: 40.0,
                          bottom: screenHeight * 0.9,
                        ),
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
                              letterSpacing: provider.letterSpacing.toDouble(),
                              color: provider.customFontColor != null
                                  ? Color(provider.customFontColor!)
                                  : theme.textTheme.bodyLarge?.color,
                            ),
                            const HorizontalSpacing(0, 0),
                            const VerticalSpacing(8, 0),
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
            if (!provider.isZenMode) ...[
              _buildGoalProgressBar(context, provider),
              _buildStatusBar(context, provider, statsColor, theme),
            ],
          ],
        ),
        Positioned(
          top: 24,
          right: 24,
          child: IconButton(
            icon: Icon(
              provider.isZenMode ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.grey.withAlpha(
                provider.isZenMode ? 100 : 50,
              ),
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

  Widget _buildStatusBar(
    BuildContext context,
    WritingProvider provider,
    Color? statsColor,
    ThemeData theme,
  ) {
    final duration = Duration(seconds: provider.sessionSeconds);
    final timeStr = DateFormat('HH:mm:ss').format(DateTime(0).add(duration));
    final saveTimeStr = provider.lastSaveTime != null
        ? DateFormat('HH:mm:ss').format(provider.lastSaveTime!)
        : "未保存";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Text(
            provider.currentChapterName != null
                ? "正在编辑：${provider.currentChapterName}"
                : "状态：就绪",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            "(上次保存: $saveTimeStr)",
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          const Spacer(),
          Text(
            "时速: ${provider.writingSpeed} | 本章: ${provider.chapterWordCount} | 本次: ${provider.sessionWordsAdded} | 今日: ${provider.dailyWordsAdded}/${provider.dailyWordGoal} 字 | 时间: $timeStr",
            style: TextStyle(
              color: statsColor,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
