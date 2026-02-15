from PyQt6.QtWidgets import QWidget, QVBoxLayout, QLabel
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor, QPalette

class ColorPreviewWidget(QWidget):
    def __init__(self, name, color_hex):
        super().__init__()
        self.color_hex = color_hex
        self.init_ui(name)

    def init_ui(self, name):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(5, 5, 5, 5)

        swatch = QWidget()
        swatch.setFixedSize(80, 60)
        swatch.setAutoFillBackground(True)

        palette = swatch.palette()
        palette.setColor(QPalette.ColorRole.Window, QColor(self.color_hex))
        swatch.setPalette(palette)

        layout.addWidget(swatch, alignment=Qt.AlignmentFlag.AlignCenter)

        name_label = QLabel(name.split('_', 1)[-1] if '_' in name else name)
        name_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        name_label.setWordWrap(True)
        layout.addWidget(name_label)

        hex_label = QLabel(self.color_hex)
        hex_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hex_label.setStyleSheet("font-family: monospace; font-size: 10px;")
        layout.addWidget(hex_label)
