import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../writing_provider.dart';

class ExportDialog extends StatefulWidget {
  final WritingProvider provider;
  const ExportDialog({super.key, required this.provider});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  late TextEditingController _nameController;
  String _path = "";

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.provider.currentBookName ?? "书稿导出");
    _initPath();
  }

  void _initPath() async {
    final desktop = await widget.provider.getDesktopPath();
    setState(() => _path = desktop);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("导出书稿"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: TextEditingController(text: _path),
            readOnly: true,
            decoration: const InputDecoration(
              labelText: "导出位置 (桌面)",
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
        ElevatedButton(
          onPressed: _handleExport,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
          child: const Text("开始导出 (TXT)", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  void _handleExport() async {
    final fileName = "${_nameController.text}.txt";
    final exportPath = p.join(_path, fileName);
    await widget.provider.exportBookAsTxt(exportPath);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("已导出至: $exportPath")),
      );
    }
  }
}
