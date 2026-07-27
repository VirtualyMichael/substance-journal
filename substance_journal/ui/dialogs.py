from __future__ import annotations

from datetime import datetime

from PySide6.QtCore import QDateTime, Qt
from PySide6.QtWidgets import (
    QComboBox,
    QDateTimeEdit,
    QDialog,
    QDialogButtonBox,
    QDoubleSpinBox,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QVBoxLayout,
)

from substance_journal.core.database import Store
from substance_journal.core.models import EffectLog, RouteOfAdministration, SubjectiveEffect, Substance
from substance_journal.ui.cannabis_calculator import CannabisFlowerCalculator


def _format_dose(unit: str, threshold: float | None, light, common, strong, heavy: float | None) -> str:
    def fmt_range(r) -> str | None:
        if r is None:
            return None
        if r.min is not None and r.max is not None:
            return f"{r.min:g}-{r.max:g}"
        return None

    parts = []
    if threshold is not None:
        parts.append(f"Threshold: {threshold:g}{unit}")
    if fmt_range(light):
        parts.append(f"Light: {fmt_range(light)}{unit}")
    if fmt_range(common):
        parts.append(f"Common: {fmt_range(common)}{unit}")
    if fmt_range(strong):
        parts.append(f"Strong: {fmt_range(strong)}{unit}")
    if heavy is not None:
        parts.append(f"Heavy: {heavy:g}+{unit}")
    return "  |  ".join(parts) if parts else "No dosing reference data for this route."


def _format_duration(roa: RouteOfAdministration) -> str:
    def fmt_phase(phase: str, label: str) -> str | None:
        d = roa.duration(phase)
        if d is None or (d.min_minutes is None and d.max_minutes is None):
            return None
        lo, hi = d.min_minutes, d.max_minutes

        def h(minutes: float) -> str:
            if minutes < 60:
                return f"{minutes:g}m"
            return f"{minutes / 60:g}h"

        if lo is not None and hi is not None:
            return f"{label}: {h(lo)}-{h(hi)}"
        return f"{label}: ~{h(lo if lo is not None else hi)}"

    parts = [
        fmt_phase("onset", "Onset"),
        fmt_phase("comeup", "Come-up"),
        fmt_phase("peak", "Peak"),
        fmt_phase("offset", "Offset"),
        fmt_phase("total", "Total"),
        fmt_phase("afterglow", "Afterglow"),
    ]
    parts = [p for p in parts if p]
    return "  |  ".join(parts) if parts else ""


