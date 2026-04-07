import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../writing_provider.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WritingProvider>();
    
    return AlertDialog(
      title: const Text("个性化设置"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDropdown(
              label: "字体样式",
              value: provider.fontFamily,
              items: WritingProvider.chineseFontMap.keys.toList(),
              itemLabels: WritingProvider.chineseFontMap.values.toList(),
              onChanged: (val) => provider.saveSetting('font_family', val),
            ),
            _buildSlider(
              label: "字体大小: ${provider.fontSize.round()}px",
              value: provider.fontSize,
              min: 12,
              max: 72,
              onChanged: (val) => provider.saveSetting('font_size', val),
            ),
            Row(
              children: [
                const Text("字体加粗: "),
                Checkbox(
                  value: provider.fontBold,
                  onChanged: (val) => provider.saveSetting('font_bold', val),
                ),
              ],
            ),
            _buildSlider(
              label: "行高倍数: ${provider.lineHeight.toStringAsFixed(1)}",
              value: provider.lineHeight,
              min: 1.0,
              max: 3.0,
              onChanged: (val) => provider.saveSetting('line_height', val),
            ),
            _buildSlider(
              label: "字距宽度: ${provider.letterSpacing}px",
              value: provider.letterSpacing.toDouble(),
              min: 0,
              max: 20,
              onChanged: (val) => provider.saveSetting('letter_spacing', val.toInt()),
            ),
            _buildDropdown(
              label: "主题背景色",
              value: provider.bgColorName,
              items: WritingProvider.bgColorMap.keys.toList(),
              onChanged: (val) => provider.saveSetting('bg_color_name', val),
            ),
            Row(
              children: [
                const Text("打字机模式: ", style: TextStyle(fontSize: 12, color: Colors.grey)),
                Switch(
                  value: provider.isTypewriterMode,
                  onChanged: (val) => provider.saveSetting('is_typewriter_mode', val),
                ),
                const Text(" (保持输入行在中上方)", style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            if (provider.isTypewriterMode)
              _buildSlider(
                label: "打字机定位 (距离顶部): ${(provider.typewriterOffset * 100).round()}%",
                value: provider.typewriterOffset,
                min: 0.1,
                max: 0.8,
                onChanged: (val) => provider.saveSetting('typewriter_offset', val),
              ),
            _buildDropdown(
              label: "个性文字色",
              value: provider.fontColorName,
              items: WritingProvider.fontColorMap.keys.toList(),
              onChanged: (val) => provider.saveSetting('font_color_name', val),
            ),
            _buildDropdown(
              label: "强调色（光标与选区）",
              value: provider.accentColorName,
              items: WritingProvider.accentColorMap.keys.toList(),
              onChanged: (val) => provider.saveSetting('accent_color_name', val),
            ),
            const Divider(),
            _buildDropdown(
              label: "系统主题色彩配置（控制弹窗边缘色等）",
              value: provider.themeMode,
              items: ["系统默认", "明亮模式", "暗黑模式"],
              onChanged: (val) => provider.saveSetting('theme_mode', val),
            ),
            const Divider(),
            _buildSlider(
              label: "每日码字目标: ${provider.dailyWordGoal} 字",
              value: provider.dailyWordGoal.toDouble(),
              min: 500,
              max: 20000,
              onChanged: (val) {
                int rounded = (val / 500).round() * 500;
                provider.setDailyWordGoal(rounded);
              },
            ),
            const Divider(),
            const Text("数据存储位置", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              provider.baseDirPath,
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.folder_shared, size: 16),
                label: const Text("更改存储目录"),
                onPressed: () async {
                  String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                  if (selectedDirectory != null) {
                    await provider.updateBaseDir(selectedDirectory);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("已切换至: $selectedDirectory")),
                      );
                    }
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.desktop_windows, size: 16),
                    label: const Text("导出配置到桌面"),
                    onPressed: () async {
                      await provider.exportSettingsToDesktop();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("已安全导出至桌面！")),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.file_open, size: 16),
                    label: const Text("导入配置包"),
                    onPressed: () async {
                      FilePickerResult? result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (result != null && result.files.single.path != null) {
                        await provider.importSettings(result.files.single.path!);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("配置已成功导入并刷新！")),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),

          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("关闭")),
      ],
    );
  }

  Widget _buildDropdown({required String label, required String value, required List<String> items, List<String>? itemLabels, required Function(String) onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          DropdownButton<String>(
            value: items.contains(value) ? value : items.first,
            isExpanded: true,
            items: items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final labelText = (itemLabels != null && idx < itemLabels.length) ? itemLabels[idx] : item;
              return DropdownMenuItem(value: item, child: Text(labelText));
            }).toList(),
            onChanged: (val) => val != null ? onChanged(val) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({required String label, required double value, required double min, required double max, required Function(double) onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
