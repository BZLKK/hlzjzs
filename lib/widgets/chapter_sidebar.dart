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
        border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBookHeader(context, provider),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _showNewChapterDialog(context, provider),
            icon: const Icon(Icons.add),
            label: const Text("新建章节"),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: chapters.length,
              onReorder: (oldIndex, newIndex) => provider.reorderChapters(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final isSelected = provider.currentChapterName == chapter.name;
                final isDarkMode = Theme.of(context).brightness == Brightness.dark;
                
                return GestureDetector(
                  key: ValueKey(chapter.name),
                  onSecondaryTapDown: (details) => _showDesktopMenu(context, provider, chapter, details.globalPosition),
                  child: ListTile(
                    title: Text(chapter.name, style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected 
                        ? (isDarkMode ? Colors.orangeAccent : Theme.of(context).primaryColor)
                        : (isDarkMode ? Colors.white70 : Colors.black87),
                    )),
                    subtitle: Text("${chapter.wordCount} 字", style: TextStyle(
                      color: isDarkMode ? Colors.white38 : Colors.black38,
                      fontSize: 12,
                    )),
                    selected: isSelected,
                    onTap: () {
                      writingEditorKey.currentState?.flushContent();
                      provider.loadChapter(chapter.name);
                    },
                    onLongPress: () => _showContextMenu(context, provider, chapter),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("当前书籍：", style: TextStyle(fontSize: 12, color: Colors.grey)),
            IconButton(
              icon: const Icon(Icons.settings, size: 16),
              onPressed: () => _showBookManagement(context, provider),
              tooltip: "书籍管理",
            ),
          ],
        ),
        Text(
          provider.currentBookName != null ? "《${provider.currentBookName}》" : "未选择",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepOrange),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text("排序: ", style: TextStyle(fontSize: 10, color: Colors.grey)),
            IconButton(
              icon: const Icon(Icons.sort_by_alpha, size: 14),
              onPressed: () => provider.sortChapters(true),
              tooltip: "名称升序",
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.sort, size: 14),
              onPressed: () => provider.sortChapters(false),
              tooltip: "名称降序",
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ],
    );
  }

  void _showDesktopMenu(BuildContext context, WritingProvider provider, Chapter chapter, Offset position) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect positionRect = RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Offset.zero & overlay.size,
    );

    final result = await showMenu<String>(
      context: context,
      position: positionRect,
      items: [
        const PopupMenuItem(value: 'rename', child: Text('✏️ 重命名')),
        const PopupMenuItem(value: 'delete', child: Text('🗑️ 删除', style: TextStyle(color: Colors.red))),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请先选择或新建一本书籍")));
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
            TextButton(
              onPressed: submit,
              child: const Text("确定"),
            ),
          ],
        );
      },
    );
  }

  void _showContextMenu(BuildContext context, WritingProvider provider, Chapter chapter) {
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

  void _showRenameDialog(BuildContext context, WritingProvider provider, Chapter chapter) {
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
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

  void _showDeleteConfirm(BuildContext context, WritingProvider provider, Chapter chapter) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("确认删除"),
        content: Text("确定要彻底删除章节【${chapter.name}】吗？此操作无法撤销。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
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
                      trailing: provider.currentBookName == book ? const Icon(Icons.check, color: Colors.green) : null,
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
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

  void _showRenameBookDialog(BuildContext context, WritingProvider provider, String name) {
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
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
