"""A small, dependency-free desktop demo of the Swift annotation tool."""

from __future__ import annotations

import tkinter as tk
from dataclasses import dataclass
from tkinter import ttk


COLORS = {
    "Yellow": "#F2C94C",
    "Pink": "#E87891",
    "Blue": "#5599DF",
    "Green": "#45AD78",
    "Purple": "#9274D2",
}


@dataclass
class Stroke:
    mode: str
    color: str
    points: list[tuple[float, float]]


class DrawingDemo:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Pencil Notes — Drawing Demo")
        self.root.geometry("1080x800")
        self.root.minsize(720, 560)

        self.mode = tk.StringVar(value="Highlight")
        self.selected_color = tk.StringVar(value="Yellow")
        self.strokes: list[Stroke] = []
        self.redo_strokes: list[Stroke] = []
        self.active_stroke: Stroke | None = None

        self._build_toolbar()

        self.canvas = tk.Canvas(
            root,
            background="#F1F3F6",
            highlightthickness=0,
            cursor="pencil",
        )
        self.canvas.pack(fill=tk.BOTH, expand=True)
        self.canvas.bind("<Configure>", self._draw_page)
        self.canvas.bind("<ButtonPress-1>", self._start_stroke)
        self.canvas.bind("<B1-Motion>", self._continue_stroke)
        self.canvas.bind("<ButtonRelease-1>", self._finish_stroke)

        root.bind("<Control-z>", self._undo)
        root.bind("<Control-y>", self._redo)

    def _build_toolbar(self) -> None:
        toolbar = ttk.Frame(self.root, padding=(18, 12))
        toolbar.pack(fill=tk.X)

        ttk.Label(toolbar, text="✎", font=("Segoe UI", 17, "bold")).pack(
            side=tk.LEFT, padx=(0, 14)
        )

        mode_icons = {"Highlight": "▰", "Note": "✎"}
        for label in ("Highlight", "Note"):
            ttk.Radiobutton(
                toolbar,
                text=f"{mode_icons[label]}  {label}",
                value=label,
                variable=self.mode,
                command=self._update_selection,
            ).pack(side=tk.LEFT, padx=4)

        ttk.Separator(toolbar, orient=tk.VERTICAL).pack(
            side=tk.LEFT, fill=tk.Y, padx=12
        )

        self.color_buttons: dict[str, tk.Button] = {}
        for name, color in COLORS.items():
            button = tk.Button(
                toolbar,
                text=" ",
                width=2,
                background=color,
                activebackground=color,
                relief=tk.FLAT,
                command=lambda choice=name: self._select_color(choice),
                takefocus=True,
                highlightthickness=2,
                highlightbackground="#FFFFFF",
            )
            button.pack(side=tk.LEFT, padx=3)
            self.color_buttons[name] = button

        ttk.Separator(toolbar, orient=tk.VERTICAL).pack(
            side=tk.LEFT, fill=tk.Y, padx=12
        )

        self.undo_button = ttk.Button(toolbar, text="Undo", command=self._undo)
        self.undo_button.pack(side=tk.LEFT, padx=3)
        self.redo_button = ttk.Button(toolbar, text="Redo", command=self._redo)
        self.redo_button.pack(side=tk.LEFT, padx=3)
        ttk.Button(toolbar, text="Clear", command=self._clear).pack(
            side=tk.LEFT, padx=(3, 0)
        )

        self.status = ttk.Label(toolbar)
        self.status.pack(side=tk.RIGHT, padx=(12, 0))
        self._update_selection()

    def _select_color(self, name: str) -> None:
        self.selected_color.set(name)
        self._update_selection()

    def _update_selection(self) -> None:
        for name, button in self.color_buttons.items():
            button.configure(
                highlightbackground=(
                    "#344054" if name == self.selected_color.get() else "#FFFFFF"
                )
            )
        if self.mode.get() == "Highlight":
            self.status.configure(text="▰ Highlight mode")
        else:
            self.status.configure(text="✎ Note mode · black ink")

    def _start_stroke(self, event: tk.Event) -> None:
        width, height = self._canvas_size()
        self.active_stroke = Stroke(
            mode=self.mode.get(),
            color=self.selected_color.get(),
            points=[(event.x / width, event.y / height)],
        )
        self._draw_page()

    def _continue_stroke(self, event: tk.Event) -> None:
        if self.active_stroke is None:
            return
        width, height = self._canvas_size()
        point = (event.x / width, event.y / height)
        if point != self.active_stroke.points[-1]:
            self.active_stroke.points.append(point)
            self._draw_page()

    def _finish_stroke(self, _event: tk.Event) -> None:
        if self.active_stroke is not None:
            if len(self.active_stroke.points) > 1:
                self.strokes.append(self.active_stroke)
                self.redo_strokes.clear()
            self.active_stroke = None
            self._draw_page()

    def _undo(self, _event: tk.Event | None = None) -> None:
        if self.strokes:
            self.redo_strokes.append(self.strokes.pop())
            self._draw_page()

    def _redo(self, _event: tk.Event | None = None) -> None:
        if self.redo_strokes:
            self.strokes.append(self.redo_strokes.pop())
            self._draw_page()

    def _clear(self) -> None:
        self.strokes.clear()
        self.redo_strokes.clear()
        self._draw_page()

    def _canvas_size(self) -> tuple[int, int]:
        return max(self.canvas.winfo_width(), 1), max(self.canvas.winfo_height(), 1)

    def _draw_page(self, _event: tk.Event | None = None) -> None:
        width, height = self._canvas_size()
        self.canvas.delete("all")

        page_width = min(820, width - 48)
        page_height = min(1050, height - 36)
        left = (width - page_width) / 2
        top = (height - page_height) / 2
        self.canvas.create_rectangle(
            left + 3,
            top + 5,
            left + page_width + 3,
            top + page_height + 5,
            fill="#DDE1E7",
            outline="",
        )
        self.canvas.create_rectangle(
            left,
            top,
            left + page_width,
            top + page_height,
            fill="#FFFFFF",
            outline="#E5E7EB",
        )

        margin = left + page_width * 0.105
        text_width = page_width * 0.79
        self.canvas.create_text(
            margin,
            top + page_height * 0.105,
            text="FIELD NOTES",
            anchor="nw",
            fill="#7B8492",
            font=("Segoe UI", 10, "bold"),
        )
        self.canvas.create_text(
            margin,
            top + page_height * 0.145,
            text="The art of noticing",
            anchor="nw",
            fill="#252A34",
            font=("Georgia", 27, "bold"),
        )
        self.canvas.create_text(
            margin,
            top + page_height * 0.22,
            text="Small observations can change the way we understand a place.",
            anchor="nw",
            width=text_width,
            fill="#687180",
            font=("Georgia", 14, "italic"),
        )
        self.canvas.create_text(
            margin,
            top + page_height * 0.30,
            text=(
                "A careful walk is a kind of attention. It asks us to slow down, "
                "to look beyond the obvious, and to notice the details that would "
                "otherwise pass without a name. The shape of a shadow, a change in "
                "the air, or a familiar path seen from a new angle can become an "
                "invitation to think differently."
            ),
            anchor="nw",
            width=text_width,
            fill="#353B46",
            font=("Georgia", 14),
            justify=tk.LEFT,
        )
        self.canvas.create_text(
            margin,
            top + page_height * 0.54,
            text="Look closely",
            anchor="nw",
            fill="#252A34",
            font=("Georgia", 19, "bold"),
        )
        self.canvas.create_text(
            margin,
            top + page_height * 0.60,
            text=(
                "Choose a phrase that stays with you. Mark it with the highlighter, "
                "then switch to the pencil to add a thought in the margin."
            ),
            anchor="nw",
            width=text_width,
            fill="#353B46",
            font=("Georgia", 14),
            justify=tk.LEFT,
        )

        visible_strokes = self.strokes.copy()
        if self.active_stroke is not None:
            visible_strokes.append(self.active_stroke)
        for stroke in visible_strokes:
            self._draw_stroke(stroke, width, height)

        self.undo_button.configure(state=tk.NORMAL if self.strokes else tk.DISABLED)
        self.redo_button.configure(
            state=tk.NORMAL if self.redo_strokes else tk.DISABLED
        )

    def _draw_stroke(self, stroke: Stroke, width: int, height: int) -> None:
        points = [(x * width, y * height) for x, y in stroke.points]
        color = COLORS[stroke.color] if stroke.mode == "Highlight" else "#111111"
        stroke_width = 23 if stroke.mode == "Highlight" else 4

        if len(points) == 1:
            x, y = points[0]
            radius = stroke_width / 2
            self.canvas.create_oval(
                x - radius,
                y - radius,
                x + radius,
                y + radius,
                fill=color,
                outline=color,
                stipple="gray50" if stroke.mode == "Highlight" else "",
            )
        else:
            flattened = [coordinate for point in points for coordinate in point]
            self.canvas.create_line(
                *flattened,
                fill=color,
                width=stroke_width,
                smooth=True,
                splinesteps=16,
                capstyle=tk.ROUND,
                joinstyle=tk.ROUND,
                stipple="gray50" if stroke.mode == "Highlight" else "",
            )


def main() -> None:
    root = tk.Tk()
    DrawingDemo(root)
    root.mainloop()


if __name__ == "__main__":
    main()
