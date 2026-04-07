import 'dart:io';
import 'package:flutter/material.dart';
import '../writing_provider.dart';
import 'package:path/path.dart' as p;

class HistoryDialog extends StatefulWidget {
  final WritingProvider provider;
  
  const HistoryDialog({super.key, required this.provider});

  @override
  State<HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<HistoryDialog> {
  List<File> _backups = [];
  bool _isLoading = true;
  File? _selectedFile;
  String _previewContent = "";

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final chapterName = widget.provider.currentChapterName;
    if (chapterName != null) {
      final backups = await widget.provider.getChapterHistory(chapterName);
      if (mounted) {
        setState(() {
          _backups = backups;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectBackup(File file) async {
    setState(() {
      _selectedFile = file;
    });
    try {
      final content = await file.readAsString();
      if (mounted && _selectedFile == file) {
        setState(() {
          _previewContent = content;
        });
      }
    } catch (e) {
       if (mounted) {
         setState(() {
          _previewContent = "无法读取文件...";
        });
       }
    }
  }

  String _formatBackupName(File file) {
    // Expected format: ChapterName_YYYYMMDD_HHMMSS.txt
    final basename = p.basenameWithoutExtension(file.path);
    final parts = basename.split('_');
    if (parts.length >= 3) {
      final datePart = parts[parts.length - 2];
      final timePart = parts[parts.length - 1];
      if (datePart.length == 8 && timePart.length == 6) {
        final year = datePart.substring(0, 4);
        final month = datePart.substring(4, 6);
        final day = datePart.substring(6, 8);
        final hour = timePart.substring(0, 2);
        final minute = timePart.substring(2, 4);
        final second = timePart.substring(4, 6);
        return "$year-$month-$day $hour:$minute:$second";
      }
    }
    return basename;
  }

  void _restore() {
    if (_selectedFile != null) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text("确认恢复"),
          content: const Text("确定要恢复到此版本吗？这将覆盖当前编辑器中的内容（不过系统会在覆盖前为你当前的文本生成一个最终快照防丢）。"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("取消"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
              onPressed: () async {
                Navigator.pop(dialogContext); // Close confirm dialog
                await widget.provider.restoreFromHistory(_selectedFile!);
                if (mounted) {
                  Navigator.pop(context); // Close history dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("已成功恢复历史版本")),
                  );
                }
              },
              child: const Text("确认覆盖", style: TextStyle(color: Colors.white)),
            ),
          ],
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      child: Container(
        width: 1000,
        height: 700,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "时光机 (历史版本) - ${widget.provider.currentChapterName ?? '未选择章节'}", 
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : _backups.isEmpty
                      ? const Center(child: Text("暂无历史备份版本", style: TextStyle(color: Colors.grey)))
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left column: list
                            SizedBox(
                              width: 250,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: theme.dividerColor),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ListView.separated(
                                  itemCount: _backups.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final file = _backups[index];
                                    final isSelected = file == _selectedFile;
                                    return ListTile(
                                      leading: const Icon(Icons.history, size: 20),
                                      title: Text(_formatBackupName(file), style: const TextStyle(fontSize: 14)),
                                      selected: isSelected,
                                      selectedTileColor: Colors.deepOrange.withAlpha(25),
                                      onTap: () => _selectBackup(file),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const VerticalDivider(width: 32),
                            // Right column: preview
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_selectedFile == null)
                                    const Expanded(
                                      child: Center(
                                        child: Text("请从左侧选择一个历史版本以预览内容", style: TextStyle(color: Colors.grey)),
                                      ),
                                    )
                                  else ...[
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: theme.scaffoldBackgroundColor,
                                          border: Border.all(color: theme.dividerColor),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: SingleChildScrollView(
                                          child: Text(
                                            _previewContent,
                                            style: TextStyle(
                                              fontFamily: widget.provider.fontFamily,
                                              fontSize: 16,
                                              height: 1.6,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: _restore,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.deepOrange,
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                          ),
                                          icon: const Icon(Icons.restore, color: Colors.white),
                                          label: const Text("还原此版本", style: TextStyle(color: Colors.white)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
