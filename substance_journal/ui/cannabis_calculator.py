from __future__ import annotations

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QComboBox, QDoubleSpinBox, QFormLayout, QLabel, QWidget

# Default flower weight per format, in grams - matches typical joint/blunt sizes.
FORMAT_GRAMS = {"joint": 1.0, "blunt": 2.0}


class CannabisFlowerCalculator(QWidget):
    """THC content (mg) = flower weight (g) x THC% - Joint defaults to 1g, Blunt to
    2g, and either can be overridden. This is the raw THC content of the flower
    burned, not a delivered/absorbed dose (combustion loses a large share of it),
    but it is what the user asked to calculate and is a useful, comparable number
    for logging "how strong was this joint/blunt" across different flower potencies."""

    dose_mg_changed = Signal(float)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._updating = False

        self.format_combo = QComboBox()
        self.format_combo.addItem("Joint (1g)", "joint")
        self.format_combo.addItem("Blunt (2g)", "blunt")
        self.format_combo.addItem("Custom amount", "custom")
        self.format_combo.currentIndexChanged.connect(self._on_format_changed)

        self.grams = QDoubleSpinBox()
        self.grams.setRange(0.05, 50.0)
        self.grams.setDecimals(2)
        self.grams.setSingleStep(0.25)
        self.grams.setSuffix(" g flower")
        self.grams.setValue(FORMAT_GRAMS["joint"])
        self.grams.valueChanged.connect(self._on_grams_changed)

        self.thc_percent = QDoubleSpinBox()
        self.thc_percent.setRange(0.1, 40.0)
        self.thc_percent.setDecimals(1)
        self.thc_percent.setSingleStep(0.5)
        self.thc_percent.setSuffix("% THC")
        self.thc_percent.setValue(20.0)
        self.thc_percent.valueChanged.connect(self._recompute)

        self.result_label = QLabel("")
        self.result_label.setObjectName("Muted")

        form = QFormLayout(self)
        form.setContentsMargins(0, 0, 0, 0)
        form.addRow("Format", self.format_combo)
        form.addRow("Flower amount", self.grams)
        form.addRow("Flower THC %", self.thc_percent)
        form.addRow("", self.result_label)

        self._recompute()

    def _on_format_changed(self) -> None:
        fmt = self.format_combo.currentData()
        if fmt in FORMAT_GRAMS:
            self._updating = True
            self.grams.setValue(FORMAT_GRAMS[fmt])
            self._updating = False
        self._recompute()

    def _on_grams_changed(self) -> None:
        if not self._updating:
            fmt = self.format_combo.currentData()
            if fmt in FORMAT_GRAMS and abs(self.grams.value() - FORMAT_GRAMS[fmt]) > 1e-9:
                self._updating = True
                self.format_combo.setCurrentIndex(self.format_combo.findData("custom"))
                self._updating = False
        self._recompute()

    def current_dose_mg(self) -> float:
        return self.grams.value() * (self.thc_percent.value() / 100.0) * 1000.0

    def _recompute(self) -> None:
        mg = self.current_dose_mg()
        self.result_label.setText(f"= {mg:.1f} mg total THC in the flower")
        self.dose_mg_changed.emit(mg)
