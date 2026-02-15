from PyQt6.QtWidgets import (
    QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, 
    QPushButton, QListWidget, QLabel, QMessageBox,
    QGroupBox, QCheckBox, QScrollArea, QGridLayout, QInputDialog,
    QTabWidget
)
from PyQt6.QtCore import Qt

from theme_manager import ThemeManager
from gui.color_widget import ColorPreviewWidget
from gui.theme_editor import ThemeEditorDialog

class ThemeManagerWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.theme_manager = ThemeManager()
        self.init_ui()
        self.load_themes()

    def init_ui(self):
        self.setWindowTitle("Theme Manager - Niri Strix")
        self.setMinimumSize(1000, 700)

        central = QWidget()
        self.setCentralWidget(central)
        layout = QHBoxLayout(central)

        left_panel = self.create_left_panel()
        layout.addWidget(left_panel, 1)

        right_panel = self.create_right_panel()
        layout.addWidget(right_panel, 3)  # Give more space to right panel

    def create_left_panel(self):
        panel = QWidget()
        layout = QVBoxLayout(panel)

        title = QLabel("Available Themes")
        title.setStyleSheet("font-size: 16px; font-weight: bold;")
        layout.addWidget(title)

        self.theme_list = QListWidget()
        self.theme_list.currentItemChanged.connect(self.on_theme_selected)
        layout.addWidget(self.theme_list)

        btn_layout = QVBoxLayout()

        self.btn_apply = QPushButton("Apply Theme")
        self.btn_apply.clicked.connect(self.apply_theme)
        btn_layout.addWidget(self.btn_apply)

        self.btn_new = QPushButton("Create New Theme")
        self.btn_new.clicked.connect(self.create_new_theme)
        btn_layout.addWidget(self.btn_new)

        self.btn_edit = QPushButton("Edit Theme")
        self.btn_edit.clicked.connect(self.edit_theme)
        btn_layout.addWidget(self.btn_edit)

        self.btn_import = QPushButton("Import from Files")
        self.btn_import.clicked.connect(self.import_theme)
        btn_layout.addWidget(self.btn_import)

        self.btn_delete = QPushButton("Delete Theme")
        self.btn_delete.clicked.connect(self.delete_theme)
        btn_layout.addWidget(self.btn_delete)

        btn_layout.addStretch()
        layout.addLayout(btn_layout)

        return panel

    def create_right_panel(self):
        panel = QWidget()
        layout = QVBoxLayout(panel)

        # Theme info
        info_group = QGroupBox("Theme Information")
        info_layout = QVBoxLayout()

        self.lbl_theme_name = QLabel("No theme selected")
        self.lbl_theme_name.setStyleSheet("font-size: 14px; font-weight: bold;")
        info_layout.addWidget(self.lbl_theme_name)

        self.lbl_theme_author = QLabel("")
        info_layout.addWidget(self.lbl_theme_author)

        info_group.setLayout(info_layout)
        layout.addWidget(info_group)

        # Tabbed color preview
        preview_group = QGroupBox("Color Preview")
        preview_layout = QVBoxLayout()

        self.color_tabs = QTabWidget()
        preview_layout.addWidget(self.color_tabs)

        preview_group.setLayout(preview_layout)
        layout.addWidget(preview_group, stretch=2)  # Give more space

        # Application selection
        app_group = QGroupBox("Apply to Applications")
        app_layout = QGridLayout()  # Use grid for better layout

        self.app_checkboxes = {}
        apps = ["niri", "btop", "kitty", "nvim", "waybar", "superfile", "rofi", "dunst"]

        for i, app_name in enumerate(apps):
            cb = QCheckBox(app_name.capitalize())
            cb.setChecked(True)
            self.app_checkboxes[app_name] = cb
            # Arrange in 2 columns
            app_layout.addWidget(cb, i // 2, i % 2)

        app_group.setLayout(app_layout)
        layout.addWidget(app_group)

        return panel

    def load_themes(self):
        self.theme_list.clear()
        themes = self.theme_manager.list_themes()
        for theme in themes:
            self.theme_list.addItem(theme['name'])

    def on_theme_selected(self, current, previous):
        if not current:
            return

        theme_name = current.text()
        theme = self.theme_manager.get_theme(theme_name)

        if theme:
            self.lbl_theme_name.setText(theme['name'])
            self.lbl_theme_author.setText(f"Author: {theme.get('author', 'Unknown')}")
            self.update_color_preview_tabs(theme['colors'])

    def update_color_preview_tabs(self, colors):
        """Update color preview organized in tabs by application"""
        # Clear existing tabs
        self.color_tabs.clear()

        # Group colors by application
        app_colors = {}
        for key, value in colors.items():
            if not value.startswith('#'):
                continue

            # Extract app prefix
            if '_' in key:
                app = key.split('_')[0]
                if app not in app_colors:
                    app_colors[app] = []
                app_colors[app].append((key, value))

        # Create a tab for each application
        for app_name in sorted(app_colors.keys()):
            tab_widget = QWidget()
            tab_layout = QVBoxLayout(tab_widget)

            # Create scrollable area for colors
            scroll = QScrollArea()
            scroll.setWidgetResizable(True)
            scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)

            colors_widget = QWidget()
            colors_layout = QGridLayout(colors_widget)
            colors_layout.setSpacing(10)

            # Add color widgets in a grid (4 per row)
            row, col = 0, 0
            for key, value in sorted(app_colors[app_name]):
                # Display name without app prefix
                display_name = key.replace(f"{app_name}_", "")
                color_widget = ColorPreviewWidget(display_name, value)
                colors_layout.addWidget(color_widget, row, col)

                col += 1
                if col >= 4:  # 4 colors per row
                    col = 0
                    row += 1

            # Add stretch to push colors to top
            colors_layout.setRowStretch(row + 1, 1)

            scroll.setWidget(colors_widget)
            tab_layout.addWidget(scroll)

            # Add tab with capitalized app name and color count
            color_count = len(app_colors[app_name])
            self.color_tabs.addTab(tab_widget, f"{app_name.capitalize()} ({color_count})")

    def apply_theme(self):
        current = self.theme_list.currentItem()
        if not current:
            QMessageBox.warning(self, "No Theme", "Please select a theme to apply.")
            return

        theme_name = current.text()
        selected_apps = [app for app, cb in self.app_checkboxes.items() if cb.isChecked()]

        if not selected_apps:
            QMessageBox.warning(self, "No Applications", "Please select at least one application.")
            return

        success = self.theme_manager.apply_theme(theme_name, selected_apps)

        if success:
            apps_str = ", ".join(selected_apps)
            QMessageBox.information(self, "Success", 
                f"Theme '{theme_name}' applied to: {apps_str}")
        else:
            QMessageBox.warning(self, "Error", "Failed to apply theme.")

    def create_new_theme(self):
        dialog = ThemeEditorDialog(self, self.theme_manager)
        if dialog.exec():
            self.load_themes()

    def edit_theme(self):
        current = self.theme_list.currentItem()
        if not current:
            QMessageBox.warning(self, "No Theme", "Please select a theme to edit.")
            return

        theme_name = current.text()
        theme = self.theme_manager.get_theme(theme_name)

        dialog = ThemeEditorDialog(self, self.theme_manager, theme)
        if dialog.exec():
            self.load_themes()
            items = self.theme_list.findItems(theme_name, Qt.MatchFlag.MatchExactly)
            if items:
                self.theme_list.setCurrentItem(items[0])

    def import_theme(self):
        name, ok = QInputDialog.getText(self, "Import Theme", 
            "Enter theme name to search for in config files:")
        if ok and name:
            if self.theme_manager.import_from_existing(name):
                self.load_themes()
                QMessageBox.information(self, "Success", 
                    f"Imported theme '{name}' from existing config files")
            else:
                QMessageBox.warning(self, "Error", 
                    f"Could not find theme '{name}' in config files.\n"
                    f"Make sure theme files exist in your ~/.config/*/themes/ directories")

    def delete_theme(self):
        current = self.theme_list.currentItem()
        if not current:
            QMessageBox.warning(self, "No Theme", "Please select a theme to delete.")
            return

        theme_name = current.text()

        reply = QMessageBox.question(
            self, 
            "Confirm Deletion", 
            f"Are you sure you want to delete the theme '{theme_name}'?\n"
            f"This will remove it from all application theme directories.",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )

        if reply == QMessageBox.StandardButton.Yes:
            if self.theme_manager.delete_theme(theme_name):
                self.load_themes()
                QMessageBox.information(self, "Deleted", f"Theme '{theme_name}' deleted.")