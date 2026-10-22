extends Control
## The landscape table for a game against 3 bots (GDD §7, slice 5). It owns the
## game state, like a future online host. The human is seat 0 at the bottom; seats
## go clockwise: 1 on the left, 2 at the top (partner), 3 on the right.

const HUMAN := 0
const NAMES := ["Vous", "Gauche", "Partenaire", "Droite"]
const SUIT_NAMES := ["pique", "cœur", "carreau", "trèfle"]
const TEAM_NAMES := ["Nous", "Eux"]
const BOT_DELAY := 0.7
const TRICK_DELAY := 1.3
const FELT := Color(0.08, 0.33, 0.19)
const BUBBLE := Color(1, 0.98, 0.88)
const GOLD := Color(1, 0.84, 0.35)

var game := Belote.new()
var bot := BeloteBot.new()
var state: BeloteState

## A short text by each seat: its bid, its announces, "Belote".
var _bubbles: Array[String] = ["", "", "", ""]
## The full trick shown for a moment after its fourth card: {cards, leader}.
var _shown_trick: Dictionary = {}
## The taker and trump of the hand being scored, for the summary.
var _scored: Dictionary = {}
var _busy := false
var _overlay: Control
var _layer: Control


func _ready() -> void:
    var felt := ColorRect.new()
    felt.color = FELT
    felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
    felt.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(felt)
    _layer = Control.new()
    _layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _layer.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_layer)
    resized.connect(_refresh)
    new_game()


func new_game(seed_value := -1) -> void:
    state = game.new_state(seed_value if seed_value >= 0 else randi())
    _bubbles = ["", "", "", ""]
    _close_overlay()
    _refresh()
    _advance()


## Lets the next bot play, or waits for the human.
func _advance() -> void:
    if _busy or _overlay != null or not is_inside_tree():
        return
    if game.is_over(state):
        _show_summary()
        return
    if state.to_act == HUMAN:
        _refresh()
        return
    _busy = true
    await get_tree().create_timer(BOT_DELAY).timeout
    _busy = false
    if _overlay == null and not game.is_over(state) and state.to_act != HUMAN:
        _apply(bot.choose(game.view_for(state, state.to_act)))


func _apply(move: Dictionary) -> void:
    var seat := state.to_act
    var deal := state.deal_number
    var playing := state.phase == BeloteState.Phase.PLAYING
    var trick := state.trick.duplicate()
    var leader := state.trick_leader
    _scored = {"taker": state.taker, "trump": state.trump}
    _bubbles[seat] = _bubble_for(seat, move)
    game.apply(state, move)
    if move.kind == "take":
        _bubbles = ["", "", "", ""]
        _bubbles[seat] = "Prend à %s" % SUIT_NAMES[move.suit]
    if playing and trick.size() == 3:
        trick.append(move.card)
        _shown_trick = {"cards": trick, "leader": leader}
        _busy = true
        _refresh()
        await get_tree().create_timer(TRICK_DELAY).timeout
        _busy = false
        _shown_trick = {}
        _after_trick()
    if state.deal_number != deal or game.is_over(state):
        _bubbles = ["", "", "", ""]
        if playing:
            _show_summary()
        else:
            _bubbles[state.to_act] = "Tout le monde passe : on redistribue"
    _refresh()
    _advance()


## What a seat says as it moves: its bid, then its announces and belote as it plays.
func _bubble_for(seat: int, move: Dictionary) -> String:
    if move.kind == "pass":
        return "Passe"
    if move.kind != "play":
        return ""
    var words: Array[String] = []
    if state.hands[seat].size() == 8:
        for announce in state.announces[seat]:
            words.append(announce.name)
    var king := Cards.make(state.trump, Cards.Rank.ROI)
    var queen := Cards.make(state.trump, Cards.Rank.DAME)
    if seat == state.belote_seat and (move.card == king or move.card == queen):
        var other := queen if move.card == king else king
        words.append("Rebelote" if state.played.has(other) else "Belote")
    return ", ".join(words)


## After the first trick only the winning announces stay up, with their points.
func _after_trick() -> void:
    var winners: Array[String] = ["", "", "", ""]
    if state.played.size() == 4 and state.announce_team >= 0:
        for seat in 4:
            if seat % 2 == state.announce_team and not state.announces[seat].is_empty():
                var names: Array[String] = []
                for announce in state.announces[seat]:
                    names.append("%s (%d)" % [announce.name, announce.points])
                winners[seat] = ", ".join(names)
    _bubbles = winners


func _on_card_pressed(card: int) -> void:
    if _busy or _overlay != null or state.to_act != HUMAN:
        return
    var move := {"kind": "play", "card": card}
    if game.legal_moves(state).has(move):
        _apply(move)


func _on_bid_pressed(move: Dictionary) -> void:
    if not _busy and _overlay == null and state.to_act == HUMAN:
        _apply(move)


# --- Drawing -----------------------------------------------------------------

