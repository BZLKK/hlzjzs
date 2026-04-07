import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../writing_provider.dart';

class SearchDialog extends StatefulWidget {
  const SearchDialog({super.key});

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  final _searchController = TextEditingController();
  final _replaceController = TextEditingController();
  bool _isWholeBook = false;
  List<String> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<WritingProvider>();

    return AlertDialog(
      title: const Text("搜索与替换 (Ctrl+F)"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(labelText: "查找内容", hintText: "要搜索的内容..."),
            autofocus: true,
          ),
          TextField(
            controller: _replaceController,
            decoration: const InputDecoration(labelText: "替换为", hintText: "替换为..."),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text("作用范围: "),
              Expanded(
                child: DropdownButton<bool>(
                  value: _isWholeBook,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: false, child: Text("仅限本章")),
                    DropdownMenuItem(value: true, child: Text("全书范围")),
                  ],
                  onChanged: (val) => setState(() => _isWholeBook = val!),
                ),
              ),
            ],
          ),
          if (_searchResults.isNotEmpty) ...[
            const Divider(),
            const Text("搜索结果:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            SizedBox(
              height: 150,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final name = _searchResults[index];
                  return ListTile(
                    dense: true,
                    title: Text(name, style: const TextStyle(fontSize: 13)),
                    onTap: () {
                      provider.loadChapter(name);
                      Navigator.pop(context);
                    },
                    trailing: const Icon(Icons.chevron_right, size: 16),
                  );
                },
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
        TextButton(
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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("未找到匹配内容")));
              }
            }
          },
          child: Text(_isSearching ? "搜索中..." : "搜索文字"),
        ),
        ElevatedButton(
          onPressed: () {
            if (_searchController.text.isNotEmpty) {
              provider.replaceAll(
                _searchController.text,
                _replaceController.text,
                _isWholeBook,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("全部替换已完成！")),
              );
              Navigator.pop(context);
            }
          },
          child: const Text("全部替换"),
        ),
      ],
    );
  }
}
