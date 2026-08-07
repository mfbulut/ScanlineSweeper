package main

import "core:fmt"
import "core:math"
import "core:slice"
import "fx"

inter: fx.Font
meaculpa: fx.Font
all_runes: [dynamic]rune

scroll_target: f32
scroll_current: f32
content_height: f32

BG_COLOR     :: fx.Color{13, 16, 23, 255}
PANEL_BG     :: fx.Color{20, 25, 36, 255}
PANEL_BORDER :: fx.Color{38, 46, 66, 255}
ACCENT_BLUE  :: fx.Color{99, 102, 241, 255}
TEXT_BRIGHT  :: fx.Color{240, 244, 255, 255}
TEXT_MUTED   :: fx.Color{130, 142, 168, 255}
CELL_BG      :: fx.Color{24, 30, 44, 255}

main :: proc() {
	fx.init("Font Renderer Demo", {1280, 800})
	inter = fx.font_load(#load("assets/fonts/Inter.bin"))
	meaculpa = fx.font_load(#load("assets/fonts/MeaCulpa-Regular.bin"))
	for r in inter do append(&all_runes, r)
	slice.sort(all_runes[:])

	fx.run(frame)
}

frame :: proc() {
	dt := fx.frame_time()
	win_size := fx.window_size()
	fx.clear_window(BG_COLOR)

	max_scroll := max(f32(0.0), content_height - win_size.y + 60.0)
	scroll_target = clamp(scroll_target - fx.mouse_scroll().y * 60.0, 0.0, max_scroll)
	scroll_current = math.lerp(scroll_current, scroll_target, 1.0 - math.pow(0.0001, dt))

	padding: f32 = 40.0
	content_width := win_size.x - padding * 2.0 - 20.0
	y := padding - scroll_current

	pangram := "The quick brown fox jumps over the lazy dog."

	fx.draw_text(inter, "FONT: INTER", {padding, y}, 20.0, ACCENT_BLUE)
	y += 30.0

	inter_sizes := []f32{14, 20, 24, 28, 32, 40, 48}
	for sz in inter_sizes {
		label := fmt.tprintf("%v px", int(sz))
		fx.draw_text(inter, label, {padding, y + (sz * 0.2)}, 13, TEXT_MUTED)
		fx.draw_text(inter, pangram, {padding + 70, y}, sz, TEXT_BRIGHT)
		y += sz + 16
	}
	y += 20

	fx.draw_text(inter, "FONT: MEA CULPA", {padding, y}, 20, ACCENT_BLUE)
	y += 30

	meaculpa_sizes := []f32{32, 40, 48, 64, 72, 96}
	for sz in meaculpa_sizes {
		label := fmt.tprintf("%v px", int(sz))
		fx.draw_text(inter, label, {padding, y + (sz * 0.2)}, 13.0, TEXT_MUTED)
		fx.draw_text(meaculpa, pangram, {padding + 70.0, y}, sz, TEXT_BRIGHT)
		y += sz + 18.0
	}
	y += 40.0

	Family :: struct {
		title:   string,
		content: string,
	}

	families := []Family{
		{"LATIN ", "The quick brown fox jumps over the lazy dog."},
		{"CYRILLIC", "Съешь же ещё этих мягких французских булок, да выпей чаю."},
		{"GREEK", "Ταχίστη αλώπηξ βαφής ψημένης γης υπερπηδά νωθρόν κύνα."},
		{"MATHEMATICAL SYMBOLS", "f(x) = ∫ (x² + √x) dx ≤ ∑ (α + β) ≠ ∅ ± ∞ ≈ ∆ ∂ ∏ ≤ ≥ ∶"},
		{"ARROWS & UI CONTROLS", "← ↑ → ↓ ↔ ↕ ↖ ↗ ↘ ↙  •  ↩ ↪ ↺ ↻ ⇐ ⇒  •  ⌘ ⌥ ⇧ ⌫ ⎋ ⏎ ⏏ ⌦ ⌧"},
		{"GEOMETRIC SHAPES & SYMBOLS", "■ □ ▢ ▪ ▲ △ ▶ ▷ ► ▼ ▽ ◀ ◁ ◆ ◇ ◊ ○  •  ☀ ★ ☆ ♡ ♥ ♪ ♫ ⚠ ℀ ℅ № ℗ ™ Ω"},
	}

	for fam in families {
		fx.draw_text(inter, fam.title, {padding, y}, 15.0, TEXT_MUTED)
		y += 24.0
		fx.draw_text(inter, fam.content, {padding + 10.0, y}, 30.0, TEXT_BRIGHT)
		y += 48.0
	}
	y += 30.0

	grid_sub := fmt.tprintf("%v glyphs", len(all_runes))
	fx.draw_text(inter, grid_sub, {padding, y}, 14.0, TEXT_MUTED)
	y += 26.0

	cell_size: f32 = 52.0
	cell_gap: f32 = 8.0
	cols := max(1, int((content_width) / (cell_size + cell_gap)))

	grid_start_y := y
	total_rows := (len(all_runes) + cols - 1) / cols

	for r, i in all_runes {
		col := i % cols
		row := i / cols

		cx := padding + f32(col) * (cell_size + cell_gap)
		cy := grid_start_y + f32(row) * (cell_size + cell_gap)

		cell_rect := fx.Rect{{cx, cy}, {cell_size, cell_size}}
		fx.draw_rect(cell_rect, {CELL_BG, CELL_BG, CELL_BG, CELL_BG}, 6.0)

		str := fmt.tprintf("%c", r)
		fx.draw_text_rect(inter, str, cell_rect, 24.0, TEXT_BRIGHT, center_x = true, center_y = true)
	}

	y = grid_start_y + f32(total_rows) * (cell_size + cell_gap) + 40.0

	content_height = y + scroll_current

	if max_scroll > 0 {
		bar_w: f32 = 8.0
		bar_x := win_size.x - bar_w - 6.0
		thumb_h := max(30.0, (win_size.y / content_height) * win_size.y)
		thumb_y := (scroll_current / max_scroll) * (win_size.y - thumb_h)

		track_rect := fx.Rect{{bar_x, 0}, {bar_w, win_size.y}}
		fx.draw_rect(track_rect, {fx.Color{20, 25, 36, 120}, fx.Color{20, 25, 36, 120}, fx.Color{20, 25, 36, 120}, fx.Color{20, 25, 36, 120}}, 4.0)

		thumb_rect := fx.Rect{{bar_x, thumb_y}, {bar_w, thumb_h}}
		fx.draw_rect(thumb_rect, {ACCENT_BLUE, ACCENT_BLUE, ACCENT_BLUE, ACCENT_BLUE}, 4.0)
	}
}