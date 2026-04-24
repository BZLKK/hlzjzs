import sys
import os
from PyQt6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                             QListWidget, QTextEdit, QPushButton, QSplitter,
                             QInputDialog, QMessageBox, QLabel, QFileDialog, QHBoxLayout,
                             QDialog, QLineEdit, QComboBox, QListWidgetItem, QFormLayout,
                             QSpinBox, QCheckBox, QDoubleSpinBox, QMenu, QFontComboBox)
from PyQt6.QtGui import QAction, QKeySequence, QShortcut, QTextCursor, QTextBlockFormat, QFont
from PyQt6.QtCore import QTimer, Qt, QSettings

class SearchReplaceDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.parent = parent
        self.setWindowTitle("搜索与替换 (Ctrl+F)")
        self.resize(350, 200)
        
        layout = QVBoxLayout(self)
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("要搜索的内容...")
        self.replace_input = QLineEdit()
        self.replace_input.setPlaceholderText("替换为...")
        
        self.scope_combo = QComboBox()
        self.scope_combo.addItems(["搜索/替换本章", "搜索/替换全书"])
        self.scope_combo.currentIndexChanged.connect(self.on_scope_changed)
        
        btn_layout = QHBoxLayout()
        self.btn_search = QPushButton("🔍 搜索")
        self.btn_replace = QPushButton("替换本章当前") 
        self.btn_replace_all = QPushButton("全部替换")
        
        btn_layout.addWidget(self.btn_search)
        btn_layout.addWidget(self.btn_replace)
        btn_layout.addWidget(self.btn_replace_all)
        
        layout.addWidget(QLabel("查找内容:"))
        layout.addWidget(self.search_input)
        layout.addWidget(QLabel("替换为:"))
        layout.addWidget(self.replace_input)
        layout.addWidget(QLabel("作用范围:"))
        layout.addWidget(self.scope_combo)
        layout.addLayout(btn_layout)

        self.btn_search.clicked.connect(self.do_search)
        self.btn_replace.clicked.connect(self.do_replace)
        self.btn_replace_all.clicked.connect(self.do_replace_all)
        
    def on_scope_changed(self, index):
        self.btn_replace.setVisible(index == 0)

    def do_search(self):
        term = self.search_input.text()
        if not term: return
        if self.scope_combo.currentIndex() == 1:
            self.parent.search_whole_book(term)
        else:
            self.parent.search_current_chapter(term)

    def do_replace(self):
        self.parent.replace_current(self.replace_input.text())

    def do_replace_all(self):
        term = self.search_input.text()
        replacement = self.replace_input.text()
        if not term: return
        is_whole_book = self.scope_combo.currentIndex() == 1
        self.parent.replace_all(term, replacement, is_whole_book)
        
    def closeEvent(self, event):
        self.parent.clear_search_filter()
        super().closeEvent(event)

class SettingsDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.parent = parent
        self.setWindowTitle("个性化设置")
        self.resize(350, 300)
        layout = QVBoxLayout(self)

        self.font_combo = QFontComboBox()
        self.font_combo.setCurrentFont(QFont(self.parent.font_family))

        self.size_spin = QSpinBox()
        self.size_spin.setRange(10, 72)
        self.size_spin.setValue(self.parent.font_size)

        self.bold_check = QCheckBox("字体加粗显示")
        self.bold_check.setChecked(self.parent.font_bold)

        self.line_height_spin = QDoubleSpinBox()
        self.line_height_spin.setRange(1.0, 3.0)
        self.line_height_spin.setSingleStep(0.1)
        self.line_height_spin.setValue(self.parent.line_height)
        
        self.letter_spacing_spin = QSpinBox()
        self.letter_spacing_spin.setRange(0, 20)
        self.letter_spacing_spin.setValue(self.parent.letter_spacing)

        self.theme_combo = QComboBox()
        self.theme_combo.addItems(["跟随系统", "明亮模式", "暗黑模式"])
        self.theme_combo.setCurrentText(self.parent.theme_mode)

        form_layout = QFormLayout()
        form_layout.addRow("字体样式:", self.font_combo)
        form_layout.addRow("字体大小 (px):", self.size_spin)
        form_layout.addRow("行高倍数 (建议1.5):", self.line_height_spin)
        form_layout.addRow("字距宽度 (px):", self.letter_spacing_spin)
        form_layout.addWidget(self.bold_check)
        form_layout.addRow("主题背景:", self.theme_combo)

        layout.addLayout(form_layout)

        btn = QPushButton("保存并应用")
        btn.clicked.connect(self.apply_settings)
        layout.addWidget(btn)

    def apply_settings(self):
        self.parent.font_family = self.font_combo.currentFont().family()
        self.parent.font_size = self.size_spin.value()
        self.parent.font_bold = self.bold_check.isChecked()
        self.parent.line_height = self.line_height_spin.value()
        self.parent.letter_spacing = self.letter_spacing_spin.value()
        self.parent.theme_mode = self.theme_combo.currentText()
        
        self.parent.settings.setValue("font_family", self.parent.font_family)
        self.parent.settings.setValue("font_size", self.parent.font_size)
        self.parent.settings.setValue("font_bold", self.parent.font_bold)
        self.parent.settings.setValue("line_height", self.parent.line_height)
        self.parent.settings.setValue("letter_spacing", self.parent.letter_spacing)
        self.parent.settings.setValue("theme_mode", self.parent.theme_mode)
        
        self.parent.apply_appearance()
        self.accept()

