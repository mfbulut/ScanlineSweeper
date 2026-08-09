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
}

STRIPE_COUNT :: 8

Glyph :: struct {
	unicode:      rune,
	advance:      f32,
	stripe_index: u32,
	bounds:       Rect,
}

Batch :: struct {
	offset:  u32,
	count:   u32,
	scissor: Rect,
}

font: map[rune]Glyph
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
		}
	)
}

draw_circle :: proc(center: Vec2, radius: f32, color: [4]Color) {
	r := Rect{center - radius, radius * 2}
	if !rect_overlaps(r, scissor) do return
	draw_rect(r, color, radius)
}

// Text Rendering

@(rodata)
font_bytes := #load("../assets/fonts/SourceSans3-Medium.bin")

font_init :: proc() {
	offset := 0

	glyph_count := (^u32)(raw_data(font_bytes[offset:]))^
	offset += size_of(u32)

	curve_count := (^u32)(raw_data(font_bytes[offset:]))^
	offset += size_of(u32)

	glyphs_bytes_len := int(glyph_count) * size_of(Glyph)
	glyph_bytes := font_bytes[offset : offset + glyphs_bytes_len]
	glyphs_slice := slice.reinterpret([]Glyph, glyph_bytes)
	offset += glyphs_bytes_len

	stripes_bytes_len := int(glyph_count) * STRIPE_COUNT * 8
	stripe_bytes := font_bytes[offset : offset + stripes_bytes_len]
	offset += stripes_bytes_len

	curves_bytes_len := int(curve_count) * 24
	curve_bytes := font_bytes[offset : offset + curves_bytes_len]

	for g in glyphs_slice {
		font[g.unicode] = g
	}

	mem.copy(vks.stripe_buffer, raw_data(stripe_bytes), stripes_bytes_len)
	mem.copy(vks.curve_buffer, raw_data(curve_bytes), curves_bytes_len)
}

draw_text :: proc(text: string, pos: Vec2, font_size: f32, color := cast([4]Color)WHITE) {
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

		dest := Rect{
			{x, y} + glyph.bounds.pos * font_size,
			{x, y} + glyph.bounds.size * font_size,
		}
		dest_screen := Rect{dest.pos, dest.size - dest.pos}

		if rect_overlaps(dest_screen, scissor) {
			append(&instances,
				Instance{
					dest   = dest,
					src    = glyph.bounds,
					color  = color,
					index  = glyph.stripe_index,
				}
			)
		}

		x += glyph.advance * font_size
	}
}
