from PyQt6.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QFormLayout,
    QLineEdit, QPushButton, QColorDialog, QScrollArea,
    QWidget, QMessageBox, QTabWidget, QLabel
)
from PyQt6.QtGui import QColor
from PyQt6.QtCore import Qt

class ThemeEditorDialog(QDialog):
    def __init__(self, parent, theme_manager, theme=None):
        super().__init__(parent)
        self.theme_manager = theme_manager
        self.theme = theme
        self.color_inputs = {}
        self.init_ui()

    def init_ui(self):
        title = "Theme Editor" if not self.theme else f"Edit: {self.theme['name']}"
        self.setWindowTitle(title)
        self.setMinimumSize(800, 600)

        layout = QVBoxLayout(self)

        # Theme metadata
        form = QFormLayout()

        self.name_input = QLineEdit()
        if self.theme:
            self.name_input.setText(self.theme['name'])
        form.addRow("Theme Name:", self.name_input)

        self.author_input = QLineEdit()
        if self.theme:
            self.author_input.setText(self.theme.get('author', ''))
        form.addRow("Author:", self.author_input)

        layout.addLayout(form)

        # Tabbed color inputs
        self.tabs = QTabWidget()
        layout.addWidget(self.tabs)

        if self.theme:
            self.load_colors_tabbed(self.theme['colors'])
        else:
            self.create_default_colors()

        # Buttons
        btn_layout = QHBoxLayout()

        btn_save = QPushButton("Save Theme")
        btn_save.clicked.connect(self.save_theme)
        btn_layout.addWidget(btn_save)

        btn_add = QPushButton("Add Color to Current Tab")
        btn_add.clicked.connect(self.add_new_color)
        btn_layout.addWidget(btn_add)

        btn_cancel = QPushButton("Cancel")
        btn_cancel.clicked.connect(self.reject)
        btn_layout.addWidget(btn_cancel)

        layout.addLayout(btn_layout)

    def create_default_colors(self):
        """Create default color inputs organized by app """
        default_apps = {
            'kitty': {
                'background': '#0e091d',
                'foreground': '#14B9B5',
                'selection_foreground': '#0e091d',
                'selection_background': '#14B9B5',
                'cursor': '#ff7f41',
                'cursor_text_color': '#0e091d',
                'active_tab_foreground': '#0e091d',
                'active_tab_background': '#14B9B5',
                'inactive_tab_foreground': '#0e091d',
                'inactive_tab_background': '#14B9B5',
                'color0': '#000000',
                'color1': '#c8e967',
                'color2': '#E20342',
                'color3': '#7cd699',
                'color4': '#BE3F50',
                'color5': '#9147a8',
                'color6': '#FF7F41',
                'color7': '#A60234',
                'color8': '#c53253',
                'color9': '#CE4F48',
                'color10': '#f93d3b',
                'color11': '#FD3E6A',
                'color12': '#04C5F0',
                'color13': '#6C032C',
                'color14': '#ffbe74',
                'color15': '#11AEB3',
            },
            'niri': {
                'border_width': '2.2',
                'active-color': '#BE3F50',
                'inactive-color': '#0e091d',
                'urgent-color': '#14B9B5',
            },
            'btop': {
                'main_bg': '#0e091d',
                'main_fg': '#14b9b5',
                'title': '#14b9b5',
                'hi_fg': '#ff7f41',
                'selected_bg': '#c8e967',
                'selected_fg': '#000000',
                'inactive_fg': '#c53253',
                'graph_text': '#fd3e6a',
                'meter_bg': '#918F9A',
                'proc_misc': '#7cd699',
                'cpu_box': '#e20342',
                'mem_box': '#7cd699',
                'net_box': '#917a8',
                'proc_box': '#c8e967',
                'div_line': '#a60234',
            },
            'nvim': {
                'hex_0e091d': '#0e091d',
                'hex_061F23': '#061F23',
                'hex_092F34': '#092F34',
                'hex_14B9B5': '#14B9B5',
                'hex_C8E967': '#C8E967',
                'hex_9147a8': '#9147a8',
                'hex_E20342': '#E20342',
                'hex_FF7F41': '#FF7F41',
                'hex_04C5F0': '#04C5F0',
                'hex_f93d3b': '#f93d3b',
                'hex_ffbe74': '#ffbe74',
                'hex_FD3E6A': '#FD3E6A',
                'hex_7cd699': '#7cd699',
            },
            'waybar': {
                'bg0_h': '#0e091d',
                'bg0': '#0a1528',
                'bg1': '#383450',
                'bg2': '#454063',
                'fg0': '#14b9b5',
                'gray': '#918daa',
                'border': '#BE3F50',  # This is the green color
                'red': '#cc241d',
                'yellow': '#d79921',
                'blue': '#458588',
                'purple': '#eb6f93',
                'dark_purple': '#1d062d',
                'aqua': '#689d6a',
                'orange': '#d65d0e',
                'white': '#ffffff',
                'black': '#000000',
            },
            'superfile': {
                'full_screen_fg': '#14B9B5',
                'full_screen_bg': '#0e091d',
                'gradient_0': '#14B9B5',
                'gradient_1': '#A60234',
                'file_panel_fg': '#14B9B5',
                'file_panel_bg': '#0e091d',
                'file_panel_border': '#A60234',
                'file_panel_border_active': '#BE3F50',
                'file_panel_top_directory_icon': '#000000',
                'file_panel_top_path': '#c53253',
                'file_panel_item_selected_fg': '#c53253',
                'file_panel_item_selected_bg': '#0e091d',
                'footer_fg': '#14B9B5',
                'footer_bg': '#0e091d',
                'footer_border': '#BE3F50',
                'sidebar_fg': '#14B9B5',
                'sidebar_bg': '#0e091d',
                'sidebar_title': '#11AEB3',
                'sidebar_border': '#A60234',
                'sidebar_border_active': '#BE3F50',
                'modal_fg': '#14B9B5',
                'modal_bg': '#0e091d',
                'modal_border_active': '#BE3F50',
                'cursor': '#14B9B5',
                'correct': '#E20342',
                'error': '#c8e967',
                'hint': '#FF7F41',
            },
            'rofi': {
                'background': '#0e091d',
                'background-alt': '#0a1528',
                'foreground': '#14b9b5',
                'selected': '#0ABDC6',
                'active': '#00a138',
                'urgent': '#E20342',
            },
            'dunst': {
                'frame_color': '#BE3F50',
                'urgency_low_background': '#0e091d',
                'urgency_low_foreground': '#14b9b5',
                'urgency_normal_background': '#0e091d',
                'urgency_normal_foreground': '#14b9b5',
                'urgency_critical_background': '#0e091d',
                'urgency_critical_foreground': '#14b9b5',
                'urgency_critical_frame_color': '#c8e967',
            },
        }

        for app, colors in default_apps.items():
            prefixed_colors = {f"{app}_{k}": v for k, v in colors.items()}
            self.create_tab_for_app(app, prefixed_colors)

    def load_colors_tabbed(self, colors):
        """Load colors into tabbed interface"""
        # Group colors by application
        app_colors = {}
        for key, value in colors.items():
            if '_' in key:
                app = key.split('_')[0]
                if app not in app_colors:
                    app_colors[app] = {}
                app_colors[app][key] = value
            else:
                # Colors without prefix go to "General" tab
                if 'general' not in app_colors:
                    app_colors['general'] = {}
                app_colors['general'][key] = value

        # Create tabs for each app
        for app_name in sorted(app_colors.keys()):
            self.create_tab_for_app(app_name, app_colors[app_name])

    def create_tab_for_app(self, app_name, colors):
        """Create a tab for an application's colors"""
        tab_widget = QWidget()
        tab_layout = QVBoxLayout(tab_widget)

        # Info label
        info_label = QLabel(f"Colors for {app_name.capitalize()}")
        info_label.setStyleSheet("font-weight: bold; padding: 5px;")
        tab_layout.addWidget(info_label)

        # Scrollable area for colors
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)

        color_widget = QWidget()
        color_layout = QFormLayout(color_widget)
        color_layout.setFieldGrowthPolicy(QFormLayout.FieldGrowthPolicy.AllNonFixedFieldsGrow)

        # Add color inputs
        for key, value in sorted(colors.items()):
            self.add_color_input_to_layout(key, value, color_layout)

        scroll.setWidget(color_widget)
        tab_layout.addWidget(scroll)

        self.tabs.addTab(tab_widget, app_name.capitalize())

    def add_color_input_to_layout(self, key, value, layout):
        """Add a color input field to a specific layout"""
        widget = QWidget()
        h_layout = QHBoxLayout(widget)
        h_layout.setContentsMargins(0, 0, 0, 0)

        color_input = QLineEdit(value)
        color_input.setMaximumWidth(120)
        color_input.setPlaceholderText("#RRGGBB")
        h_layout.addWidget(color_input)

        # Color preview square
        preview = QLabel()
        preview.setFixedSize(30, 30)
        preview.setStyleSheet(f"background-color: {value}; border: 1px solid #ccc;")
        h_layout.addWidget(preview)

        btn_picker = QPushButton("Pick")
        btn_picker.setMaximumWidth(60)
        btn_picker.clicked.connect(lambda: self.pick_color(color_input, preview))
        h_layout.addWidget(btn_picker)

        h_layout.addStretch()

        # Display name without prefix
        display_name = key.split('_', 1)[-1] if '_' in key else key
        layout.addRow(display_name, widget)
        self.color_inputs[key] = color_input

    def add_new_color(self):
        """Add a new color entry to current tab"""
        current_tab_index = self.tabs.currentIndex()
        if current_tab_index < 0:
            QMessageBox.warning(self, "No Tab", "Please select a tab first.")
            return

        tab_name = self.tabs.tabText(current_tab_index).lower()
        new_key = f"{tab_name}_new_color_{len(self.color_inputs)}"

        # Get the form layout from current tab
        current_widget = self.tabs.currentWidget()
        scroll = current_widget.findChild(QScrollArea)
        if scroll:
            color_widget = scroll.widget()
            form_layout = color_widget.layout()
            self.add_color_input_to_layout(new_key, "#000000", form_layout)

    def pick_color(self, input_widget, preview_widget):
        """Open color picker dialog"""
        current_color = QColor(input_widget.text() if input_widget.text().startswith('#') else "#000000")
        color = QColorDialog.getColor(current_color, self)
        if color.isValid():
            color_hex = color.name()
            input_widget.setText(color_hex)
            preview_widget.setStyleSheet(f"background-color: {color_hex}; border: 1px solid #ccc;")

    def save_theme(self):
        """Save the theme"""
        name = self.name_input.text().strip()
        if not name:
            QMessageBox.warning(self, "Invalid Name", "Please enter a theme name.")
            return

        author = self.author_input.text().strip() or "Theme Manager"

        colors = {}
        for key, input_widget in self.color_inputs.items():
            color_value = input_widget.text().strip()
            # Validate hex color
            if color_value and color_value.startswith('#') and len(color_value) in [7, 9]:
                colors[key] = color_value

        if not colors:
            QMessageBox.warning(self, "No Colors", "Please add at least one color.")
            return

        theme_data = {
            'name': name,
            'author': author,
            'variant': 'dark',
            'colors': colors
        }

        if self.theme_manager.save_theme(theme_data):
            QMessageBox.information(self, "Success", 
                f"Theme '{name}' saved successfully!\n"
                f"Total colors: {len(colors)}")
            self.accept()
        else:
            QMessageBox.warning(self, "Error", "Failed to save theme.")