class NovelWriter(QMainWindow):
    def __init__(self):
        super().__init__()
        self.library_path = os.path.join(os.getcwd(), "MyLibrary")
        self.current_book_path = None
        self.current_chapter_name = None
        
        self.settings = QSettings("HongLiToolbox", "NovelWriter")
        
        self.font_family = str(self.settings.value("font_family", "微软雅黑"))
        self.font_size = int(self.settings.value("font_size", 20)) 
        bold_val = self.settings.value("font_bold", False)
        self.font_bold = bold_val.lower() == 'true' if isinstance(bold_val, str) else bool(bold_val)
        
        # 【强力洗白行高】：只要超过 2.5 倍，无视缓存，强行压回标准的 1.5 倍
        try:
            saved_line_height = float(self.settings.value("line_height", 1.5))
        except ValueError:
            saved_line_height = 1.5
        self.line_height = 1.5 if saved_line_height > 2.5 else saved_line_height
        
        self.letter_spacing = int(self.settings.value("letter_spacing", 2)) 
        self.theme_mode = str(self.settings.value("theme_mode", "跟随系统"))
        
        self.session_seconds = 0        
        self.session_words_added = 0    
        self.current_text_len = 0       
        
        self.init_env()
        self.init_ui()
        self.init_menu()
        self.init_timers()
        self.init_shortcuts()
        
        self.apply_appearance()
        self.restore_last_state()

    def init_env(self):
        if not os.path.exists(self.library_path):
            os.makedirs(self.library_path)

    def init_ui(self):
        self.setWindowTitle("极简作家助手 v9.2 (原生排版缩进版)")
        self.resize(1200, 800)
        self.splitter = QSplitter(Qt.Orientation.Horizontal)

        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        left_layout.setContentsMargins(10, 10, 0, 10)
        
        self.book_label = QLabel("当前书籍：未选择")
        self.book_label.setStyleSheet("color: #d84315; font-weight: bold; font-size: 15px; margin-bottom: 5px;")

        self.btn_new_chapter = QPushButton("➕ 新建章节")
        self.btn_new_chapter.clicked.connect(self.create_chapter)
        
        self.chapter_list = QListWidget()
        self.chapter_list.itemClicked.connect(self.load_chapter)
        self.chapter_list.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.chapter_list.customContextMenuRequested.connect(self.show_chapter_context_menu)

        left_layout.addWidget(self.book_label)
        left_layout.addWidget(self.btn_new_chapter)
        left_layout.addWidget(self.chapter_list)
        
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(0, 10, 10, 10)
        
        # 退回使用原生的 QTextEdit，因为我们有了更高级的缩进方法
        self.text_editor = QTextEdit()
        self.text_editor.setPlaceholderText("请通过左上角菜单栏【书籍管理】新建或切换书籍...")
        self.text_editor.textChanged.connect(self.on_text_changed)
        
        status_layout = QHBoxLayout()
        status_layout.setContentsMargins(10, 5, 0, 0)
        
        self.save_status_label = QLabel("状态：就绪")
        self.save_status_label.setStyleSheet("font-weight: bold; font-size: 14px;")
        
        self.stats_label = QLabel("本章: 0 | 本次: 0 | 时间: 00:00:00 | 时速: 0 字/时")
        self.stats_label.setStyleSheet("color: #2e7d32; font-weight: bold; font-size: 15px;")
        self.stats_label.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        
        status_layout.addWidget(self.save_status_label)
        status_layout.addStretch()
        status_layout.addWidget(self.stats_label)

        right_layout.addWidget(self.text_editor)
        right_layout.addLayout(status_layout)

        self.splitter.addWidget(left_widget)
        self.splitter.addWidget(right_widget)
        
        state = self.settings.value("splitter_state")
        if state:
            self.splitter.restoreState(state)
        else:
            self.splitter.setSizes([300, 900])

        self.setCentralWidget(self.splitter)

    def restore_last_state(self):
        last_book = self.settings.value("last_book")
        last_chapter = self.settings.value("last_chapter")
        if last_book:
            path = os.path.join(self.library_path, str(last_book))
            if os.path.exists(path):
                self.load_book_workspace(str(last_book), path)
                if last_chapter:
                    for i in range(self.chapter_list.count()):
                        item = self.chapter_list.item(i)
                        if item.data(Qt.ItemDataRole.UserRole) == last_chapter:
                            self.chapter_list.setCurrentItem(item)
                            self.load_chapter(item)
                            break

    def show_chapter_context_menu(self, pos):
        item = self.chapter_list.itemAt(pos)
        if not item: return
        menu = QMenu(self)
        rename_action = menu.addAction("✏️ 重命名")
        delete_action = menu.addAction("🗑️ 删除")
        action = menu.exec(self.chapter_list.mapToGlobal(pos))
        if action == rename_action:
            self.rename_chapter(item)
        elif action == delete_action:
            self.delete_chapter(item)

    def rename_chapter(self, item):
        old_name = item.data(Qt.ItemDataRole.UserRole)
        new_title, ok = QInputDialog.getText(self, "重命名章节", "请输入新章节名:", text=old_name)
        if ok and new_title and new_title != old_name:
            old_path = os.path.join(self.current_book_path, f"{old_name}.txt")
            new_path = os.path.join(self.current_book_path, f"{new_title}.txt")
            if os.path.exists(new_path):
                QMessageBox.warning(self, "错误", "该章节名已存在！")
                return
            if self.current_chapter_name == old_name:
                self.auto_save()
            os.rename(old_path, new_path)
            if self.current_chapter_name == old_name:
                self.current_chapter_name = new_title
                self.save_status_label.setText(f"正在编辑：{self.current_chapter_name}")
            self.refresh_chapter_list()
            for i in range(self.chapter_list.count()):
                if self.chapter_list.item(i).data(Qt.ItemDataRole.UserRole) == new_title:
                    self.chapter_list.setCurrentItem(self.chapter_list.item(i))
                    break

    def delete_chapter(self, item):
        chapter_name = item.data(Qt.ItemDataRole.UserRole)
        reply = QMessageBox.question(self, "确认删除", f"确定要彻底删除章节【{chapter_name}】吗？\n注意：此操作直接删除硬盘文件，不可撤销！",
                                     QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        if reply == QMessageBox.StandardButton.Yes:
            file_path = os.path.join(self.current_book_path, f"{chapter_name}.txt")
            if os.path.exists(file_path):
                os.remove(file_path)
            if self.current_chapter_name == chapter_name:
                self.text_editor.clear()
                self.current_chapter_name = None
                self.current_text_len = 0
                self.save_status_label.setText("状态：就绪")
            self.refresh_chapter_list()

    def apply_appearance(self):
        base_css = ""
        editor_bg = "background-color: transparent;"
        editor_color = ""
        
        if self.theme_mode == "暗黑模式":
            base_css = """
                QMainWindow, QWidget { background-color: #2b2b2b; color: #cfcfcf; }
                QListWidget { background-color: #1e1e1e; color: #cfcfcf; border: 1px solid #444; font-size: 15px; }
                QPushButton { background-color: #3c3f41; color: #cfcfcf; border: 1px solid #555; border-radius: 4px; padding: 10px; font-weight: bold; font-size: 14px;}
                QPushButton:hover { background-color: #4c4f51; }
                QMenuBar, QMenu { background-color: #2b2b2b; color: #cfcfcf; }
            """
            editor_bg = "background-color: #1e1e1e;"
            editor_color = "color: #cfcfcf;"
        elif self.theme_mode == "明亮模式":
            base_css = """
                QMainWindow, QWidget { background-color: #f5f5f5; color: #333333; }
                QListWidget { background-color: #ffffff; color: #333333; border: 1px solid #ccc; font-size: 15px;}
                QPushButton { background-color: #e1f5fe; color: #0277bd; border: 1px solid #b3e5fc; border-radius: 4px; padding: 10px; font-weight: bold; font-size: 14px;}
                QPushButton:hover { background-color: #b3e5fc; }
                QMenuBar, QMenu { background-color: #f5f5f5; color: #333333; }
            """
            editor_bg = "background-color: #fafafa;"
            editor_color = "color: #333333;"

        weight = "bold" if self.font_bold else "normal"
        editor_css = f"""
            QTextEdit {{
                font-family: '{self.font_family}';
                font-size: {self.font_size}px;
                font-weight: {weight};
                letter-spacing: {self.letter_spacing}px;
                padding: 20px 100px; 
                border: none;
                {editor_bg}
                {editor_color}
            }}
        """
        self.setStyleSheet(base_css + editor_css)
        self.apply_block_format()

    def apply_block_format(self):
        cursor = self.text_editor.textCursor()
        pos = cursor.position()
        cursor.select(QTextCursor.SelectionType.Document)
        
        block_fmt = QTextBlockFormat()
        # 原生设置行高
        block_fmt.setLineHeight(self.line_height * 100, 1) 
        
        # 【核心魔法】：原生设置首行缩进（以物理像素点推进，宽度约为字体大小的 2 倍）
        block_fmt.setTextIndent(self.font_size * 2)
        
        cursor.mergeBlockFormat(block_fmt)
        cursor.clearSelection()
        cursor.setPosition(pos)
        self.text_editor.setTextCursor(cursor)

    def init_shortcuts(self):
        self.shortcut_find = QShortcut(QKeySequence("Ctrl+F"), self)
        self.shortcut_find.activated.connect(self.open_search_dialog)

    def init_menu(self):
        menubar = self.menuBar()
        book_menu = menubar.addMenu("📚 书籍管理")
        book_menu.addAction("➕ 新建书籍", self.create_book)
        book_menu.addAction("🔄 切换书籍", self.switch_book)
        book_menu.addSeparator()
        book_menu.addAction("🚀 导出当前书籍为TXT", self.export_book)
        
        settings_menu = menubar.addMenu("⚙️ 设置")
        settings_menu.addAction("个性化设置", self.open_settings)

    def open_settings(self):
        dialog = SettingsDialog(self)
        dialog.exec()

    def init_timers(self):
        self.save_timer = QTimer(self)
        self.save_timer.timeout.connect(self.auto_save)
        self.save_timer.start(10000) 
        
        self.stats_timer = QTimer(self)
        self.stats_timer.timeout.connect(self.update_stats)
        self.stats_timer.start(1000)

    def open_search_dialog(self):
        if not self.current_book_path: return
        self.search_dialog = SearchReplaceDialog(self)
        self.search_dialog.show()

    def search_current_chapter(self, term):
        found = self.text_editor.find(term)
        if not found:
            self.text_editor.moveCursor(QTextCursor.MoveOperation.Start)
            found = self.text_editor.find(term)
            if not found:
                QMessageBox.information(self.search_dialog, "提示", "本章未找到该内容！")

    def search_whole_book(self, term):
        found_any = False
        for i in range(self.chapter_list.count()):
            item = self.chapter_list.item(i)
            chapter_name = item.data(Qt.ItemDataRole.UserRole)
            file_path = os.path.join(self.current_book_path, f"{chapter_name}.txt")
            with open(file_path, "r", encoding="utf-8") as f:
                if term in f.read():
                    item.setHidden(False)
                    found_any = True
                else:
                    item.setHidden(True)
        if not found_any:
             QMessageBox.information(self.search_dialog, "提示", "全书所有章节均未找到该内容！")

    def clear_search_filter(self):
        for i in range(self.chapter_list.count()):
            self.chapter_list.item(i).setHidden(False)

    def replace_current(self, replacement):
        cursor = self.text_editor.textCursor()
        if cursor.hasSelection():
            cursor.insertText(replacement)

    def replace_all(self, term, replacement, is_whole_book):
        if is_whole_book:
            reply = QMessageBox.question(self, "高危操作", f"确定要把全书所有的【{term}】替换为【{replacement}】吗？此操作不可撤销！", 
                                         QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
            if reply == QMessageBox.StandardButton.Yes:
                self.auto_save() 
                count = 0
                for f_name in os.listdir(self.current_book_path):
                    if not f_name.endswith('.txt'): continue
                    file_path = os.path.join(self.current_book_path, f_name)
                    with open(file_path, "r", encoding="utf-8") as f:
                        content = f.read()
                    if term in content:
                        count += content.count(term)
                        new_content = content.replace(term, replacement)
                        with open(file_path, "w", encoding="utf-8") as f:
                            f.write(new_content)
                QMessageBox.information(self, "成功", f"全书替换完毕，共替换了 {count} 处！\n为防止显示异常，将重新加载当前章节。")
                self.refresh_chapter_list()
                self.text_editor.clear()
                self.current_chapter_name = None
        else:
            content = self.text_editor.toPlainText()
            count = content.count(term)
            if count > 0:
                new_content = content.replace(term, replacement)
                self.text_editor.setPlainText(new_content)
                self.apply_block_format()
                QMessageBox.information(self, "成功", f"本章替换完毕，共替换了 {count} 处！")

    def get_real_text_len(self, text):
        return len(text.replace(" ", "").replace("\n", "").replace("　", "")) 

    def on_text_changed(self):
        if not self.current_chapter_name: return
        current_len = self.get_real_text_len(self.text_editor.toPlainText())
        diff = current_len - self.current_text_len
        if diff > 0:
             self.session_words_added += diff
        self.current_text_len = current_len

    def update_stats(self):
        if not self.current_book_path: return
        self.session_seconds += 1
        mins, secs = divmod(self.session_seconds, 60)
        hours, mins = divmod(mins, 60)
        time_str = f"{hours:02d}:{mins:02d}:{secs:02d}"
        speed = 0
        if self.session_seconds > 0:
            speed = int((self.session_words_added / self.session_seconds) * 3600)
        stats_text = f"本章: {self.current_text_len} | 本次: {self.session_words_added} | 时间: {time_str} | 时速: {speed} 字/时"
        self.stats_label.setText(stats_text)

    def create_book(self):
        book_name, ok = QInputDialog.getText(self, "新建书籍", "请输入新书名：")
        if ok and book_name:
            path = os.path.join(self.library_path, book_name)
            if not os.path.exists(path):
                os.makedirs(path)
                self.load_book_workspace(book_name, path)

    def switch_book(self):
        books = [d for d in os.listdir(self.library_path) if os.path.isdir(os.path.join(self.library_path, d))]
        if not books: return
        book_name, ok = QInputDialog.getItem(self, "切换书籍", "请选择书籍：", books, 0, False)
        if ok and book_name:
            path = os.path.join(self.library_path, book_name)
            self.load_book_workspace(book_name, path)

    def load_book_workspace(self, book_name, path):
        self.auto_save() 
        self.current_book_path = path
        self.settings.setValue("last_book", os.path.basename(path))
        self.book_label.setText(f"当前书籍：《{book_name}》")
        self.refresh_chapter_list()
        self.text_editor.clear()
        self.current_chapter_name = None

    def refresh_chapter_list(self):
        if not self.current_book_path: return
        self.chapter_list.clear()
        files = [f for f in os.listdir(self.current_book_path) if f.endswith('.txt')]
        files.sort()
        for f in files:
            file_path = os.path.join(self.current_book_path, f)
            with open(file_path, "r", encoding="utf-8") as file:
                word_count = self.get_real_text_len(file.read())
            clean_name = os.path.splitext(f)[0]
            display_text = f"{clean_name}  [{word_count}]"
            item = QListWidgetItem(display_text)
            item.setData(Qt.ItemDataRole.UserRole, clean_name)
            self.chapter_list.addItem(item)

    def create_chapter(self):
        if not self.current_book_path: return
        files = [f for f in os.listdir(self.current_book_path) if f.endswith('.txt')]
        prefix = f"第{len(files) + 1:03d}章"
        title, ok = QInputDialog.getText(self, "新建章节", f"前缀：{prefix}\n标题：")
        if ok:
            full_title = f"{prefix} {title}".strip() if title else prefix
            file_path = os.path.join(self.current_book_path, f"{full_title}.txt")
            if not os.path.exists(file_path):
                # 新建空文件即可，排版引擎会在显示时自动推缩进
                with open(file_path, "w", encoding="utf-8") as f: 
                    f.write("")
                self.refresh_chapter_list()
                for i in range(self.chapter_list.count()):
                    item = self.chapter_list.item(i)
                    if item.data(Qt.ItemDataRole.UserRole) == full_title:
                        self.chapter_list.setCurrentItem(item)
                        self.load_chapter(item)
                        break

    def load_chapter(self, item):
        self.auto_save() 
        self.current_chapter_name = item.data(Qt.ItemDataRole.UserRole)
        self.settings.setValue("last_chapter", self.current_chapter_name)
        file_path = os.path.join(self.current_book_path, f"{self.current_chapter_name}.txt")
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
            
        self.text_editor.blockSignals(True)
        self.text_editor.setPlainText(content)
        self.current_text_len = self.get_real_text_len(content)
        self.text_editor.blockSignals(False)
        
        # 每次载入自动给全篇应用原生排版（缩进+行高）
        self.apply_block_format()
        self.save_status_label.setText(f"正在编辑：{self.current_chapter_name}")

    def auto_save(self):
        if self.current_book_path and self.current_chapter_name:
            file_path = os.path.join(self.current_book_path, f"{self.current_chapter_name}.txt")
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(self.text_editor.toPlainText())
            import time
            self.save_status_label.setText(f"已保存 ({time.strftime('%H:%M:%S')})")
            
            for i in range(self.chapter_list.count()):
                item = self.chapter_list.item(i)
                if item.data(Qt.ItemDataRole.UserRole) == self.current_chapter_name:
                    item.setText(f"{self.current_chapter_name}  [{self.current_text_len}]")
                    break

    def export_book(self):
        if not self.current_book_path: return
        save_path, _ = QFileDialog.getSaveFileName(self, "导出全书", "", "Text Files (*.txt)")
        if save_path:
            files = [f for f in os.listdir(self.current_book_path) if f.endswith('.txt')]
            files.sort()
            with open(save_path, "w", encoding="utf-8") as out_file:
                for f_name in files:
                    chapter_title = os.path.splitext(f_name)[0]
                    with open(os.path.join(self.current_book_path, f_name), "r", encoding="utf-8") as f:
                        out_file.write(f"\n\n{chapter_title}\n\n")
                        out_file.write(f.read())
            QMessageBox.information(self, "成功", f"全书已导出！")

    def closeEvent(self, event):
        self.settings.setValue("splitter_state", self.splitter.saveState())
        self.auto_save() 
        super().closeEvent(event)

if __name__ == '__main__':
    app = QApplication(sys.argv)
    writer = NovelWriter()
    writer.show()
    sys.exit(app.exec())
