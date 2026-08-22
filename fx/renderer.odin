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
	dest:   Rect,
	src:    Rect,
	color:  Color,
	index:  u32,
	radius: f32,
}

Glyph :: struct {
	unicode: rune,
	advance: f32,
	index:   u32,
	bounds:  Rect,
}

font: map[rune]Glyph
instances: [dynamic; MAX_INSTANCES]Instance

clear_window :: proc(color: Color) {
	vks.clear_color = Vec4(color) / 255.0
}

draw_rect :: proc(r: Rect, color: Color, radius: f32 = 0) {
	append(&instances,
		Instance{
			dest   = {r.pos, r.pos + r.size},
			color  = color,
			radius = clamp(radius, 0, min(r.size.x, r.size.y) * 0.5),
		}
	)
}

draw_circle :: proc(center: Vec2, radius: f32, color: Color) {
	draw_rect({center - radius, radius * 2}, color, radius)
}

// Text Rendering

@(rodata)
font_bytes := #load("../assets/fonts/SourceSans3-Regular.bin")

font_init :: proc() {
	offset := 0

	glyph_count := (^u32)(raw_data(font_bytes[offset:]))^
	offset += size_of(u32)

	curve_count := (^u32)(raw_data(font_bytes[offset:]))^
	offset += size_of(u32)

	glyphs_bytes_len := int(glyph_count) * size_of(Glyph)
	glyph_bytes := font_bytes[offset : offset + glyphs_bytes_len]
	glyphs := slice.reinterpret([]Glyph, glyph_bytes)
	offset += glyphs_bytes_len

	STRIPE_COUNT :: 8
	stripes_bytes_len := int(glyph_count) * STRIPE_COUNT * 8
	stripe_bytes := font_bytes[offset : offset + stripes_bytes_len]
	offset += stripes_bytes_len

	curves_bytes_len := int(curve_count) * 24
	curve_bytes := font_bytes[offset : offset + curves_bytes_len]

	for g in glyphs {
		font[g.unicode] = g
	}

	mem.copy(vks.stripe_buffer.mapped, raw_data(stripe_bytes), stripes_bytes_len)
	mem.copy(vks.curve_buffer.mapped, raw_data(curve_bytes), curves_bytes_len)
}

draw_text :: proc(text: string, pos: Vec2, font_size: f32, color: Color) {
	p := pos

	for b in text {
		if b == '\n' {
			p.x = pos.x
			p.y += font_size
			continue
		}

		glyph := font[b] or_else font['?']

		dest := Rect{
			p + glyph.bounds.pos * font_size,
			p + glyph.bounds.size * font_size,
		}

		append(&instances,
			Instance{
				dest   = dest,
				src    = glyph.bounds,
				color  = color,
				index  = glyph.index,
			}
		)

		p.x += glyph.advance * font_size
	}
}