func _refresh() -> void:
    if _layer == null or state == null:
        return
    for child in _layer.get_children():
        _layer.remove_child(child)
        child.queue_free()
    var w := size.x
    var h := size.y
    var card_size := Vector2(h * 0.175, h * 0.25)
    var small := card_size * 0.5
    _draw_hand(card_size)
    _draw_opponents(small)
    _draw_center(card_size)
    _draw_bubbles(card_size, small)
    _draw_info()
    if state.to_act == HUMAN and _shown_trick.is_empty() and _overlay == null \
            and state.phase != BeloteState.Phase.PLAYING and state.phase != BeloteState.Phase.GAME_OVER:
        _draw_bid_buttons(Vector2(w / 2, h - card_size.y - 80))


func _draw_hand(card_size: Vector2) -> void:
    var hand: Array[int] = (state.hands[HUMAN] as Array[int]).duplicate()
    hand.sort_custom(_display_order)
    var my_turn := state.to_act == HUMAN and state.phase == BeloteState.Phase.PLAYING \
            and _shown_trick.is_empty()
    var legal: Array[int] = []
    if my_turn:
        legal = game.legal_cards(state)
    var n := hand.size()
    var step := minf(card_size.x * 0.85, (size.x * 0.7 - card_size.x) / maxf(n - 1, 1))
    var x := size.x / 2 - (step * (n - 1) + card_size.x) / 2
    for card in hand:
        var view := CardView.new(card, card_size)
        var playable := legal.has(card)
        view.position = Vector2(x, size.y - card_size.y - 12 - (18 if playable else 0))
        view.dimmed = my_turn and not playable
        if playable:
            view.mouse_filter = Control.MOUSE_FILTER_STOP
            view.pressed.connect(_on_card_pressed)
        _layer.add_child(view)
        x += step


## Suits side by side, alternating colours, strongest first; trumps on the left.
func _display_order(a: int, b: int) -> bool:
    var order := [Cards.Suit.PIQUE, Cards.Suit.COEUR, Cards.Suit.TREFLE, Cards.Suit.CARREAU]
    var ka: int = order.find(Cards.suit_of(a))
    var kb: int = order.find(Cards.suit_of(b))
    if state.trump >= 0:
        ka = -1 if Cards.suit_of(a) == state.trump else ka
        kb = -1 if Cards.suit_of(b) == state.trump else kb
    if ka != kb:
        return ka < kb
    var trump := state.trump if state.trump >= 0 else -1
    return BeloteCards.strength(a, trump) > BeloteCards.strength(b, trump)


func _draw_opponents(small: Vector2) -> void:
    for seat in [1, 2, 3]:
        var n: int = state.hands[seat].size()
        for i in n:
            var back := CardView.new(-1, small)
            match seat:
                1: back.position = Vector2(16, size.y / 2 - small.y / 2 - (n - 1) * 9 + i * 18)
                2: back.position = Vector2(size.x / 2 - small.x / 2 - (n - 1) * 11 + i * 22, 12)
                3: back.position = Vector2(size.x - 16 - small.x, size.y / 2 - small.y / 2 - (n - 1) * 9 + i * 18)
            _layer.add_child(back)


func _seat_anchor(seat: int, card_size: Vector2, small: Vector2) -> Vector2:
    match seat:
        0: return Vector2(size.x / 2, size.y - card_size.y - 50)
        1: return Vector2(30 + small.x + 70, size.y / 2 - small.y * 0.9)
        2: return Vector2(size.x / 2, 30 + small.y + 24)
        _: return Vector2(size.x - 30 - small.x - 70, size.y / 2 - small.y * 0.9)


func _draw_center(card_size: Vector2) -> void:
    var center := Vector2(size.x / 2, size.y * 0.44)
    if state.phase == BeloteState.Phase.BID_ROUND_1 or state.phase == BeloteState.Phase.BID_ROUND_2:
        if _overlay == null:
            var turned := CardView.new(state.turned, card_size)
            turned.position = center - card_size / 2
            _layer.add_child(turned)
        return
    var cards: Array = state.trick
    var leader := state.trick_leader
    if not _shown_trick.is_empty():
        cards = _shown_trick.cards
        leader = _shown_trick.leader
    var offsets := [Vector2(0, card_size.y * 0.33), Vector2(-card_size.x * 0.9, 0),
            Vector2(0, -card_size.y * 0.33), Vector2(card_size.x * 0.9, 0)]
    for i in cards.size():
        var view := CardView.new(cards[i], card_size)
        view.position = center + offsets[(leader + i) % 4] - card_size / 2
        _layer.add_child(view)


func _draw_bubbles(card_size: Vector2, small: Vector2) -> void:
    for seat in 4:
        var text := _bubbles[seat]
        var anchor := _seat_anchor(seat, card_size, small)
        if seat != HUMAN:
            var name_label := _label(NAMES[seat] + (" (donneur)" if seat == state.dealer else ""), 20,
                    GOLD if state.to_act == seat else Color.WHITE)
            _layer.add_child(name_label)
            name_label.position = anchor + Vector2(-name_label.get_minimum_size().x / 2, -44)
        if text.is_empty():
            continue
        var bubble := _label(text, 22, Color(0.1, 0.1, 0.1))
        var style := StyleBoxFlat.new()
        style.bg_color = BUBBLE
        style.set_corner_radius_all(12)
        style.set_content_margin_all(8)
        bubble.add_theme_stylebox_override("normal", style)
        _layer.add_child(bubble)
        bubble.position = anchor - Vector2(bubble.get_minimum_size().x / 2, 0)


