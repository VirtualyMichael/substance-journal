from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QComboBox,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from substance_journal.core.database import Store
from substance_journal.core.interactions import check_new_ingestion
from substance_journal.core.models import EffectLog, Ingestion, SubjectiveEffect, SubstancePreset
from substance_journal.core.paths import default_db_path
from substance_journal.ui.dialogs import EffectPickerDialog, SubstanceIngestionDialog, SubstancePresetDialog


class MainWindow(QMainWindow):
    def __init__(self, store: Store | None = None) -> None:
        super().__init__()
        self.store = store or Store(default_db_path())
        self.current_consumer = "Me"
        self.selected_session_id: int | None = None

        self.setWindowTitle("Substance Journal")
        self.resize(1280, 820)
        self.setMinimumSize(1020, 680)
        self.setCentralWidget(self._build_content())
        self.refresh_all()

    def _build_content(self) -> QWidget:
        root = QWidget()
        layout = QGridLayout(root)
        layout.setContentsMargins(18, 18, 18, 18)
        layout.setHorizontalSpacing(16)
        layout.setVerticalSpacing(16)
        layout.setColumnStretch(0, 0)
        layout.setColumnStretch(1, 1)
        layout.setRowStretch(1, 1)

        self.session_title = QLabel("No session selected")
        self.session_title.setObjectName("Title")
        self.session_summary = QLabel("")
        self.session_summary.setObjectName("Muted")
        self.sessions_list = QListWidget()
        self.ingestion_list = QListWidget()
        self.effect_log_list = QListWidget()

        layout.addWidget(self._build_header(), 0, 0, 1, 2)
        layout.addWidget(self._build_sidebar(), 1, 0)
        layout.addWidget(self._build_main_panel(), 1, 1)
        return root

    def _build_header(self) -> QWidget:
        frame = QWidget()
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(0, 0, 0, 0)

        title = QLabel("Substance Journal")
        title.setObjectName("Title")
        subtitle = QLabel("Local multi-substance ingestion and effect journal")
        subtitle.setObjectName("Muted")
        text_layout = QVBoxLayout()
        text_layout.setSpacing(2)
        text_layout.addWidget(title)
        text_layout.addWidget(subtitle)

        add_button = QPushButton("+ Ingestion")
        add_button.setObjectName("PrimaryButton")
        add_button.clicked.connect(self.add_ingestion)
        log_effect_button = QPushButton("Log Effect")
        log_effect_button.clicked.connect(self.log_effect)
        self.log_effect_button = log_effect_button
        end_session_button = QPushButton("End Session")
        end_session_button.clicked.connect(self.end_selected_session)
        self.end_session_button = end_session_button
        delete_button = QPushButton("Delete Ingestion")
        delete_button.clicked.connect(self.delete_selected_ingestion)

        top_row = QHBoxLayout()
        top_row.addLayout(text_layout)
        top_row.addStretch(1)
        top_row.addWidget(delete_button)
        top_row.addWidget(end_session_button)
        top_row.addWidget(log_effect_button)
        top_row.addWidget(add_button)

        self.quick_add_row = QWidget()
        self.quick_add_layout = QHBoxLayout(self.quick_add_row)
        self.quick_add_layout.setContentsMargins(0, 8, 0, 0)

        self.recent_effects_row = QWidget()
        self.recent_effects_layout = QHBoxLayout(self.recent_effects_row)
        self.recent_effects_layout.setContentsMargins(0, 4, 0, 0)

        layout.addLayout(top_row)
        layout.addWidget(self.quick_add_row)
        layout.addWidget(self.recent_effects_row)
        return frame

    def _build_sidebar(self) -> QFrame:
        frame = QFrame()
        frame.setObjectName("Panel")
        frame.setFixedWidth(320)
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(14, 14, 14, 14)
        layout.setSpacing(10)

        title = QLabel("Sessions")
        title.setObjectName("SectionTitle")
        hint = QLabel("Select a session to review or add to it.")
        hint.setObjectName("Muted")
        hint.setWordWrap(True)

        self.consumer_filter = QComboBox()
        self.consumer_filter.currentTextChanged.connect(self.set_consumer)

        self.sessions_list.currentRowChanged.connect(self.select_session_by_row)

        layout.addWidget(title)
        layout.addWidget(self.consumer_filter)
        layout.addWidget(hint)
        layout.addWidget(self.sessions_list, 1)
        return frame

    def _build_main_panel(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("Panel")
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(14, 14, 14, 14)
        layout.setSpacing(10)
        layout.addWidget(self.session_title)
        layout.addWidget(self.session_summary)

        lists_row = QHBoxLayout()
        ingestions_column = QVBoxLayout()
        ingestions_label = QLabel("Ingestions")
        ingestions_label.setObjectName("SectionTitle")
        ingestions_column.addWidget(ingestions_label)
        ingestions_column.addWidget(self.ingestion_list, 1)

        effects_column = QVBoxLayout()
        effects_label = QLabel("Subjective Effects")
        effects_label.setObjectName("SectionTitle")
        effects_column.addWidget(effects_label)
        effects_column.addWidget(self.effect_log_list, 1)

        lists_row.addLayout(ingestions_column, 1)
        lists_row.addLayout(effects_column, 1)
        layout.addLayout(lists_row, 1)
        return frame

    # ---- refresh ----

    def refresh_all(self) -> None:
        self._refresh_consumer_filter()
        self.refresh_quick_add_row()
        self.refresh_recent_effects_row()
        self.refresh_sessions()

    def _refresh_consumer_filter(self) -> None:
        self.consumer_filter.blockSignals(True)
        consumers = ["All"] + self.store.list_consumers()
        if self.current_consumer not in consumers:
            consumers.append(self.current_consumer)
        self.consumer_filter.clear()
        self.consumer_filter.addItems(consumers)
        self.consumer_filter.setCurrentText(self.current_consumer)
        self.consumer_filter.blockSignals(False)

    def set_consumer(self, consumer: str) -> None:
        self.current_consumer = consumer
        self.refresh_sessions()

    def refresh_sessions(self) -> None:
        self.sessions_list.blockSignals(True)
        self.sessions_list.clear()
        sessions = self.store.list_sessions(self.current_consumer)
        for session in sessions:
            ingestions = self.store.list_ingestions_for_session(session.id)
            substances = ", ".join(sorted({i.substance_key for i in ingestions})) or "no ingestions yet"
            status = "OPEN" if session.ended_at is None else "closed"
            label = (
                f"{session.consumer} — {session.started_at.strftime('%a %d %b, %I:%M %p').replace(' 0', ' ')} [{status}]\n"
                f"{substances}"
            )
            item = QListWidgetItem(label)
            item.setData(Qt.UserRole, session.id)
            self.sessions_list.addItem(item)

        row_to_select = 0
        for row in range(self.sessions_list.count()):
            if self.sessions_list.item(row).data(Qt.UserRole) == self.selected_session_id:
                row_to_select = row
                break
        if self.sessions_list.count() > 0:
            self.sessions_list.setCurrentRow(row_to_select)
        else:
            self.selected_session_id = None
            self.refresh_selected_session()
        self.sessions_list.blockSignals(False)
        if self.sessions_list.count() > 0:
            self.select_session_by_row(row_to_select)

    def select_session_by_row(self, row: int) -> None:
        if row < 0:
            self.selected_session_id = None
            self.refresh_selected_session()
            return
        session_id = self.sessions_list.item(row).data(Qt.UserRole)
        self.selected_session_id = session_id
        self.refresh_selected_session()

    def refresh_selected_session(self) -> None:
        self.ingestion_list.clear()
        self.effect_log_list.clear()
        session = self.store.get_session(self.selected_session_id) if self.selected_session_id else None
        if session is None:
            self.session_title.setText("No session selected")
            self.session_summary.setText("Log an ingestion to start a new session.")
            self.end_session_button.setEnabled(False)
            self.log_effect_button.setEnabled(False)
            return

        substances_by_key = {s.key: s for s in self.store.list_substances()}
        ingestions = self.store.list_ingestions_for_session(session.id)
        for ingestion in ingestions:
            substance = substances_by_key.get(ingestion.substance_key)
            name = substance.name if substance else ingestion.substance_key
            item = QListWidgetItem(
                f"{ingestion.occurred_at.strftime('%I:%M %p').lstrip('0')}  |  {name} ({ingestion.consumer})\n"
                f"{ingestion.amount:g} {ingestion.unit}"
                + (f"  |  {ingestion.notes}" if ingestion.notes else "")
            )
            item.setData(Qt.UserRole, ingestion.id)
            self.ingestion_list.addItem(item)

        effects_by_id = {e.id: e for e in self.store.list_effects()}
        effect_logs = self.store.list_effect_logs_for_session(session.id)
        for effect_log in effect_logs:
            effect = effects_by_id.get(effect_log.effect_id)
            name = effect.name if effect else "Unknown effect"
            intensity = f" ({effect_log.intensity})" if effect_log.intensity else ""
            item = QListWidgetItem(
                f"{effect_log.occurred_at.strftime('%I:%M %p').lstrip('0')}  |  {name}{intensity}"
            )
            item.setData(Qt.UserRole, effect_log.id)
            self.effect_log_list.addItem(item)

        status = "open" if session.ended_at is None else "closed"
        self.session_title.setText(
            f"{session.consumer}'s session — {session.started_at.strftime('%a %d %b %Y, %I:%M %p').replace(' 0', ' ')} ({status})"
        )
        self.session_summary.setText(f"{len(ingestions)} ingestion(s), {len(effect_logs)} effect(s) logged.")
        self.end_session_button.setEnabled(session.ended_at is None)
        self.log_effect_button.setEnabled(True)

    def refresh_quick_add_row(self) -> None:
        while self.quick_add_layout.count():
            item = self.quick_add_layout.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.deleteLater()

        substances_by_key = {s.key: s for s in self.store.list_substances()}
        presets = self.store.list_presets()
        self.quick_add_row.setVisible(True)

        for preset in presets[:6]:
            substance = substances_by_key.get(preset.substance_key)
            label = f"+ {preset.name}"
            btn = QPushButton(label)
            btn.clicked.connect(lambda checked, p=preset: self.quick_add(p))
            self.quick_add_layout.addWidget(btn)

        self.quick_add_combo = QComboBox()
        self.quick_add_combo.setMinimumWidth(260)
        for preset in presets:
            substance = substances_by_key.get(preset.substance_key)
            roa = next((r for r in (substance.roas if substance else []) if r.id == preset.roa_id), None)
            unit = roa.unit if roa else ""
            substance_name = substance.name if substance else preset.substance_key
            self.quick_add_combo.addItem(f"{preset.name} — {substance_name} ({preset.amount:g} {unit})", preset.id)
        self.quick_add_layout.addWidget(self.quick_add_combo)

        quick_add_button = QPushButton("Quick Add")
        quick_add_button.setEnabled(bool(presets))
        quick_add_button.clicked.connect(self._quick_add_from_dropdown)
        self.quick_add_layout.addWidget(quick_add_button)

        new_preset_button = QPushButton("+ New Preset")
        new_preset_button.clicked.connect(self.new_preset)
        self.quick_add_layout.addWidget(new_preset_button)

        self.quick_add_layout.addStretch(1)

    def refresh_recent_effects_row(self) -> None:
        while self.recent_effects_layout.count():
            item = self.recent_effects_layout.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.deleteLater()

        recent = self.store.recent_effects(limit=8)
        self.recent_effects_row.setVisible(bool(recent))
        if not recent:
            return

        label = QLabel("Recent effects:")
        label.setObjectName("Muted")
        self.recent_effects_layout.addWidget(label)
        for effect in recent:
            btn = QPushButton(effect.name)
            btn.clicked.connect(lambda checked, e=effect: self.quick_log_effect(e))
            self.recent_effects_layout.addWidget(btn)
        self.recent_effects_layout.addStretch(1)

    # ---- session attach helper ----

    def _open_or_start_session(self, consumer: str, occurred_at: datetime) -> int:
        open_session = self.store.get_open_session(consumer)
        if open_session is not None:
            return open_session.id
        return self.store.start_session(consumer, occurred_at)

    def _confirm_interaction_warnings(self, consumer: str, substance_key: str) -> bool:
        warnings = check_new_ingestion(self.store, consumer, substance_key)
        if not warnings:
            return True

        substances_by_key = {s.key: s for s in self.store.list_substances()}
        lines = []
        most_severe = "Caution"
        for warning in warnings:
            other = substances_by_key.get(warning.other_substance_key)
            other_name = other.name if other else warning.other_substance_key
            line = f"With {other_name}: {warning.interaction.risk_level}"
            if warning.interaction.note:
                line += f"\n{warning.interaction.note}"
            lines.append(line)
            if warning.interaction.risk_level == "Dangerous":
                most_severe = "Dangerous"

        message = (
            "This combination has a flagged interaction risk (source: TripSit):\n\n"
            + "\n\n".join(lines)
            + "\n\nLog it anyway?"
        )
        default_button = QMessageBox.No if most_severe == "Dangerous" else QMessageBox.Yes
        result = QMessageBox.warning(
            self, "Interaction warning", message, QMessageBox.Yes | QMessageBox.No, default_button
        )
        return result == QMessageBox.Yes

    # ---- actions ----

    def add_ingestion(self) -> None:
        dialog = SubstanceIngestionDialog(self, self.store)
        if not dialog.exec():
            return
        values = dialog.result_values()
        if values["roa_id"] is None:
            return
        if not self._confirm_interaction_warnings(values["consumer"], values["substance_key"]):
            return
        session_id = self._open_or_start_session(values["consumer"], values["occurred_at"])
        self.store.add_ingestion(
            Ingestion(
                id=None,
                session_id=session_id,
                substance_key=values["substance_key"],
                roa_id=values["roa_id"],
                amount=values["amount"],
                unit=values["unit"],
                occurred_at=values["occurred_at"],
                consumer=values["consumer"],
                notes=values["notes"],
            )
        )
        self.current_consumer = values["consumer"]
        self.selected_session_id = session_id
        self.refresh_all()

    def quick_add(self, preset: SubstancePreset) -> None:
        substance = self.store.get_substance(preset.substance_key)
        roa = next((r for r in substance.roas if r.id == preset.roa_id), None) if substance else None
        if roa is None:
            return
        consumer = self.current_consumer if self.current_consumer != "All" else "Me"
        if not self._confirm_interaction_warnings(consumer, preset.substance_key):
            return
        now = datetime.now()
        session_id = self._open_or_start_session(self.current_consumer if self.current_consumer != "All" else "Me", now)
        self.store.add_ingestion(
            Ingestion(
                id=None,
                session_id=session_id,
                substance_key=preset.substance_key,
                roa_id=roa.id,
                amount=preset.amount,
                unit=roa.unit,
                occurred_at=now,
                consumer=self.current_consumer if self.current_consumer != "All" else "Me",
            )
        )
        self.selected_session_id = session_id
        self.refresh_all()

    def _quick_add_from_dropdown(self) -> None:
        preset_id = self.quick_add_combo.currentData()
        preset = next((p for p in self.store.list_presets() if p.id == preset_id), None)
        if preset is not None:
            self.quick_add(preset)

    def new_preset(self) -> None:
        dialog = SubstancePresetDialog(self, self.store)
        if not dialog.exec():
            return
        values = dialog.result_values()
        if values["roa_id"] is None:
            return
        self.store.save_preset(
            SubstancePreset(
                id=None,
                substance_key=values["substance_key"],
                roa_id=values["roa_id"],
                name=values["name"],
                amount=values["amount"],
            )
        )
        self.refresh_quick_add_row()

    def log_effect(self) -> None:
        if self.selected_session_id is None:
            QMessageBox.information(self, "No session selected", "Log an ingestion or select a session first.")
            return
        dialog = EffectPickerDialog(self, self.store, self.selected_session_id)
        dialog.exec()
        if dialog.logged_count:
            self.refresh_selected_session()
            self.refresh_recent_effects_row()

    def quick_log_effect(self, effect: SubjectiveEffect) -> None:
        if self.selected_session_id is None:
            QMessageBox.information(self, "No session selected", "Log an ingestion or select a session first.")
            return
        self.store.add_effect_log(
            EffectLog(id=None, session_id=self.selected_session_id, effect_id=effect.id, occurred_at=datetime.now())
        )
        self.refresh_selected_session()
        self.refresh_recent_effects_row()

    def end_selected_session(self) -> None:
        if self.selected_session_id is None:
            return
        self.store.end_session(self.selected_session_id, datetime.now())
        self.refresh_all()

    def delete_selected_ingestion(self) -> None:
        item = self.ingestion_list.currentItem()
        if item is None:
            QMessageBox.information(self, "No selection", "Select an ingestion first.")
            return
        ingestion_id = item.data(Qt.UserRole)
        result = QMessageBox.question(
            self,
            "Delete ingestion",
            "Delete the selected ingestion?",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if result == QMessageBox.Yes:
            self.store.delete_ingestion(ingestion_id)
            self.refresh_all()
