package fx

import "core:mem"
import "core:slice"

Vec2  :: [2]f32
Vec3  :: [3]f32
Vec4  :: [4]f32
Color :: [4]byte

Rect :: struct {
	pos, size: Vec2,
}

Instance :: struct #align(16) {
	dest:   Rect,     // x0, y0, x1, y1
	src:    Rect,     // u0, v0, u1, v1
	color:  [4]Color, // TL, TR, BL, BR
	radius: f32,
	index:  u32,
	kind:   enum u32 { Rect, Texture, Text },
}

Glyph :: struct {
	unicode:     rune,
	advance:     f32,
	curve_start: u32,
	curve_count: u32,
}

Font :: map[rune]Glyph

Batch :: struct {
	offset:  u32,
	count:   u32,
	scissor: Rect,
}

scissor: Rect
batches: [dynamic; 256]Batch
instances: [dynamic; MAX_INSTANCES]Instance
WHITE := Color{255, 255, 255, 255}

rect_overlaps :: proc(a, b: Rect) -> bool {
	return a.pos.x < b.pos.x + b.size.x && a.pos.x + a.size.x > b.pos.x && a.pos.y < b.pos.y + b.size.y && a.pos.y + a.size.y > b.pos.y
}

clear_window :: proc(color: Color) {
	vks.clear_color = Vec4(color) / 255.0
}

set_scissor :: proc(rect: Rect) {
	if rect != scissor {
		flush()
		scissor = rect
	}
}

reset_scissor :: proc() {
	set_scissor({{0, 0}, window_size()})
}

flush :: proc() {
	if len(instances) == 0 do return

	last_count: u32 = 0
	for b in batches {
		last_count += b.count
	}

	count := u32(len(instances)) - last_count
	if count == 0 do return

	append(&batches, Batch{
		offset  = last_count,
		count   = count,
		scissor = scissor,
	})
}

draw_rect :: proc(r: Rect, color: [4]Color, radius := f32(0)) {
	if !rect_overlaps(r, scissor) do return

	append(&instances,
		Instance{
			dest   = {r.pos, r.pos + r.size},
			src    = {},
			color  = color,
			radius = radius,
			kind   = .Rect,
		}
	)
}

draw_circle :: proc(center: Vec2, radius: f32, color: [4]Color) {
	r := Rect{center - radius, radius * 2}
	if !rect_overlaps(r, scissor) do return
	draw_rect(r, color, radius)
}

draw_texture_ex :: proc(tex: Texture, src: Rect, dest: Rect, tint := cast([4]Color)WHITE, radius := f32(0)) {
	if !rect_overlaps(dest, scissor) || tex.index == 0 do return

	size := Vec2(tex.size)

	src_uv := Rect{
		src.pos / size,
		(src.pos + src.size) / size,
	}

	append(&instances,
		Instance{
			src    = src_uv,
			dest   = {dest.pos, dest.pos + dest.size},
			color  = tint,
			radius = radius,
			kind   = .Texture,
			index  = u32(tex.index),
		}
	)
}

draw_texture :: proc(tex: Texture, rect: Rect, tint := cast([4]Color)WHITE, radius := f32(0)) {
	draw_texture_ex(tex, {{0, 0}, {f32(tex.size.x), f32(tex.size.y)}}, rect, tint, radius)
}

// Text Rendering

font_load :: proc(font_bytes: []u8) -> Font {
	@(static) total_curves_loaded: u32

	offset := 0

	glyph_count := (^u32)(raw_data(font_bytes[offset:]))^
	offset += size_of(u32)

	curve_count := (^u32)(raw_data(font_bytes[offset:]))^
	offset += size_of(u32)

	glyphs_bytes_len := int(glyph_count) * size_of(Glyph)
	glyph_bytes := font_bytes[offset : offset + glyphs_bytes_len]
	glyphs_slice := slice.reinterpret([]Glyph, glyph_bytes)
	offset += glyphs_bytes_len

	curves_bytes_len := int(curve_count) * 12
	curve_bytes := font_bytes[offset : offset + curves_bytes_len]

	curves_to_copy := min(curve_count, MAX_CURVES - total_curves_loaded)
	glyphs := make(map[rune]Glyph, glyph_count)

	for g in glyphs_slice {
		adjusted_g := g
		adjusted_g.curve_start += total_curves_loaded

		if adjusted_g.curve_start >= MAX_CURVES {
			adjusted_g.curve_count = 0
		} else if adjusted_g.curve_start + adjusted_g.curve_count > MAX_CURVES {
			adjusted_g.curve_count = MAX_CURVES - adjusted_g.curve_start
		}

		glyphs[g.unicode] = adjusted_g
	}

	if curves_to_copy > 0 {
		dest_ptr := rawptr(uintptr(vks.curve_buffer_mapped) + uintptr(total_curves_loaded * 12))
		mem.copy(dest_ptr, raw_data(curve_bytes), int(curves_to_copy) * 12)
		total_curves_loaded += curves_to_copy
	}

	return glyphs
}

draw_text :: proc(font: Font, text: string, pos: Vec2, font_size: f32, color := cast([4]Color)WHITE) {
	if text == "" do return

	x := pos.x
	y := pos.y

	for char in text {
		if char == '\n' {
			x = pos.x
			y += font_size
			continue
		}

		glyph := font[char] or_else font['?']

		if glyph.curve_count > 0 {
			dest := Rect{{x, y}, {x, y} + font_size}
			if !rect_overlaps(dest, scissor) do continue

			append(&instances,
				Instance{
					dest   = dest,
					src    = {{0, 0}, {1, 1}},
					color  = color,
					radius = f32(glyph.curve_count),
					index  = glyph.curve_start,
					kind   = .Text,
				}
			)
		}

		x += glyph.advance * font_size
	}
}

draw_text_rect :: proc(font: Font, text: string, bounds: Rect, font_size: f32, color := cast([4]Color)WHITE, center_x := false, center_y := false) {
	if text == "" do return
	size := measure_text(font, text, font_size)
	x := bounds.pos.x + (center_x ? (bounds.size.x - size.x) * 0.5 : 0)
	y := bounds.pos.y + (center_y ? (bounds.size.y - font_size) * 0.5 : 0)
	draw_text(font, text, {x, y}, font_size, color)
}

measure_text :: proc(font: Font, text: string, font_size: f32) -> (size: Vec2) {
	if text == "" do return

	cursor_x := f32(0)
	size.y = font_size

	for char in text {
		if char == '\n' {
			cursor_x = 0
			size.y += font_size
			continue
		}

		glyph := font[char] or_else font['?']
		cursor_x += glyph.advance * font_size
		size.x = max(size.x, cursor_x)
	}

	return
}