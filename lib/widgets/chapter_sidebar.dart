import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../writing_provider.dart';
import '../main.dart';

class ChapterSidebar extends StatelessWidget {
  const ChapterSidebar({super.key});

  String _sanitizeName(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WritingProvider>();
    final chapters = provider.chapters;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      padding: const EdgeInsets.only(top: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildBookHeader(context, provider),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(height: 1),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildChapterListHeader(context, provider),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 4.0,
              ),
              itemCount: chapters.length,
              onReorder: (oldIndex, newIndex) =>
                  provider.reorderChapters(oldIndex, newIndex),
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final isSelected = provider.currentChapterName == chapter.name;
                final isDarkMode =
                    Theme.of(context).brightness == Brightness.dark;

                return ReorderableDragStartListener(
                  key: ValueKey(chapter.name),
                  index: index,
                  child: GestureDetector(
                    onSecondaryTapDown: (details) => _showDesktopMenu(
                      context,
                      provider,
                      chapter,
                      details.globalPosition,
                    ),
                    onLongPress: () =>
                        _showContextMenu(context, provider, chapter),
                    onTap: () {
                      writingEditorKey.currentState?.flushContent();
                      provider.loadChapter(chapter.name);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDarkMode
                                  ? Colors.white12
                                  : Colors.black.withAlpha(12))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 16,
                            color: isSelected
                                ? (isDarkMode
                                      ? Colors.orangeAccent
                                      : Theme.of(context).primaryColor)
                                : (isDarkMode
                                      ? Colors.white38
                                      : Colors.black38),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              chapter.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? (isDarkMode
                                          ? Colors.orangeAccent
                                          : Theme.of(context).primaryColor)
                                    : (isDarkMode
                                          ? Colors.white70
                                          : Colors.black87),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "${chapter.wordCount}",
                            style: TextStyle(
                              color: isDarkMode
                                  ? Colors.white38
                                  : Colors.black38,
                              fontSize: 10,
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
        ],
      ),
    );
  }

  Widget _buildBookHeader(BuildContext context, WritingProvider provider) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => _showBookManagement(context, provider),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white10 : Colors.black.withAlpha(10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(Icons.menu_book, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                provider.currentBookName ?? "尚未选择书籍",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterListHeader(
    BuildContext context,
    WritingProvider provider,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "章节目录",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.sort, size: 14),
              onPressed: () => provider.sortChapters(false), // Descending
              tooltip: "名称降序 (最新在最上)",
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.sort_by_alpha, size: 14),
              onPressed: () => provider.sortChapters(true), // Ascending
              tooltip: "名称升序",
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Builder(
              builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final iconColor = isDark ? Colors.orangeAccent : Theme.of(context).primaryColor;
                final bgColor = isDark 
                    ? Colors.orangeAccent.withAlpha(50) 
                    : Theme.of(context).primaryColor.withAlpha(20);

                return InkWell(
                  onTap: () => _showNewChapterDialog(context, provider),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      Icons.add,
                      size: 16,
                      color: iconColor,
                    ),
                  ),
                );
              }
            ),
          ],
        ),
      ],
    );
  }

  void _showDesktopMenu(
    BuildContext context,
    WritingProvider provider,
    Chapter chapter,
    Offset position,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect positionRect = RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Offset.zero & overlay.size,
    );

    final result = await showMenu<String>(
      context: context,
      position: positionRect,
      items: [
        const PopupMenuItem(value: 'rename', child: Text('✏️ 重命名')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('🗑️ 删除', style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (result == 'rename') {
      if (!context.mounted) return;
      _showRenameDialog(context, provider, chapter);
    } else if (result == 'delete') {
      if (!context.mounted) return;
      _showDeleteConfirm(context, provider, chapter);
    }
  }

  void _showNewChapterDialog(BuildContext context, WritingProvider provider) {
    if (provider.currentBookName == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请先选择或新建一本书籍")));
      return;
    }
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        void submit() {
          final sName = _sanitizeName(controller.text);
          provider.createChapter(sName.isNotEmpty ? sName : controller.text);
          if (context.mounted) Navigator.pop(context);
        }

        return AlertDialog(
          title: const Text("新建章节"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: "请输入标题 (留空自动生成)"),
            autofocus: true,
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("取消"),
            ),
            TextButton(onPressed: submit, child: const Text("确定")),
          ],
        );
      },
    );
  }

  void _showContextMenu(
    BuildContext context,
    WritingProvider provider,
    Chapter chapter,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text("重命名"),
            onTap: () {
              Navigator.pop(context);
              _showRenameDialog(context, provider, chapter);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text("删除"),
            onTap: () {
              Navigator.pop(context);
              _showDeleteConfirm(context, provider, chapter);
            },
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    WritingProvider provider,
    Chapter chapter,
  ) {
    final controller = TextEditingController(text: chapter.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("重命名章节"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "新章节标题"),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              final sName = _sanitizeName(controller.text);
              if (sName.isNotEmpty && sName != chapter.name) {
                provider.renameChapter(chapter.name, sName);
                Navigator.pop(context);
              }
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(
    BuildContext context,
    WritingProvider provider,
    Chapter chapter,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("确认删除"),
        content: Text("确定要彻底删除章节【${chapter.name}】吗？此操作无法撤销。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              provider.deleteChapter(chapter.name);
              Navigator.pop(context);
            },
            child: const Text("删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showBookManagement(BuildContext context, WritingProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("书籍管理"),
        content: SizedBox(
          width: 300,
          height: 400,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text("新建书籍"),
                onTap: () {
                  Navigator.pop(context);
                  _showNewBookDialog(context, provider);
                },
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: provider.books.length,
                  itemBuilder: (context, index) {
                    final book = provider.books[index];
                    return ListTile(
                      title: Text(book),
                      leading: IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () {
                          Navigator.pop(context);
                          _showRenameBookDialog(context, provider, book);
                        },
                      ),
                      trailing: provider.currentBookName == book
                          ? const Icon(Icons.check, color: Colors.green)
                          : null,
                      onTap: () {
                        writingEditorKey.currentState?.flushContent();
                        provider.loadBook(book);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNewBookDialog(BuildContext context, WritingProvider provider) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("新建书籍"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "请输入书名"),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              final sName = _sanitizeName(controller.text);
              if (sName.isNotEmpty) {
                provider.createBook(sName);
                Navigator.pop(context);
              }
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }

  void _showRenameBookDialog(
    BuildContext context,
    WritingProvider provider,
    String name,
  ) {
    final controller = TextEditingController(text: name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("重命名书籍"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "书名"),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              final sName = _sanitizeName(controller.text);
              if (sName.isNotEmpty) {
                provider.renameBook(name, sName);
                Navigator.pop(context);
              }
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }
}
