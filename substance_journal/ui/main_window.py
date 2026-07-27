from __future__ import annotations

from PySide6.QtWidgets import QLabel, QMainWindow, QVBoxLayout, QWidget


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Substance Journal")
        self.resize(1280, 820)
        self.setMinimumSize(1020, 680)

        root = QWidget()
        layout = QVBoxLayout(root)
        title = QLabel("Substance Journal")
        title.setObjectName("Title")
        subtitle = QLabel("Local multi-substance ingestion and effect journal.")
        subtitle.setObjectName("Muted")
        layout.addWidget(title)
        layout.addWidget(subtitle)
        layout.addStretch(1)
        self.setCentralWidget(root)
