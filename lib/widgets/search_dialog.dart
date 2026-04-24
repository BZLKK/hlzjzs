import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../writing_provider.dart';
import '../main.dart'; // To access writingEditorKey

class SearchPanel extends StatefulWidget {
  final Function(Offset delta)? onDrag;
  const SearchPanel({super.key, this.onDrag});

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  final _searchController = TextEditingController();
  final _replaceController = TextEditingController();
  
  List<int> _matches = [];
  int _currentIndex = -1; // 0-based index
  
  List<String> _searchResults = [];
  bool _isSearching = false;
  String? _lastChapterName;
  String? _lastEditorContent;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    
    // 监听 Provider 状态，确保章节切换时搜索结果同步刷新
    Future.microtask(() {
      if (mounted) {
        context.read<WritingProvider>().addListener(_onProviderNotify);
      }
    });
  }

  void _onProviderNotify() {
    if (!mounted) return;
    
    final provider = context.read<WritingProvider>();
    // 只有当章节切换或者内容真的变了才需要刷新匹配项
    // 之前每秒都会通知（因为有时钟），导致不停 reset 到第 0 个，这是个巨大 Bug
    if (_lastChapterName != provider.currentChapterName || 
        _lastEditorContent != provider.editorContent) {
      
      bool chapterChanged = _lastChapterName != provider.currentChapterName;
      _lastChapterName = provider.currentChapterName;
      _lastEditorContent = provider.editorContent;
      
      _updateMatches();
      
      // 只有在自动打字或者刚切换章节时才强制高亮第 0 个
      if (chapterChanged && _matches.isNotEmpty && _searchController.text.isNotEmpty) {
        Future.microtask(() => _highlightMatch(0));
      }
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    try {
      context.read<WritingProvider>().removeListener(_onProviderNotify);
    } catch (_) {}
    _searchController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _updateMatches();
    // 实时更新高亮，让用户边打字边看到第一个匹配项
    if (_matches.isNotEmpty && _searchController.text.isNotEmpty) {
      _highlightMatch(_currentIndex >= 0 ? _currentIndex : 0);
    }
  }

  void _updateMatches() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _matches = [];
        _currentIndex = -1;
      });
      return;
    }

    final provider = context.read<WritingProvider>();
    final content = provider.editorContent.toLowerCase();
    final List<int> matches = [];
    int index = content.indexOf(query);
    while (index != -1) {
      matches.add(index);
      index = content.indexOf(query, index + query.length);
      if (index == -1) break;
    }

    setState(() {
      _matches = matches;
      if (_matches.isNotEmpty) {
        if (_currentIndex < 0 || _currentIndex >= _matches.length) {
          _currentIndex = 0;
        }
      } else {
        _currentIndex = -1;
      }
    });
  }

  void _navigate(int direction) {
    if (_matches.isEmpty) return;
    setState(() {
      _currentIndex = (_currentIndex + direction) % _matches.length;
      if (_currentIndex < 0) _currentIndex = _matches.length - 1;
    });
    _highlightMatch(_currentIndex);
  }

  void _highlightMatch(int index) {
    if (index < 0 || index >= _matches.length) return;
    final offset = _matches[index];
    final length = _searchController.text.length;
    writingEditorKey.currentState?.selectRange(offset, length);
    writingEditorKey.currentState?.scrollToMatch(offset);
  }

  void _replaceCurrent() {
    if (_currentIndex < 0) return;
    final replacement = _replaceController.text;
    writingEditorKey.currentState?.replaceSelection(replacement);
    Future.delayed(const Duration(milliseconds: 100), () {
      _updateMatches();
      if (_matches.isNotEmpty) {
          if (_currentIndex >= _matches.length) _currentIndex = _matches.length - 1;
          _highlightMatch(_currentIndex);
      }
    });
  }

  Future<void> _confirmAndReplaceAll(WritingProvider provider, bool isWholeBook) async {
    if (isWholeBook) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("确认全书替换？"),
          content: const Text("此操作将不可逆地修改整本书中的匹配内容。建议执行前先备份。是否继续？"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("取消"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text("确认替换"),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (_searchController.text.isNotEmpty) {
      await provider.replaceAll(
        _searchController.text,
        _replaceController.text,
        isWholeBook,
      );
      _updateMatches();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isWholeBook ? "全书替换已完成" : "本章替换已完成")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WritingProvider>();
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final dialogBg = isDark ? const Color(0xFF333333) : const Color(0xFFC7EDCC);
    final inputBg = isDark ? const Color(0xFF4A4A4A) : const Color(0xFFE8F5E9);
    final borderColor = isDark ? const Color(0xFF555555) : const Color(0xFFA5D6A7);
    const accentBlue = Color(0xFF4A90E2);
    final labelColor = isDark ? const Color(0xFFD8DEE9) : const Color(0xFF333333);
    final hintColor = isDark ? const Color(0xFF636D7F) : const Color(0xFF888888);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(12),
      color: dialogBg,
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          color: dialogBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor.withAlpha(50)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            GestureDetector(
              onPanUpdate: (details) => widget.onDrag?.call(details.delta),
              child: Container(
                color: Colors.transparent, // Ensure drag works on empty areas of header
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "查找替换",
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: hintColor, size: 20),
                      onPressed: () => provider.setSearchVisible(false),
                    ),
                  ],
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                children: [
                  _buildInputRow(
                    label: "查找",
                    controller: _searchController,
                    hint: "输入查找词",
                    inputBg: inputBg,
                    labelColor: labelColor,
                    hintColor: hintColor,
                    borderColor: borderColor,
                    suffix: TextButton(
                      onPressed: _isSearching ? null : () async {
                        if (_searchController.text.isEmpty) return;
                        setState(() => _isSearching = true);
                        final results = await provider.searchWholeBook(_searchController.text);
                        setState(() {
                          _searchResults = results;
                          _isSearching = false;
                        });
                        if (results.isEmpty) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("全书中未找到匹配内容")),
                            );
                          }
                        }
                      },
                      child: Text(
                        _isSearching ? "搜索中..." : "搜索全书",
                        style: const TextStyle(color: accentBlue, fontSize: 13),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  _buildInputRow(
                    label: "替换",
                    controller: _replaceController,
                    hint: "输入替换词",
                    inputBg: inputBg,
                    labelColor: labelColor,
                    hintColor: hintColor,
                    borderColor: borderColor,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  Row(
                    children: [
                      _buildNavArrow(Icons.keyboard_arrow_up, "上", hintColor, () => _navigate(-1)),
                      const SizedBox(width: 8),
                      Text(
                        _matches.isEmpty ? "0 / 0" : "${_currentIndex + 1} / ${_matches.length}",
                        style: TextStyle(color: hintColor, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      _buildNavArrow(Icons.keyboard_arrow_down, "下", hintColor, () => _navigate(1)),
                      const Spacer(),
                      _buildActionButton(
                        "替换", 
                        onPressed: _matches.isNotEmpty ? _replaceCurrent : null,
                        isPrimary: true,
                        accentColor: accentBlue,
                      ),
                      const SizedBox(width: 6),
                      _buildActionButton(
                        "本章", 
                        textColor: textColor,
                        onPressed: () => _confirmAndReplaceAll(provider, false),
                        borderColor: borderColor,
                      ),
                      const SizedBox(width: 6),
                      _buildActionButton(
                        "全书", 
                        textColor: textColor,
                        onPressed: () => _confirmAndReplaceAll(provider, true),
                        borderColor: borderColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            if (_searchResults.isNotEmpty) ...[
              Divider(color: borderColor, height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final name = _searchResults[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          name, 
                          style: TextStyle(color: textColor.withAlpha(200), fontSize: 13),
                        ),
                        trailing: Icon(Icons.chevron_right, size: 16, color: hintColor),
                        onTap: () async {
                          await provider.loadChapter(name);
                          // 切换章节后强制刷新搜索匹配（虽然 _onProviderNotify 也会做，但这里显式调用更保险且可立即高亮）
                          _updateMatches();
                          if (_matches.isNotEmpty) {
                            _highlightMatch(0);
                          }
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputRow({
    required String label,
    required TextEditingController controller,
    required String hint,
    required Color inputBg,
    required Color labelColor,
    required Color hintColor,
    required Color borderColor,
    Widget? suffix,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: TextStyle(color: labelColor, fontSize: 14),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: TextStyle(color: textColor, fontSize: 14),
                    cursorColor: textColor,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(color: hintColor, fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (suffix != null) suffix,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavArrow(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            Text(
              label,
              style: TextStyle(color: color.withAlpha(180), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    String label, {
    VoidCallback? onPressed,
    bool isPrimary = false,
    Color? accentColor,
    Color? borderColor,
    Color? textColor,
  }) {
    return SizedBox(
      height: 36,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: isPrimary ? accentColor : Colors.transparent,
          side: borderColor != null ? BorderSide(color: borderColor) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isPrimary ? Colors.white : (textColor ?? Colors.white70),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
