package main

import "core:fmt"
import "core:os"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:math/linalg"
import "vendor:stb/truetype"

STRIPE_COUNT :: 8

Vec2f16 :: [2]f16
Vec2 :: [2]f32

Rect :: struct {
	pos, size: Vec2,
}

Stripe :: struct {
	curve_start: u32,
	curve_count: u32,
}

Curve :: struct {
	p0:   Vec2f16,
	p1:   Vec2f16,
	p2:   Vec2f16,
}

Glyph :: struct {
	unicode:      u32,
	advance:      f32,
	stripe_index: u32,
	bounds:       Rect,
}

divide_curve :: proc(p0, p1, p2: Vec2, t: f32) -> (left: [3]Vec2, right: [3]Vec2) {
	p01 := linalg.lerp(p0, p1, t)
	p12 := linalg.lerp(p1, p2, t)
	p012 := linalg.lerp(p01, p12, t)
	return {p0, p01, p012}, {p012, p12, p2}
}

subdivide_to_monotonic :: proc(p0, p1, p2: Vec2, out_curves: ^[dynamic]Curve) {
	curves_step1: [dynamic; 4][3]Vec2

	denom_y := p0.y - 2.0 * p1.y + p2.y
	t_y: f32 = -1.0
	if abs(denom_y) > 1e-5 {
		t_y = (p0.y - p1.y) / denom_y
	}

	if t_y > 1e-4 && t_y < 0.9996 {
		left, right := divide_curve(p0, p1, p2, t_y)
		append(&curves_step1, left)
		append(&curves_step1, right)
	} else {
		append(&curves_step1, [3]Vec2{p0, p1, p2})
	}

	for c in curves_step1 {
		if abs(c[0].y - c[2].y) < 1e-6 {
			continue
		}

		denom_x := c[0].x - 2.0 * c[1].x + c[2].x
		t_x: f32 = -1.0
		if abs(denom_x) > 1e-5 {
			t_x = (c[0].x - c[1].x) / denom_x
		}

		if t_x > 1e-4 && t_x < 0.9996 {
			left, right := divide_curve(c[0], c[1], c[2], t_x)
			if abs(left[0].y - left[2].y) >= 1e-6 {
				append(out_curves, Curve{p0 = Vec2f16(left[0]), p1 = Vec2f16(left[1]), p2 = Vec2f16(left[2])})
			}
			if abs(right[0].y - right[2].y) >= 1e-6 {
				append(out_curves, Curve{p0 = Vec2f16(right[0]), p1 = Vec2f16(right[1]), p2 = Vec2f16(right[2])})
			}
		} else {
			append(out_curves, Curve{p0 = Vec2f16(c[0]), p1 = Vec2f16(c[1]), p2 = Vec2f16(c[2])})
		}
	}
}

