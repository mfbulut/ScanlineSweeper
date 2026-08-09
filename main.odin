package main

import "core:math"
import "fx"

scroll_target: f32
scroll_current: f32

main :: proc() {
	fx.init("Scanline Sweeper")
	fx.run(frame)
}

frame :: proc() {
	dt := fx.frame_time()
	fx.clear_window({13, 16, 23, 255})

	scroll_target += fx.mouse_scroll().y * 60.0
	scroll_current = math.lerp(scroll_current, scroll_target, 1.0 - math.pow(0.0001, dt))
	y := scroll_current + 35.0

	for text in example_texts {
		fx.draw_text(text, {30.0, y}, 48.0, {240, 244, 255, 255})
		y += 60.0
	}
}

@(rodata)
example_texts := []string{
	"latin (english): The quick brown fox jumps over the lazy dog.",
	"latin (french): Voix ambiguë d'un cœur qui au zéphyr préfère les jattes de kiwi.",
	"latin (german): Victor jagt zwölf Boxkämpfer quer über den großen Sylter Deich.",
	"latin (spanish): El veloz murciélago hindú comía feliz cardillo y escabeche.",
	"latin (polish): Pchnąć w tę łódź jeża lub osiem skrzyń fig.",
	"latin (czech): Příliš žluťoučký kůň úpěl ďábelské ódy.",
	"latin (nordic): Sævör grét áðan því ósköpin öll af snjó féllu á hjólbörurnar.",
	"latin (turkish): Pijamalı hasta yağız şoföre çabucak güvendi.",
	"latin (romanian): Gheorghe, aprinde o ţigară şi dă-mi şi mie o brichetă.",
	"latin (vietnamese): Tắt đèn mở rót chén rượu thắm, Cần cù bù thông minh.",
	"latin (pinyin): Nǐ hǎo! Shànɡhǎi shì Zhōngɡuó zuì dà de chéngshì.",
	"cyrillic (russian): Съешь же ещё этих мягких французских булок, да выпей чаю.",
	"cyrillic (ukrainian): Фабрикуймо γ-ґаджети для їжаків, що шукають ґудзик.",
	"cyrillic (bulgarian): Подхвърлящ се жълт охлюв, търсещ малката мотика.",
	"greek (modern): Ταχίστη αλώπηξ βαφής ψημένης γης υπερπηδά νωθρόν κύνα.",
	"greek (polytonic): Ἀρχῇ ἐποίησεν ὁ θεὸς τὸν οὐρανὸν καὶ τὴν γῆν.",
	"math / technical: f(x) = ∫ (x² + √x) dx ≤ ∑ (α + β) ≠ ± ∞ ≈ ∆ ∂ ∏ ≤ ≥ ∶",
	"subscripts & superscripts: x⁰ x¹ x² x³ x⁴ x⁵ x⁶ x⁷ x⁸ x⁹ x⁺ x⁻ xⁿ  •  H₂O  CO₂  x₀ x₁ x₂ x₉",
	"fractions: ½  ⅓  ⅔  ¼  ¾  ⅕  ⅖  ⅗  ⅘  ⅙  ⅚  ⅛  ⅜  ⅝  ⅞  №",
	"currency: $ € £ ¥ ₺ ₴ ₹ ₽ ₸ ₩ ¢ ¤ ₡ ₣ ₤ ₦ ₧ ₫ ₲ ₵",
	"arrows: ← ↑ → ↓ ↔ ↕ ↖ ↗ ↘ ↙  •  ⇐ ⇑ ⇒ ⇓",
	"symbols / ui: ⌘ ⌥ ⇧ ⌫ ⌦  •  ■ □ ▪ ▲ △ ▶ ▷ ► ▼ ▽ ◀ ◁ ◆ ◊ ○  •  ♥ ♪ ♫ № ℗ ™ Ω",
}
