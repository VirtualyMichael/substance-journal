from __future__ import annotations

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QComboBox, QDoubleSpinBox, QFormLayout, QHBoxLayout, QLabel, QWidget

# Default flower weight per format, in grams - matches typical joint/blunt sizes.
FORMAT_GRAMS = {"joint": 1.0, "blunt": 2.0}


class CannabisFlowerCalculator(QWidget):
    """Amount entry for smoked cannabis, in one of two modes:

    - Joint/Blunt: enter flower weight (g, defaulting to 1g/2g) and the flower's
      THC%; mg THC is computed automatically (grams x THC% = mg) and shown as a
      read-only result - there's no separate editable milligram field, since that
      would just be a second, redundant way to set the same number.
    - Custom: bypass the THC% calculation entirely and enter a plain amount,
      choosing whether it's in milligrams (of THC) or grams (of flower).
    """

    amount_changed = Signal(float, str)  # (amount, unit)

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
        self.grams.valueChanged.connect(self._recompute)

        self.thc_percent = QDoubleSpinBox()
        self.thc_percent.setRange(0.1, 40.0)
        self.thc_percent.setDecimals(1)
        self.thc_percent.setSingleStep(0.5)
        self.thc_percent.setSuffix("% THC")
        self.thc_percent.setValue(20.0)
        self.thc_percent.valueChanged.connect(self._recompute)

        self.computed_label = QLabel("")
        self.computed_label.setObjectName("Muted")

        self.custom_amount = QDoubleSpinBox()
        self.custom_amount.setRange(0.01, 99999.0)
        self.custom_amount.setDecimals(2)
        self.custom_amount.valueChanged.connect(self._recompute)

        self.custom_unit = QComboBox()
        self.custom_unit.addItem("mg (THC)", "mg")
        self.custom_unit.addItem("g (flower)", "g")
        self.custom_unit.currentIndexChanged.connect(self._recompute)

        custom_row = QWidget()
        custom_row_layout = QHBoxLayout(custom_row)
        custom_row_layout.setContentsMargins(0, 0, 0, 0)
        custom_row_layout.addWidget(self.custom_amount, 1)
        custom_row_layout.addWidget(self.custom_unit)

        self._grams_label = QLabel("Flower amount")
        self._thc_label = QLabel("Flower THC %")
        self._computed_row_label = QLabel("")
        self._custom_label = QLabel("Amount")

        form = QFormLayout(self)
        form.setContentsMargins(0, 0, 0, 0)
        form.addRow("Format", self.format_combo)
        form.addRow(self._grams_label, self.grams)
        form.addRow(self._thc_label, self.thc_percent)
        form.addRow(self._computed_row_label, self.computed_label)
        form.addRow(self._custom_label, custom_row)

        self._apply_mode_visibility()
        self._recompute()

    def _on_format_changed(self) -> None:
        fmt = self.format_combo.currentData()
        if fmt in FORMAT_GRAMS:
            self._updating = True
            self.grams.setValue(FORMAT_GRAMS[fmt])
            self._updating = False
        self._apply_mode_visibility()
        self._recompute()

    def _apply_mode_visibility(self) -> None:
        is_calculated = self.format_combo.currentData() in FORMAT_GRAMS
        for widget in (self._grams_label, self.grams, self._thc_label, self.thc_percent, self._computed_row_label, self.computed_label):
            widget.setVisible(is_calculated)
        for widget in (self._custom_label, self.custom_amount, self.custom_unit):
            widget.setVisible(not is_calculated)

    def current_amount(self) -> tuple[float, str]:
        if self.format_combo.currentData() in FORMAT_GRAMS:
            mg = self.grams.value() * (self.thc_percent.value() / 100.0) * 1000.0
            return mg, "mg"
        return self.custom_amount.value(), self.custom_unit.currentData()

    def _recompute(self) -> None:
        if self._updating:
            return
        amount, unit = self.current_amount()
        if unit == "mg" and self.format_combo.currentData() in FORMAT_GRAMS:
            self.computed_label.setText(f"= {amount:.1f} mg THC in the flower")
        self.amount_changed.emit(amount, unit)
