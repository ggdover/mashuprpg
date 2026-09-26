class_name UIStyle
extends RefCounted
## Shared look & feel for every UI module: palette, fonts sizes, and small factory helpers.
## OWNER: orchestrator. FROZEN during waves 1-2: module agents must NOT edit this file. Need a new signal/stat/helper?
## Keep it in a file you own and list it in your final report; the orchestrator merges between waves.
## Put module-specific helpers in files you own (e.g. scripts/ui/inventory/inv_slot.gd).
## Style: dark translucent panels, thin bronze borders, warm parchment text (classic ARPG).

const COLOR_BG := Color(0.05, 0.045, 0.04, 0.94)
const COLOR_PANEL := Color(0.09, 0.08, 0.07, 0.96)
const COLOR_PANEL_LIGHT := Color(0.15, 0.13, 0.11, 0.96)
const COLOR_SLOT := Color(0.12, 0.11, 0.10, 1.0)
const COLOR_SLOT_HOVER := Color(0.22, 0.2, 0.16, 1.0)
const COLOR_BORDER := Color(0.48, 0.38, 0.22)
const COLOR_BORDER_BRIGHT := Color(0.85, 0.68, 0.36)
const COLOR_TEXT := Color(0.88, 0.84, 0.76)
const COLOR_TEXT_DIM := Color(0.56, 0.53, 0.48)
const COLOR_TITLE := Color(0.95, 0.82, 0.55)
const COLOR_GOOD := Color(0.45, 0.88, 0.45)
const COLOR_BAD := Color(0.92, 0.32, 0.3)
const COLOR_GOLD := Color(0.96, 0.8, 0.32)
const COLOR_MOD := Color(0.55, 0.6, 1.0)          # affix / modifier text
const COLOR_IMPLICIT := Color(0.7, 0.75, 1.0)
const COLOR_UNIQUE_FLAVOR := Color(0.75, 0.45, 0.2)
const COLOR_LIFE := Color(0.78, 0.1, 0.12)
const COLOR_MANA := Color(0.15, 0.3, 0.85)
const COLOR_ES := Color(0.6, 0.85, 1.0)
const COLOR_XP := Color(0.85, 0.7, 0.25)

## Index = Item.Rarity (NORMAL, MAGIC, RARE, UNIQUE). Also used for monster rarity.
const RARITY_COLORS: Array[Color] = [
	Color(0.86, 0.86, 0.86),
	Color(0.45, 0.56, 1.0),
	Color(1.0, 0.9, 0.35),
	Color(0.92, 0.52, 0.16),
]
const RARITY_NAMES: Array[String] = ["Normal", "Magic", "Rare", "Unique"]

const DAMAGE_COLORS := {
	"physical": Color(0.92, 0.9, 0.86),
	"fire": Color(1.0, 0.5, 0.15),
	"cold": Color(0.45, 0.78, 1.0),
	"lightning": Color(1.0, 0.95, 0.35),
	"chaos": Color(0.78, 0.35, 0.95),
	"heal": Color(0.4, 0.95, 0.4),
	"mana": Color(0.4, 0.55, 1.0),
	"player_hurt": Color(1.0, 0.25, 0.2),
	"evade": Color(0.8, 0.8, 0.8),
	"block": Color(0.8, 0.8, 0.8),
	"immune": Color(0.8, 0.8, 0.8),
	"xp": Color(0.85, 0.7, 0.25),
}

const FONT_SMALL := 14
const FONT_NORMAL := 17
const FONT_LARGE := 22
const FONT_TITLE := 30


static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]


static func damage_color(kind: String) -> Color:
	return DAMAGE_COLORS.get(kind, COLOR_TEXT)


static func panel_style(bg: Color = COLOR_PANEL, border: Color = COLOR_BORDER, border_width: int = 2, radius: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	return sb


static func make_panel(bg: Color = COLOR_PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func make_label(text: String, size: int = FONT_NORMAL, color: Color = COLOR_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func make_button(text: String, size: int = FONT_NORMAL) -> Button:
	var b := Button.new()
	b.text = text
	# Never keep keyboard focus: Space (dodge) / Tab (minimap) must not re-trigger buttons.
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", panel_style(COLOR_PANEL_LIGHT, COLOR_BORDER, 1, 3))
	b.add_theme_stylebox_override("hover", panel_style(COLOR_SLOT_HOVER, COLOR_BORDER_BRIGHT, 1, 3))
	b.add_theme_stylebox_override("pressed", panel_style(COLOR_BG, COLOR_BORDER_BRIGHT, 1, 3))
	b.add_theme_stylebox_override("disabled", panel_style(COLOR_BG, COLOR_BORDER.darkened(0.4), 1, 3))
	b.add_theme_color_override("font_color", COLOR_TEXT)
	b.add_theme_color_override("font_hover_color", COLOR_TITLE)
	b.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)
	return b


## Title bar with an optional close button; returns the HBoxContainer.
static func make_title_bar(title: String, on_close: Callable = Callable()) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var l := make_label(title, FONT_LARGE, COLOR_TITLE)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	if on_close.is_valid():
		var x := make_button("X", FONT_SMALL)
		x.custom_minimum_size = Vector2(28, 28)
		x.pressed.connect(on_close)
		hb.add_child(x)
	return hb


## Theme applied at the UI root so default controls match the palette.
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_NORMAL
	t.set_color("font_color", "Label", COLOR_TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("normal", "Button", panel_style(COLOR_PANEL_LIGHT, COLOR_BORDER, 1, 3))
	t.set_stylebox("hover", "Button", panel_style(COLOR_SLOT_HOVER, COLOR_BORDER_BRIGHT, 1, 3))
	t.set_stylebox("pressed", "Button", panel_style(COLOR_BG, COLOR_BORDER_BRIGHT, 1, 3))
	t.set_color("font_color", "Button", COLOR_TEXT)
	t.set_color("font_hover_color", "Button", COLOR_TITLE)
	t.set_stylebox("normal", "LineEdit", panel_style(COLOR_BG, COLOR_BORDER, 1, 3))
	t.set_color("font_color", "LineEdit", COLOR_TEXT)
	return t
