from __future__ import annotations

from datetime import datetime, timedelta

from PySide6.QtCore import QPointF, Qt
from PySide6.QtGui import QBrush, QColor, QFont, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QFrame, QLabel, QVBoxLayout, QWidget


class TimelineGraph(QWidget):
    def __init__(self, title: str, subtitle: str, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.title = title
        self.subtitle = subtitle
        self.points: list[tuple[datetime, float]] = []
        self.markers: list[datetime] = []
        self.empty_message = "No data logged for this view"
        self.hover_pos: QPointF | None = None
        self.setMouseTracking(True)
        self.setMinimumHeight(240)

    def mouseMoveEvent(self, event) -> None:
        self.hover_pos = event.position()
        self.update()

    def leaveEvent(self, event) -> None:
        self.hover_pos = None
        self.update()

    def set_points(self, points: list[tuple[datetime, float]], markers: list[datetime] | None = None) -> None:
        self.points = points
        self.markers = markers or []
        self.update()

    def paintEvent(self, event) -> None:  # noqa: N802 - Qt API naming
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        rect = self.rect().adjusted(8, 8, -8, -8)
        painter.setPen(QPen(QColor("#343840"), 1))
        painter.setBrush(QBrush(QColor("#15171a")))
        painter.drawRoundedRect(rect, 8, 8)

        painter.setFont(QFont("Segoe UI", 11, QFont.Weight.DemiBold))
        painter.setPen(QColor("#ececef"))
        painter.drawText(rect.adjusted(16, 14, -16, -14), Qt.AlignTop | Qt.AlignLeft, self.title)
        painter.setFont(QFont("Segoe UI", 9))
        painter.setPen(QColor("#9da3ad"))
        painter.drawText(rect.adjusted(16, 40, -16, -14), Qt.AlignTop | Qt.AlignLeft, self.subtitle)

        graph = rect.adjusted(30, 78, -30, -42)
        painter.setPen(QPen(QColor("#252930"), 1))
        for i in range(4):
            y = graph.top() + graph.height() * i / 3
            painter.drawLine(graph.left(), int(y), graph.right(), int(y))

        if not self.points:
            painter.setPen(QColor("#7f858f"))
            painter.drawText(graph, Qt.AlignCenter, self.empty_message)
            return

        min_time = min(point[0] for point in self.points)
        max_time = max(point[0] for point in self.points)
        max_value = max(max(point[1] for point in self.points), 1.0)
        total_seconds = max((max_time - min_time).total_seconds(), 1.0)

        if max(point[1] for point in self.points) <= 0:
            self._draw_now_marker(painter, graph, min_time, max_time, total_seconds)
            painter.setPen(QColor("#7f858f"))
            painter.drawText(graph, Qt.AlignCenter, self.empty_message)
            return

        mapped = [self._map_point(timestamp, value, min_time, total_seconds, max_value, graph) for timestamp, value in self.points]

        fill_path = QPainterPath(mapped[0])
        for point in mapped[1:]:
            fill_path.lineTo(point)
        fill_path.lineTo(graph.right(), graph.bottom())
        fill_path.lineTo(graph.left(), graph.bottom())
        fill_path.closeSubpath()
        painter.fillPath(fill_path, QColor(201, 151, 0, 58))

        line_path = QPainterPath(mapped[0])
        for point in mapped[1:]:
            line_path.lineTo(point)
        painter.setPen(QPen(QColor("#c99700"), 3, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
        painter.drawPath(line_path)

        painter.setPen(QPen(QColor("#d8ae27"), 1, Qt.DashLine))
        painter.setBrush(QBrush(QColor("#d8ae27")))
        for marker in self.markers:
            if marker < min_time or marker > max_time:
                continue
            x_ratio = (marker - min_time).total_seconds() / total_seconds
            x = graph.left() + graph.width() * x_ratio
            painter.drawLine(int(x), graph.top(), int(x), graph.bottom())
            painter.drawEllipse(QPointF(x, graph.bottom()), 4, 4)

        self._draw_now_marker(painter, graph, min_time, max_time, total_seconds)

        if self.hover_pos and self.points:
            x = self.hover_pos.x()
            if graph.left() <= x <= graph.right():
                painter.setPen(QPen(QColor("#a0a5af"), 1, Qt.DashLine))
                painter.drawLine(int(x), graph.top(), int(x), graph.bottom())

                x_ratio = (x - graph.left()) / graph.width()
                hover_time = min_time + timedelta(seconds=total_seconds * x_ratio)

                hover_value = 0.0
                for i in range(len(self.points) - 1):
                    if self.points[i][0] <= hover_time <= self.points[i + 1][0]:
                        t1, v1 = self.points[i]
                        t2, v2 = self.points[i + 1]
                        if (t2 - t1).total_seconds() > 0:
                            ratio = (hover_time - t1).total_seconds() / (t2 - t1).total_seconds()
                            hover_value = v1 + (v2 - v1) * ratio
                        else:
                            hover_value = v1
                        break

                label = f"{hover_time.strftime('%b %d %I:%M %p').replace(' 0', ' ')} - {hover_value:.2f}"
                painter.setFont(QFont("Segoe UI", 9, QFont.Weight.DemiBold))
                painter.setPen(QColor("#ececef"))

                fm = painter.fontMetrics()
                text_width = fm.horizontalAdvance(label)
                text_x = x - text_width / 2
                if text_x < graph.left():
                    text_x = graph.left()
                elif text_x + text_width > graph.right():
                    text_x = graph.right() - text_width

                painter.drawText(int(text_x), graph.top() - 6, label)

        painter.setFont(QFont("Segoe UI", 8))
        painter.setPen(QColor("#7f858f"))
        bottom = graph.adjusted(0, graph.height() + 8, 0, 28)
        painter.drawText(bottom, Qt.AlignLeft, min_time.strftime("%b %d"))
        painter.drawText(bottom, Qt.AlignRight, max_time.strftime("%b %d"))
        painter.drawText(graph.adjusted(0, -22, 0, -graph.height()), Qt.AlignRight, f"Peak {max_value:.1f}")

    def _draw_now_marker(self, painter, graph, min_time, max_time, total_seconds) -> None:
        now = datetime.now()
        if now < min_time or now > max_time:
            return
        x_ratio = (now - min_time).total_seconds() / total_seconds
        x = graph.left() + graph.width() * x_ratio
        painter.setPen(QPen(QColor("#66d9ff"), 2, Qt.SolidLine, Qt.RoundCap))
        painter.drawLine(int(x), graph.top(), int(x), graph.bottom())
        label_rect = graph.adjusted(0, -24, 0, -graph.height() + 2)
        painter.setFont(QFont("Segoe UI", 8, QFont.Weight.DemiBold))
        painter.setPen(QColor("#66d9ff"))
        painter.drawText(label_rect.adjusted(int(x - graph.left()) - 24, 0, 0, 0), Qt.AlignLeft, "Now")

    def _map_point(self, timestamp, value, min_time, total_seconds, max_value, graph) -> QPointF:
        x_ratio = (timestamp - min_time).total_seconds() / total_seconds
        y_ratio = min(value / max_value, 1.0)
        return QPointF(
            graph.left() + graph.width() * x_ratio,
            graph.bottom() - graph.height() * y_ratio,
        )


class StatCard(QFrame):
    def __init__(self, label: str) -> None:
        super().__init__()
        self.setObjectName("StatCard")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 10, 12, 10)
        layout.setSpacing(3)
        self.value = QLabel("--")
        self.value.setObjectName("StatValue")
        self.label = QLabel(label)
        self.label.setObjectName("Muted")
        layout.addWidget(self.value)
        layout.addWidget(self.label)

    def set_value(self, value: str) -> None:
        self.value.setText(value)
