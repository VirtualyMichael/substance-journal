import sys

from PySide6.QtWidgets import QApplication

from substance_journal.ui.main_window import MainWindow
from substance_journal.ui.theme import apply_dark_theme


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("Substance Journal")
    app.setOrganizationName("Local")
    apply_dark_theme(app)

    window = MainWindow()
    window.show()
    return app.exec()