class SubstanceIngestionDialog(QDialog):
    def __init__(
        self,
        parent,
        store: Store,
        default_substance_key: str | None = None,
        default_roa_id: int | None = None,
        default_amount: float | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("Log Ingestion")
        self.setMinimumWidth(520)
        self.store = store
        self.substances: list[Substance] = store.list_substances()

        self.substance_combo = QComboBox()
        for substance in self.substances:
            self.substance_combo.addItem(substance.name, substance.key)
        self.substance_combo.currentIndexChanged.connect(self._on_substance_changed)

        self.roa_combo = QComboBox()
        self.roa_combo.currentIndexChanged.connect(self._on_roa_changed)

        self.dose_hint = QLabel("")
        self.dose_hint.setObjectName("Muted")
        self.dose_hint.setWordWrap(True)

        self.duration_hint = QLabel("")
        self.duration_hint.setObjectName("Muted")
        self.duration_hint.setWordWrap(True)

        self.amount = QDoubleSpinBox()
        self.amount.setRange(0.01, 99999.0)
        self.amount.setDecimals(2)
        self.amount.setSingleStep(1.0)

        self.cannabis_calculator = CannabisFlowerCalculator()
        self.cannabis_calculator.amount_changed.connect(self._on_cannabis_amount_changed)
        self.cannabis_calculator.setVisible(False)
        self._cannabis_amount: tuple[float, str] | None = None

        self.occurred_at = QDateTimeEdit()
        self.occurred_at.setCalendarPopup(True)
        self.occurred_at.setDisplayFormat("yyyy-MM-dd h:mm AP")
        self.occurred_at.setDateTime(QDateTime(datetime.now()))

        self.consumer = QComboBox()
        self.consumer.setEditable(True)
        self.consumer.addItems(["Me"])
        self.consumer.setCurrentText("Me")

        self.notes = QPlainTextEdit("")
        self.notes.setMaximumHeight(90)

        self._amount_label = QLabel("Amount")

        form = QFormLayout()
        form.addRow("Substance", self.substance_combo)
        form.addRow("Route", self.roa_combo)
        form.addRow("", self.dose_hint)
        form.addRow("", self.duration_hint)
        form.addRow(self._amount_label, self.amount)
        form.addRow(self.cannabis_calculator)
        form.addRow("Time", self.occurred_at)
        form.addRow("Consumer", self.consumer)
        form.addRow("Notes", self.notes)

        buttons = QDialogButtonBox(QDialogButtonBox.Save | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)

        layout = QVBoxLayout(self)
        layout.addLayout(form)
        layout.addWidget(buttons)

        default_index = 0
        if default_substance_key:
            idx = self.substance_combo.findData(default_substance_key)
            if idx >= 0:
                default_index = idx
        self.substance_combo.setCurrentIndex(default_index)
        self._on_substance_changed()
        if default_roa_id is not None:
            roa_idx = self.roa_combo.findData(default_roa_id)
            if roa_idx >= 0:
                self.roa_combo.setCurrentIndex(roa_idx)
        if default_amount is not None:
            self.amount.setValue(default_amount)

    def _current_substance(self) -> Substance:
        key = self.substance_combo.currentData()
        return next(s for s in self.substances if s.key == key)

    def _on_substance_changed(self) -> None:
        substance = self._current_substance()
        self.roa_combo.blockSignals(True)
        self.roa_combo.clear()
        for roa in substance.roas:
            self.roa_combo.addItem(roa.route.capitalize(), roa.id)
        self.roa_combo.blockSignals(False)
        self._on_roa_changed()

    def _current_roa(self) -> RouteOfAdministration | None:
        roa_id = self.roa_combo.currentData()
        if roa_id is None:
            return None
        substance = self._current_substance()
        return next((r for r in substance.roas if r.id == roa_id), None)

    def _is_cannabis_smoked(self) -> bool:
        roa = self._current_roa()
        return self._current_substance().key == "cannabis" and roa is not None and roa.route == "smoked"

    def _on_cannabis_amount_changed(self, amount: float, unit: str) -> None:
        self._cannabis_amount = (amount, unit)

    def _on_roa_changed(self) -> None:
        roa = self._current_roa()
        if roa is None:
            self.dose_hint.setText("")
            self.duration_hint.setText("")
            self.amount.setSuffix("")
            self.cannabis_calculator.setVisible(False)
            self._amount_label.setVisible(True)
            self.amount.setVisible(True)
            return
        self.amount.setSuffix(f" {roa.unit}")
        self.dose_hint.setText(
            _format_dose(roa.unit, roa.dose_threshold, roa.dose_light, roa.dose_common, roa.dose_strong, roa.dose_heavy)
        )
        self.duration_hint.setText(_format_duration(roa))

        is_cannabis_smoked = self._is_cannabis_smoked()
        self.cannabis_calculator.setVisible(is_cannabis_smoked)
        self._amount_label.setVisible(not is_cannabis_smoked)
        self.amount.setVisible(not is_cannabis_smoked)
        if is_cannabis_smoked:
            self._cannabis_amount = self.cannabis_calculator.current_amount()
        elif roa.dose_common and roa.dose_common.min is not None:
            self.amount.setValue(roa.dose_common.min)

    def result_values(self) -> dict:
        roa = self._current_roa()
        if self._is_cannabis_smoked() and self._cannabis_amount is not None:
            amount, unit = self._cannabis_amount
        else:
            amount, unit = self.amount.value(), (roa.unit if roa else "")
        return {
            "substance_key": self._current_substance().key,
            "roa_id": roa.id if roa else None,
            "amount": amount,
            "unit": unit,
            "occurred_at": self.occurred_at.dateTime().toPython(),
            "consumer": self.consumer.currentText().strip() or "Me",
            "notes": self.notes.toPlainText().strip(),
        }


class SubstancePresetDialog(QDialog):
    def __init__(self, parent, store: Store, default_substance_key: str | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("New Custom Preset")
        self.setMinimumWidth(420)
        self.store = store
        self.substances: list[Substance] = store.list_substances()

        self.name = QLineEdit("")
        self.name.setPlaceholderText("e.g. My usual bowl")

        self.substance_combo = QComboBox()
        for substance in self.substances:
            self.substance_combo.addItem(substance.name, substance.key)
        self.substance_combo.currentIndexChanged.connect(self._on_substance_changed)

        self.roa_combo = QComboBox()
        self.roa_combo.currentIndexChanged.connect(self._on_roa_changed)

        self.amount = QDoubleSpinBox()
        self.amount.setRange(0.01, 99999.0)
        self.amount.setDecimals(2)

        form = QFormLayout()
        form.addRow("Preset name", self.name)
        form.addRow("Substance", self.substance_combo)
        form.addRow("Route", self.roa_combo)
        form.addRow("Amount", self.amount)

        buttons = QDialogButtonBox(QDialogButtonBox.Save | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self._on_accept)
        buttons.rejected.connect(self.reject)

        layout = QVBoxLayout(self)
        layout.addLayout(form)
        layout.addWidget(buttons)

        default_index = 0
        if default_substance_key:
            idx = self.substance_combo.findData(default_substance_key)
            if idx >= 0:
                default_index = idx
        self.substance_combo.setCurrentIndex(default_index)
        self._on_substance_changed()

    def _current_substance(self) -> Substance:
        key = self.substance_combo.currentData()
        return next(s for s in self.substances if s.key == key)

    def _on_substance_changed(self) -> None:
        substance = self._current_substance()
        self.roa_combo.blockSignals(True)
        self.roa_combo.clear()
        for roa in substance.roas:
            self.roa_combo.addItem(roa.route.capitalize(), roa.id)
        self.roa_combo.blockSignals(False)
        self._on_roa_changed()

    def _on_roa_changed(self) -> None:
        roa = self._current_roa()
        self.amount.setSuffix(f" {roa.unit}" if roa else "")
        if roa and roa.dose_common and roa.dose_common.min is not None:
            self.amount.setValue(roa.dose_common.min)

    def _current_roa(self) -> RouteOfAdministration | None:
        roa_id = self.roa_combo.currentData()
        if roa_id is None:
            return None
        substance = self._current_substance()
        return next((r for r in substance.roas if r.id == roa_id), None)

    def _on_accept(self) -> None:
        if not self.name.text().strip():
            QMessageBox.warning(self, "Name required", "Enter a name for this preset.")
            return
        self.accept()

    def result_values(self) -> dict:
        roa = self._current_roa()
        return {
            "name": self.name.text().strip(),
            "substance_key": self._current_substance().key,
            "roa_id": roa.id if roa else None,
            "amount": self.amount.value(),
        }


class EffectPickerDialog(QDialog):
    """Browse/search the Subjective Effect Index and tag effects against a session
    as they happen. Stays open after each tag so multiple effects can be logged in
    quick succession without reopening the dialog - matches PsychonautWiki Journal's
    in-the-moment tagging flow."""

    def __init__(self, parent, store: Store, session_id: int) -> None:
        super().__init__(parent)
        self.setWindowTitle("Log Subjective Effect")
        self.setMinimumSize(560, 620)
        self.store = store
        self.session_id = session_id
        self.effects: list[SubjectiveEffect] = store.list_effects()
        self.logged_count = 0

        self.search = QLineEdit("")
        self.search.setPlaceholderText("Search effects...")
        self.search.textChanged.connect(self._refresh_list)

        self.category_combo = QComboBox()
        self.category_combo.addItem("All categories", None)
        for category in sorted({e.category for e in self.effects}):
            self.category_combo.addItem(category, category)
        self.category_combo.currentIndexChanged.connect(self._refresh_list)

        self.intensity_combo = QComboBox()
        self.intensity_combo.addItem("No intensity", None)
        self.intensity_combo.addItem("Light", "light")
        self.intensity_combo.addItem("Common", "common")
        self.intensity_combo.addItem("Strong", "strong")

        filter_row = QHBoxLayout()
        filter_row.addWidget(self.search, 1)
        filter_row.addWidget(self.category_combo)

        self.effect_list = QListWidget()
        self.effect_list.itemDoubleClicked.connect(self._log_selected)

        self.description_label = QLabel("")
        self.description_label.setObjectName("Muted")
        self.description_label.setWordWrap(True)
        self.effect_list.currentItemChanged.connect(self._on_selection_changed)

        self.status_label = QLabel("")
        self.status_label.setObjectName("Muted")

        log_button = QPushButton("Log This Effect")
        log_button.setObjectName("PrimaryButton")
        log_button.clicked.connect(self._log_selected)
        done_button = QPushButton("Done")
        done_button.clicked.connect(self.accept)

        action_row = QHBoxLayout()
        action_row.addWidget(self.intensity_combo)
        action_row.addStretch(1)
        action_row.addWidget(log_button)
        action_row.addWidget(done_button)

        layout = QVBoxLayout(self)
        layout.addLayout(filter_row)
        layout.addWidget(self.effect_list, 1)
        layout.addWidget(self.description_label)
        layout.addWidget(self.status_label)
        layout.addLayout(action_row)

        self._refresh_list()

    def _refresh_list(self) -> None:
        query = self.search.text().strip().lower()
        category = self.category_combo.currentData()
        self.effect_list.clear()
        for effect in self.effects:
            if category and effect.category != category:
                continue
            if query and query not in effect.name.lower():
                continue
            label = effect.name
            if effect.subcategory:
                label += f"  ({effect.subcategory})"
            item = QListWidgetItem(label)
            item.setData(Qt.UserRole, effect.id)
            self.effect_list.addItem(item)

    def _selected_effect(self) -> SubjectiveEffect | None:
        item = self.effect_list.currentItem()
        if item is None:
            return None
        effect_id = item.data(Qt.UserRole)
        return next((e for e in self.effects if e.id == effect_id), None)

    def _on_selection_changed(self) -> None:
        effect = self._selected_effect()
        self.description_label.setText(effect.description or "" if effect else "")

    def _log_selected(self) -> None:
        effect = self._selected_effect()
        if effect is None:
            return
        self.store.add_effect_log(
            EffectLog(
                id=None,
                session_id=self.session_id,
                effect_id=effect.id,
                occurred_at=datetime.now(),
                intensity=self.intensity_combo.currentData(),
            )
        )
        self.logged_count += 1
        self.status_label.setText(f"Logged “{effect.name}” at {datetime.now().strftime('%I:%M %p').lstrip('0')}")
