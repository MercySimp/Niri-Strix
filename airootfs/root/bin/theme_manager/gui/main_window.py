from PyQt6.QtWidgets import (
    QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, 
    QPushButton, QListWidget, QLabel, QMessageBox,
    QGroupBox, QCheckBox, QScrollArea, QGridLayout, QInputDialog,
    QTabWidget, QComboBox
)
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QPixmap

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

         # ADD WALLPAPER INFO
        self.lbl_wallpaper_count = QLabel("")
        self.lbl_wallpaper_count.setStyleSheet("color: #14B9B5;")
        info_layout.addWidget(self.lbl_wallpaper_count)

        info_group.setLayout(info_layout)
        layout.addWidget(info_group)

            # ADD WALLPAPER PREVIEW SECTION
        wallpaper_group = QGroupBox("Wallpaper Preview")
        wallpaper_layout = QVBoxLayout()

        self.wallpaper_preview = QLabel("No wallpaper")
        self.wallpaper_preview.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.wallpaper_preview.setMinimumHeight(150)
        self.wallpaper_preview.setMaximumHeight(200)
        self.wallpaper_preview.setStyleSheet("border: 1px solid #555; background: #1a1a1a;")
        self.wallpaper_preview.setScaledContents(True)
        wallpaper_layout.addWidget(self.wallpaper_preview)

        # Wallpaper controls
        wp_controls = QHBoxLayout()

        self.btn_open_walls_dir = QPushButton("Open Wallpaper Folder")
        self.btn_open_walls_dir.clicked.connect(self.open_wallpaper_directory)
        wp_controls.addWidget(self.btn_open_walls_dir)

        self.btn_refresh_wallpapers = QPushButton("Refresh")
        self.btn_refresh_wallpapers.clicked.connect(self.refresh_wallpaper_preview)
        wp_controls.addWidget(self.btn_refresh_wallpapers)

        wallpaper_layout.addLayout(wp_controls)

        wallpaper_group.setLayout(wallpaper_layout)
        layout.addWidget(wallpaper_group)

        # Tabbed color preview
        preview_group = QGroupBox("Color Preview")
        preview_layout = QVBoxLayout()

        self.color_tabs = QTabWidget()
        preview_layout.addWidget(self.color_tabs)

        preview_group.setLayout(preview_layout)
        layout.addWidget(preview_group, stretch=2)  # Give more space

        # Application selection
        app_group = QGroupBox("Apply to Applications")
        app_layout = QVBoxLayout()  # Use grid for better layout

        # App checkboxes in grid
        app_grid = QGridLayout()
        self.app_checkboxes = {}
        apps = ["niri", "btop", "kitty", "nvim", "waybar", "superfile", "rofi", "dunst"]

        for i, app_name in enumerate(apps):
            cb = QCheckBox(app_name.capitalize())
            cb.setChecked(True)
            self.app_checkboxes[app_name] = cb
            app_grid.addWidget(cb, i // 2, i % 2)

        app_layout.addLayout(app_grid)

        # ADD WALLPAPER CHECKBOX AND TRANSITION
        app_layout.addSpacing(10)

        self.cb_apply_wallpaper = QCheckBox("Apply Wallpaper")
        self.cb_apply_wallpaper.setChecked(True)
        self.cb_apply_wallpaper.setStyleSheet("font-weight: bold; color: #14B9B5;")
        app_layout.addWidget(self.cb_apply_wallpaper)

        transition_layout = QHBoxLayout()
        transition_layout.addWidget(QLabel("Transition:"))

        self.transition_combo = QComboBox()
        self.transition_combo.addItems([
            "fade", "left", "right", "top", "bottom", 
            "wipe", "wave", "grow", "center", "any", "outer", "random"
        ])
        transition_layout.addWidget(self.transition_combo)
        transition_layout.addStretch()

        app_layout.addLayout(transition_layout)

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
        
        # UPDATE WALLPAPER INFO
        self.update_wallpaper_info(theme_name)

    def update_wallpaper_info(self, theme_name: str):
        """Update wallpaper preview and info"""
        wp_info = self.theme_manager.get_theme_wallpaper_info(theme_name)

        count = wp_info['count']
        if count > 0:
            self.lbl_wallpaper_count.setText(f"🖼️  {count} wallpaper{'s' if count != 1 else ''} available")

            # Show random wallpaper preview
            import random
            wallpaper = random.choice(wp_info['wallpapers'])
            pixmap = QPixmap(str(wallpaper))

            if not pixmap.isNull():
                # Scale to fit preview
                scaled = pixmap.scaled(
                    400, 200, 
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation
                )
                self.wallpaper_preview.setPixmap(scaled)
            else:
                self.wallpaper_preview.setText(f"Preview: {wallpaper.name}")
        else:
            self.lbl_wallpaper_count.setText("No wallpapers found")
            self.wallpaper_preview.setText(
                f"Add wallpapers to:\n{wp_info['directory']}"
            )

    def refresh_wallpaper_preview(self):
        """Refresh wallpaper preview"""
        current = self.theme_list.currentItem()
        if current:
            self.update_wallpaper_info(current.text())

    def open_wallpaper_directory(self):
        """Open wallpaper directory in file manager"""
        current = self.theme_list.currentItem()
        if not current:
            QMessageBox.warning(self, "No Theme", "Please select a theme first.")
            return

        theme_name = current.text()
        wp_info = self.theme_manager.get_theme_wallpaper_info(theme_name)
        wp_dir = wp_info['directory']

        # Create directory if it doesn't exist
        wp_dir.mkdir(parents=True, exist_ok=True)

        # Open in file manager
        import subprocess
        try:
            subprocess.Popen(['xdg-open', str(wp_dir)])
        except Exception as e:
            QMessageBox.information(
                self, 
                "Wallpaper Directory", 
                f"Wallpaper directory:\n{wp_dir}\n\nAdd images here for this theme."
            )
    

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

        if not selected_apps and not self.cb_apply_wallpaper.isChecked():
            QMessageBox.warning(self, "No Applications", "Please select at least one application.")
            return

        # Get wallpaper settings
        apply_wallpaper = self.cb_apply_wallpaper.isChecked()
        transition = self.transition_combo.currentText()

        success = self.theme_manager.apply_theme(
            theme_name, 
            selected_apps,
            apply_wallpaper=apply_wallpaper,
            transition=transition
        )

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