process_font_file :: proc(font_path, out_bin_path: string) -> bool {
	ttf_data, read_err := os.read_entire_file_from_path(font_path, context.allocator)
	if read_err != nil {
		fmt.printf("Failed to read font file: %s\n", font_path)
		return false
	}
	defer delete(ttf_data)

	info: truetype.fontinfo
	if !truetype.InitFont(&info, raw_data(ttf_data), 0) {
		fmt.printf("Failed to initialize font: %s\n", font_path)
		return false
	}

	ascent, descent: i32
	truetype.GetFontVMetrics(&info, &ascent, &descent, nil)
	em_scale := 1.0 / f32(ascent - descent)

	glyphs: [dynamic]Glyph
	curves: [dynamic]Curve
	stripes: [dynamic]Stripe
	glyph_curves: [dynamic]Curve
	defer delete(glyphs)
	defer delete(curves)
	defer delete(stripes)
	defer delete(glyph_curves)

	for ch in u32(32)..=u32(0xFFFF) {
		glyph_idx := truetype.FindGlyphIndex(&info, rune(ch))
		if glyph_idx == 0 && ch != 32 do continue

		advance_i: i32
		truetype.GetGlyphHMetrics(&info, glyph_idx, &advance_i, nil)
		advance := f32(advance_i) * em_scale

		verts: [^]truetype.vertex
		num_verts := truetype.GetCodepointShape(&info, rune(ch), &verts)

		clear(&glyph_curves)

		p0: Vec2
		for i in 0..<int(num_verts) {
			v := verts[i]
			switch v.type {
			case 1: // MOVE
				p0 = Vec2{f32(v.x), f32(ascent) - f32(v.y)} * em_scale
			case 2: // LINE
				p1 := Vec2{f32(v.x), f32(ascent) - f32(v.y)} * em_scale
				c0 := (p0 + p1) * 0.5
				subdivide_to_monotonic(p0, c0, p1, &glyph_curves)
				p0 = p1
			case 3: // QUADRATIC
				p1 := Vec2{f32(v.x), f32(ascent) - f32(v.y)} * em_scale
				c0 := Vec2{f32(v.cx), f32(ascent) - f32(v.cy)} * em_scale
				subdivide_to_monotonic(p0, c0, p1, &glyph_curves)
				p0 = p1
			case 4: // CUBIC
				c1 := Vec2{f32(v.cx), f32(ascent) - f32(v.cy)} * em_scale
				c2 := Vec2{f32(v.cx1), f32(ascent) - f32(v.cy1)} * em_scale
				p1 := Vec2{f32(v.x), f32(ascent) - f32(v.y)} * em_scale
				mid := (p0 + 3.0 * c1 + 3.0 * c2 + p1) * 0.125
				q1_control := (3.0 * c1 - p0) * 0.5
				q2_control := (3.0 * c2 - p1) * 0.5
				subdivide_to_monotonic(p0, q1_control, mid, &glyph_curves)
				subdivide_to_monotonic(mid, q2_control, p1, &glyph_curves)
				p0 = p1
			}
		}

		truetype.FreeShape(&info, cast(^truetype.vertex)verts)

		bounds: Rect
		glyph_stripe_index := u32(len(stripes))

		if len(glyph_curves) > 0 {
			min_pos := Vec2{1e9, 1e9}
			max_pos := Vec2{-1e9, -1e9}
			for c in glyph_curves {
				cp0 := Vec2(c.p0)
				cp1 := Vec2(c.p1)
				cp2 := Vec2(c.p2)
				min_pos.x = min(min_pos.x, cp0.x, cp1.x, cp2.x)
				min_pos.y = min(min_pos.y, cp0.y, cp1.y, cp2.y)
				max_pos.x = max(max_pos.x, cp0.x, cp1.x, cp2.x)
				max_pos.y = max(max_pos.y, cp0.y, cp1.y, cp2.y)
			}
			min_pos -= 0.001
			max_pos += 0.001
			bounds = Rect{pos = min_pos, size = max_pos}

			y_range := max_pos.y - min_pos.y
			stripe_height := y_range / f32(STRIPE_COUNT)
			margin := stripe_height * 0.10

			for s in 0..<STRIPE_COUNT {
				stripe_y_min := min_pos.y + f32(s) * stripe_height
				stripe_y_max := stripe_y_min + stripe_height

				stripe_start := u32(len(curves))

				for c in glyph_curves {
					c_y_min := min(f32(c.p0.y), f32(c.p1.y), f32(c.p2.y))
					c_y_max := max(f32(c.p0.y), f32(c.p1.y), f32(c.p2.y))

					if c_y_max > stripe_y_min - margin && c_y_min < stripe_y_max + margin {
						append(&curves, c)
					}
				}

				append(&stripes, Stripe{
					curve_start = stripe_start,
					curve_count = u32(len(curves)) - stripe_start,
				})
			}
		} else {
			for s in 0..<STRIPE_COUNT {
				append(&stripes, Stripe{curve_start = 0, curve_count = 0})
			}
		}

		append(&glyphs, Glyph{
			unicode      = ch,
			advance      = advance,
			stripe_index = glyph_stripe_index,
			bounds       = bounds,
		})
	}

	out_buffer: [dynamic]u8
	defer delete(out_buffer)

	glyph_count := u32(len(glyphs))
	count_bytes := mem.ptr_to_bytes(&glyph_count)
	for b in count_bytes do append(&out_buffer, b)

	curve_count := u32(len(curves))
	curve_count_bytes := mem.ptr_to_bytes(&curve_count)
	for b in curve_count_bytes do append(&out_buffer, b)

	stripe_count := u32(len(stripes))
	stripe_count_bytes := mem.ptr_to_bytes(&stripe_count)
	for b in stripe_count_bytes do append(&out_buffer, b)

	glyphs_bytes := slice.to_bytes(glyphs[:])
	for b in glyphs_bytes do append(&out_buffer, b)

	stripes_bytes := slice.to_bytes(stripes[:])
	for b in stripes_bytes do append(&out_buffer, b)

	curves_bytes := slice.to_bytes(curves[:])
	for b in curves_bytes do append(&out_buffer, b)

	write_err := os.write_entire_file(out_bin_path, out_buffer[:])
	if write_err != nil {
		fmt.printf("Failed to write output file: %s\n", out_bin_path)
		return false
	}

	fmt.printf("Generated %s from %s (%d glyphs, %d stripes, %d curves, total %d bytes)\n", out_bin_path, font_path, glyph_count, stripe_count, curve_count, len(out_buffer))
	return true
}

main :: proc() {
	font_files: [dynamic]string

	ttf_matches, _ := os.glob("*.ttf")
	append(&font_files, ..ttf_matches)

	ttf_matches2, _ := os.glob("assets/fonts/*.ttf")
	append(&font_files, ..ttf_matches2)

	otf_matches, _ := os.glob("*.otf")
	append(&font_files, ..otf_matches)

	otf_matches2, _ := os.glob("assets/fonts/*.otf")
	append(&font_files, ..otf_matches2)

	if len(font_files) == 0 {
		fmt.println("No .ttf or .otf files found")
		return
	}

	for font_path in font_files {
		ext := os.ext(font_path)
		stem := strings.trim_suffix(font_path, ext)
		out_bin := fmt.tprintf("%s.bin", stem)
		process_font_file(font_path, out_bin)
	}
}