func _draw_info() -> void:
    var score := _label("Nous %d  ·  Eux %d   (en %d)" % [state.scores[0], state.scores[1],
            game.rules.target], 24, Color.WHITE)
    score.position = Vector2(20, 14)
    _layer.add_child(score)
    if state.reserve > 0:
        var reserve := _label("Litige en réserve : %d" % state.reserve, 20, GOLD)
        reserve.position = Vector2(20, 48)
        _layer.add_child(reserve)
    if state.trump < 0:
        var dealer := _label("Donneur : %s" % NAMES[state.dealer], 20, Color.WHITE)
        _layer.add_child(dealer)
        dealer.position = Vector2(size.x - 20 - dealer.get_minimum_size().x, 14)
        return
    var info := _label("Atout       pris par %s" % NAMES[state.taker], 22, Color.WHITE)
    _layer.add_child(info)
    info.position = Vector2(size.x - 20 - info.get_minimum_size().x, 14)
    var badge := Panel.new()
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.98, 0.97, 0.93)
    style.set_corner_radius_all(8)
    badge.add_theme_stylebox_override("panel", style)
    badge.size = Vector2(40, 40)
    badge.position = info.position + Vector2(70, -4)
    var icon := SuitIcon.new()
    icon.suit = state.trump
    icon.size = Vector2(32, 32)
    icon.position = Vector2(4, 4)
    badge.add_child(icon)
    _layer.add_child(badge)


func _draw_bid_buttons(center: Vector2) -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    for move in game.legal_moves(state):
        var button := Button.new()
        button.text = "Passer" if move.kind == "pass" else "Prendre à %s" % SUIT_NAMES[move.suit]
        button.add_theme_font_size_override("font_size", 26)
        button.custom_minimum_size = Vector2(150, 64)
        button.pressed.connect(_on_bid_pressed.bind(move))
        row.add_child(button)
    _layer.add_child(row)
    row.position = center - Vector2(row.get_combined_minimum_size().x / 2, 0)


func _label(text: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


# --- Hand and game summary -----------------------------------------------------

func _show_summary() -> void:
    if _overlay != null:
        return
    var result := state.last_hand
    var panel := PanelContainer.new()
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.1, 0.12, 0.14, 0.95)
    style.set_corner_radius_all(16)
    style.set_content_margin_all(24)
    panel.add_theme_stylebox_override("panel", style)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    panel.add_child(column)
    var titles := {"fait": "Contrat rempli", "dedans": "Dedans !", "litige": "Litige"}
    if game.is_over(state):
        column.add_child(_label("Vous gagnez la partie !" if state.winner == 0 else "Vous perdez la partie", 34, GOLD))
    column.add_child(_label(titles.get(result.get("outcome", ""), ""), 30, Color.WHITE))
    if _scored.get("taker", -1) >= 0:
        column.add_child(_label("Pris par %s à %s" % [NAMES[_scored.taker], SUIT_NAMES[_scored.trump]],
                20, Color(0.8, 0.8, 0.8)))
    var grid := GridContainer.new()
    grid.columns = 3
    grid.add_theme_constant_override("h_separation", 40)
    var rows := [["", TEAM_NAMES[0], TEAM_NAMES[1]],
            ["Annonces", result.announces[0], result.announces[1]],
            ["Belote", result.belote[0], result.belote[1]],
            ["Points", result.raw[0], result.raw[1]],
            ["Marqués", result.points[0], result.points[1]],
            ["Total", state.scores[0], state.scores[1]]]
    for row in rows:
        for cell in row:
            grid.add_child(_label(str(cell), 22, Color.WHITE))
    column.add_child(grid)
    var buttons := HBoxContainer.new()
    buttons.add_theme_constant_override("separation", 16)
    if game.is_over(state):
        buttons.add_child(_button("Rejouer", func() -> void: new_game()))
        buttons.add_child(_button("Menu", func() -> void:
                get_tree().change_scene_to_file("res://ui/main.tscn")))
    else:
        buttons.add_child(_button("Continuer", func() -> void:
                _close_overlay()
                _refresh()
                _advance()))
    column.add_child(buttons)
    _overlay = panel
    add_child(panel)
    panel.position = (size - panel.get_combined_minimum_size()) / 2


func _button(text: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.add_theme_font_size_override("font_size", 26)
    button.custom_minimum_size = Vector2(180, 64)
    button.pressed.connect(action)
    return button


func _close_overlay() -> void:
    if _overlay != null:
        _overlay.queue_free()
        _overlay = null


## Android back: leave the table for the home screen.
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        get_tree().change_scene_to_file("res://ui/main.tscn")
