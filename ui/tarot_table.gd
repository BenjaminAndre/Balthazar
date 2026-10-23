extends Control
## The landscape Tarot table (GDD §4.2) for 3, 4 or 5 players. Like the Belote
## table, it only plays the packets a TarotHost sends and turns taps into
## `move_chosen`. We sit at the bottom; the others spread over the top of the
## table, clockwise from our left.

signal move_chosen(move: Dictionary)
signal continued
signal left

const TRICK_DELAY := 1.3
const LAST_TRICK_DELAY := 2.4
const BUBBLE := Color(1, 0.98, 0.88)
const GOLD := Color(1, 0.84, 0.35)

## Set before the scene opens (Session): how many players, for a solo game.
var players := 4
var host: TarotHost
var _me := 0
var _view: Dictionary = {}
var _queue: Array[Dictionary] = []
var _playing := false
var _bubbles: Array[String] = []
var _shown_trick: Dictionary = {}
var _hide_hands := false
## The chien, shown in the middle for a moment once a petite or a garde is taken.
var _shown_chien: Array = []
var _overlay: Control
var _layer: Control
var _felt: ShaderMaterial

var _seen_deal := -1
var _seen_hand: Dictionary = {}
var _seen_backs: Array[int] = []
var _center_count := 0
var _center_leader := -1
var _trick_views: Array[CardView] = []
var _floating: Array = []
var _time := 0.0


func _ready() -> void:
    theme = TableTheme.make()
    var felt := ColorRect.new()
    _felt = ShaderMaterial.new()
    _felt.shader = preload("res://ui/felt.gdshader")
    felt.material = _felt
    felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
    felt.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(felt)
    _layer = Control.new()
    _layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _layer.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_layer)
    resized.connect(_refresh)
    var setup := Session.take_table_setup()
    if setup.is_valid():
        setup.call(self)
    else:
        play_solo()


## A game against bots, with us in seat 0.
func play_solo(seed_value := -1) -> TarotHost:
    host = TarotHost.new(players)
    add_child(host)
    host.settings = TableSettings.load_profile()
    attach(host, 0)
    left.connect(func() -> void: get_tree().change_scene_to_file("res://ui/main.tscn"))
    host.start(seed_value)
    return host


func attach(table_host: Node, seat: int) -> void:
    table_host.packet.connect(func(s: int, data: Dictionary) -> void:
        if s == seat:
            receive(data))
    move_chosen.connect(func(move: Dictionary) -> void: table_host.submit(seat, move))
    continued.connect(func() -> void: table_host.continue_from(seat))


func receive(data: Dictionary) -> void:
    _queue.append(data)
    if not _playing:
        _play_queue()


func _process(delta: float) -> void:
    _time += delta
    for entry in _floating:
        var view: CardView = entry[0]
        if is_instance_valid(view) and not view.has_meta("moving"):
            view.position.y = entry[1] + sin(_time * 2.4 + entry[2]) * 3.0


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        left.emit()


# --- Packets ----------------------------------------------------------------------

func _play_queue() -> void:
    _playing = true
    while not _queue.is_empty() and is_inside_tree():
        var data: Dictionary = _queue.pop_front()
        await _play(data.event, data.view)
    _playing = false


func _play(event: Dictionary, view: Dictionary) -> void:
    _me = view.seat
    players = view.players
    if _bubbles.size() != players:
        _bubbles = []
        _seen_backs = []
        for i in players:
            _bubbles.append("")
            _seen_backs.append(0)
    if event.kind == "start":
        _view = view
        _clear_bubbles()
        _close_overlay()
        _refresh()
        return
    var seat: int = event.seat
    if event.say != "":
        _bubbles[seat] = event.say
    if event.has("chien"):
        _view = view
        _shown_chien = event.chien
        _refresh()
        await get_tree().create_timer(2.0).timeout
        _shown_chien = []
        _clear_bubbles()
    if event.has("trick"):
        _shown_trick = event.trick
        _hide_hands = event.has("hand_end")
        _view = view
        _refresh()
        await get_tree().create_timer(LAST_TRICK_DELAY if _hide_hands else TRICK_DELAY).timeout
        await _sweep_trick(event.trick.winner)
        _shown_trick = {}
        _clear_bubbles()
    _view = view
    if event.has("hand_end"):
        _clear_bubbles()
        _show_summary(event.hand_end)
        _refresh()
        await continued
        _hide_hands = false
        if event.hand_end.game_over:
            return
    elif event.has("redeal"):
        _clear_bubbles()
        _bubbles[view.to_act] = "Personne ne prend : on redistribue"
    _refresh()


func _clear_bubbles() -> void:
    for i in _bubbles.size():
        _bubbles[i] = ""


func _sweep_trick(winner: int) -> void:
    if _trick_views.is_empty():
        return
    var target := _seat_origin(winner)
    var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    for view in _trick_views:
        if is_instance_valid(view):
            tween.tween_property(view, "position", target - view.size / 2, 0.35)
            tween.tween_property(view, "scale", Vector2.ONE * 0.45, 0.35)
            tween.tween_property(view, "modulate:a", 0.0, 0.35)
    await tween.finished


func _choose(move: Dictionary) -> void:
    if _playing or _overlay != null or not _my_turn():
        return
    if _view.legal.has(move):
        move_chosen.emit(move)


func _on_card_pressed(card: int) -> void:
    var kind := "discard" if int(_view.phase) == TarotState.Phase.ECART else "play"
    _choose({"kind": kind, "card": card})


func _my_turn() -> bool:
    return not _view.is_empty() and _view.to_act == _me and int(_view.phase) != TarotState.Phase.GAME_OVER


# --- Seats ------------------------------------------------------------------------

## 0 = us, then the others clockwise from our left.
func _place(seat: int) -> int:
    return (seat - _me + players) % players


## The direction of a seat from the middle of the table (us: straight down).
func _direction(seat: int) -> Vector2:
    var place := _place(seat)
    if place == 0:
        return Vector2(0, 1)
    # The others share the top half, from left (180°) to right (0°).
    var others := players - 1
    var t := float(place - 1) / maxf(others - 1, 1)
    var angle := deg_to_rad(lerpf(185.0, -5.0, t)) if others > 1 else deg_to_rad(90.0)
    if others == 2:
        angle = deg_to_rad(lerpf(160.0, 20.0, t))
    return Vector2(cos(angle), -sin(angle))


func _center() -> Vector2:
    return Vector2(size.x / 2, size.y * 0.42)


## Where a seat's hand is, on screen.
func _seat_origin(seat: int) -> Vector2:
    if _place(seat) == 0:
        return Vector2(size.x / 2, size.y - size.y * 0.11)
    var d := _direction(seat)
    return _center() + Vector2(d.x * size.x * 0.44, d.y * size.y * 0.36)


func _name(seat: int) -> String:
    if seat == _me:
        return "Vous"
    var names: Array = _view.get("names", [])
    if _view.get("humans", [])[seat] and seat < names.size() and names[seat] != "":
        return names[seat]
    return "Bot %d" % _place(seat)


# --- Drawing ----------------------------------------------------------------------

func _refresh() -> void:
    if _layer == null or _view.is_empty():
        return
    for child in _layer.get_children():
        _layer.remove_child(child)
        child.queue_free()
    if _felt:
        _felt.set_shader_parameter("size", size)
    var card_size := Vector2(size.y * 0.155, size.y * 0.22)
    var small := card_size * 0.45
    _floating.clear()
    _trick_views.clear()
    if _overlay == null:
        if not _hide_hands and _view.deal_number != _seen_deal:
            _seen_deal = _view.deal_number
            _seen_hand.clear()
            for i in _seen_backs.size():
                _seen_backs[i] = 0
            _center_count = 0
        if not _hide_hands:
            _draw_hand(card_size)
            _draw_opponents(small)
        _draw_center(card_size)
    _draw_names_and_bubbles()
    _draw_info()
    if _my_turn() and _shown_trick.is_empty() and _overlay == null and not _hide_hands:
        match int(_view.phase):
            TarotState.Phase.BIDDING:
                _draw_bid_buttons()
            TarotState.Phase.CALLING:
                _draw_call_buttons()


func _draw_hand(card_size: Vector2) -> void:
    var hand: Array[int] = []
    hand.assign(_view.hand)
    hand.sort_custom(_display_order)
    var phase := int(_view.phase)
    var choosing := _my_turn() and (phase == TarotState.Phase.PLAYING or phase == TarotState.Phase.ECART) \
            and _shown_trick.is_empty() and _shown_chien.is_empty()
    var legal: Array[int] = []
    if choosing:
        for move in _view.legal:
            legal.append(move.card)
    var n := hand.size()
    var step := minf(card_size.x * 0.8, (size.x * 0.9 - card_size.x) / maxf(n - 1, 1))
    var mid := (n - 1) / 2.0
    var arriving := 0
    for i in n:
        var card := hand[i]
        var view := CardView.new(card, card_size)
        view.tarot = true
        var playable := legal.has(card)
        var k := i - mid
        view.rotation_degrees = k * 1.1
        view.position = Vector2(size.x / 2 + k * step - card_size.x / 2,
                size.y - card_size.y - 16 + k * k * 0.35 - (18 if playable else 0))
        view.dimmed = choosing and not playable
        view.lifted = playable
        if playable:
            view.mouse_filter = Control.MOUSE_FILTER_STOP
            view.pressed.connect(_on_card_pressed)
            _floating.append([view, view.position.y, i * 0.5])
        _layer.add_child(view)
        if not _seen_hand.has(card):
            _fly_in(view, _center(), arriving * 0.03)
            arriving += 1
    _seen_hand.clear()
    for card in hand:
        _seen_hand[card] = true


## Trumps first (from the 21 down), then the suits alternating colours, the
## Excuse last.
func _display_order(a: int, b: int) -> bool:
    var order := [TarotCards.TRUMP_SUIT, Cards.Suit.PIQUE, Cards.Suit.COEUR, Cards.Suit.TREFLE,
            Cards.Suit.CARREAU, TarotCards.EXCUSE_SUIT]
    var ka: int = order.find(TarotCards.suit_of(a))
    var kb: int = order.find(TarotCards.suit_of(b))
    if ka != kb:
        return ka < kb
    return TarotCards.strength(a) > TarotCards.strength(b)


func _draw_opponents(small: Vector2) -> void:
    for seat in players:
        if seat == _me:
            continue
        var n: int = _view.hand_sizes[seat]
        var origin := _seat_origin(seat)
        var d := _direction(seat)
        var along := Vector2(-d.y, d.x)
        var mid := (n - 1) / 2.0
        var spread := minf(9.0, 140.0 / maxf(n, 1))
        for i in n:
            var back := CardView.new(-1, small)
            back.tarot = true
            var k := i - mid
            back.position = origin + along * k * spread - small / 2
            back.rotation = d.angle() - PI / 2 + k * 0.02
            _layer.add_child(back)
            if i >= _seen_backs[seat]:
                _fly_in(back, _center(), (i - _seen_backs[seat]) * 0.02, 1.6)
        _seen_backs[seat] = n


func _draw_center(card_size: Vector2) -> void:
    var center := _center()
    if not _shown_chien.is_empty() or (not _view.chien.is_empty() and _shown_trick.is_empty()):
        # The chien, face up, while the taker discards.
        var chien: Array = _shown_chien if not _shown_chien.is_empty() else _view.chien
        var step := card_size.x * 0.75
        var left := center.x - (step * (chien.size() - 1) + card_size.x) / 2
        for i in chien.size():
            var view := CardView.new(chien[i], card_size)
            view.tarot = true
            view.position = Vector2(left + i * step, center.y - card_size.y / 2)
            _layer.add_child(view)
        return
    var cards: Array = _view.trick
    var leader: int = _view.trick_leader
    if not _shown_trick.is_empty():
        cards = _shown_trick.cards
        leader = _shown_trick.leader
    var fresh := cards.size() > _center_count and (leader == _center_leader or _center_count == 0)
    var master := TarotCards.winning_index(cards) if not cards.is_empty() else -1
    for i in cards.size():
        var card: int = cards[i]
        var seat := (leader + i) % players
        var view := CardView.new(card, card_size)
        view.tarot = true
        var d := _direction(seat)
        view.position = center + Vector2(d.x * card_size.x * 1.0, d.y * card_size.y * 0.45) - card_size / 2
        view.rotation_degrees = ((card * 37) % 11 - 5) * 1.1
        view.highlighted = i == master and card != TarotCards.EXCUSE
        _layer.add_child(view)
        _trick_views.append(view)
        if fresh and i == cards.size() - 1:
            _fly_in(view, _seat_origin(seat), 0.0, 0.8 if seat == _me else 0.5)
    _center_count = cards.size()
    _center_leader = leader


func _fly_in(view: CardView, from: Vector2, delay: float, from_scale := 0.6) -> void:
    var target := view.position
    var target_rotation := view.rotation
    view.position = from - view.size / 2
    view.scale = Vector2.ONE * from_scale
    view.rotation = 0
    view.modulate.a = 0.0
    view.set_meta("moving", true)
    var tween := view.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_property(view, "position", target, 0.32).set_delay(delay)
    tween.tween_property(view, "scale", Vector2.ONE, 0.32).set_delay(delay)
    tween.tween_property(view, "rotation", target_rotation, 0.32).set_delay(delay)
    tween.tween_property(view, "modulate:a", 1.0, 0.12).set_delay(delay)
    tween.chain().tween_callback(view.remove_meta.bind("moving"))


func _draw_names_and_bubbles() -> void:
    for seat in players:
        var anchor: Vector2
        if seat == _me:
            anchor = Vector2(size.x / 2, size.y - size.y * 0.22 - 70)
        else:
            var d := _direction(seat)
            # Inside the table, clear of the fan of cards: further in for the side seats.
            anchor = _seat_origin(seat) - d * (150.0 if absf(d.x) > 0.6 else 75.0)
            var role := ""
            if seat == int(_view.taker):
                role = " (preneur)"
            elif seat == int(_view.partner):
                role = " (partenaire)"
            elif seat == int(_view.dealer):
                role = " (donneur)"
            var name_label := _label(_name(seat) + role, 20, GOLD if _view.to_act == seat else Color.WHITE)
            _layer.add_child(name_label)
            name_label.position = anchor + Vector2(-name_label.get_minimum_size().x / 2, -34)
        var text := _bubbles[seat] if seat < _bubbles.size() else ""
        if text.is_empty():
            continue
        var bubble := _label(text, 22, TableTheme.INK)
        var style := StyleBoxFlat.new()
        style.bg_color = BUBBLE
        style.border_color = TableTheme.GOLD
        style.set_border_width_all(2)
        style.set_corner_radius_all(12)
        style.set_content_margin_all(8)
        bubble.add_theme_stylebox_override("normal", style)
        _layer.add_child(bubble)
        bubble.position = anchor - Vector2(bubble.get_minimum_size().x / 2, 0)


func _draw_info() -> void:
    # Scores, one line per player.
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 0)
    var deal := mini(int(_view.deals_played) + 1, int(_view.deals_per_game))
    column.add_child(_label("Donne %d / %d" % [deal, int(_view.deals_per_game)], 20, GOLD))
    for seat in players:
        column.add_child(_label("%s : %d" % [_name(seat), int(_view.scores[seat])], 20, Color.WHITE))
    column.position = Vector2(20, 10)
    _layer.add_child(column)
    if int(_view.contract) <= TarotState.Contract.NONE:
        return
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.add_child(_label("%s par %s" % [TarotState.CONTRACT_NAMES[int(_view.contract)], _name(int(_view.taker))],
            22, Color.WHITE))
    if int(_view.called_card) >= 0:
        var called: int = _view.called_card
        row.add_child(_label("· appel :", 20, Color.WHITE))
        var view := CardView.new(called, Vector2(36, 52))
        view.tarot = true
        view.custom_minimum_size = Vector2(36, 52)
        row.add_child(view)
    _layer.add_child(row)
    row.position = Vector2(size.x - 20 - row.get_combined_minimum_size().x, 10)
    if int(_view.phase) == TarotState.Phase.ECART:
        var count := (_view.ecart as Array).size()
        var text := "Écartez %d cartes (%d / %d)" % [(_view.chien as Array).size(), count, (_view.chien as Array).size()] \
                if _view.taker == _me else "%s fait son écart" % _name(int(_view.taker))
        var hint := _label(text, 22, GOLD)
        _layer.add_child(hint)
        hint.position = Vector2(size.x / 2 - hint.get_minimum_size().x / 2, _center().y + size.y * 0.15)


func _draw_bid_buttons() -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    for move in _view.legal:
        var button := Button.new()
        button.text = "Passer" if move.contract == TarotState.Contract.NONE else TarotState.CONTRACT_NAMES[move.contract]
        button.custom_minimum_size = Vector2(140, 60)
        button.pressed.connect(_choose.bind(move))
        row.add_child(button)
    _layer.add_child(row)
    row.position = Vector2(size.x / 2 - row.get_combined_minimum_size().x / 2, size.y - size.y * 0.22 - 110)


func _draw_call_buttons() -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    for move in _view.legal:
        var button := Button.new()
        button.custom_minimum_size = Vector2(170, 64)
        var inner := HBoxContainer.new()
        inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
        inner.alignment = BoxContainer.ALIGNMENT_CENTER
        inner.set_anchors_preset(Control.PRESET_FULL_RECT)
        var rank := "Roi" if TarotCards.rank_of(move.card) == TarotCards.Rank.ROI else "Dame"
        var text := _label("Appeler %s" % rank.to_lower(), 22, TableTheme.INK)
        text.mouse_filter = Control.MOUSE_FILTER_IGNORE
        inner.add_child(text)
        var icon := SuitIcon.new()
        icon.suit = TarotCards.suit_of(move.card)
        icon.custom_minimum_size = Vector2(28, 28)
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        inner.add_child(icon)
        button.add_child(inner)
        button.pressed.connect(_choose.bind(move))
        row.add_child(button)
    _layer.add_child(row)
    row.position = Vector2(size.x / 2 - row.get_combined_minimum_size().x / 2, size.y - size.y * 0.22 - 110)


func _label(text: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


# --- Summary ------------------------------------------------------------------------

func _show_summary(hand_end: Dictionary) -> void:
    _close_overlay()
    var result: Dictionary = hand_end.result
    var panel := PanelContainer.new()
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 8)
    panel.add_child(column)
    var taker: int = result.taker
    var mine := taker == _me or int(result.partner) == _me
    if hand_end.game_over:
        var best: int = hand_end.winner
        column.add_child(_label("%s gagne la partie !" % ("Vous" if best == _me else _name(best)), 32,
                TableTheme.GREEN if best == _me else TableTheme.RED))
    var title := "%s %s" % [TarotState.CONTRACT_NAMES[int(result.contract)], "réussie" if result.made else "chutée"]
    column.add_child(_label(title, 28, TableTheme.GREEN if result.made == mine else TableTheme.RED))
    var who := "Preneur : %s" % _name(taker)
    if int(result.partner) >= 0:
        who += " · partenaire : %s" % _name(int(result.partner))
    column.add_child(_label(who, 20, TableTheme.INK.lightened(0.25)))
    column.add_child(_label("%s points pour %d demandés (%d bout%s)" % [_half(result.points), int(result.needed) / 2,
            result.oudlers, "s" if int(result.oudlers) > 1 else ""], 20, TableTheme.INK))
    if int(result.petit_au_bout) >= 0:
        column.add_child(_label("Petit au bout : %s" % _name(int(result.petit_au_bout)), 20, TableTheme.INK))
    column.add_child(HSeparator.new())
    var grid := GridContainer.new()
    grid.columns = 3
    grid.add_theme_constant_override("h_separation", 40)
    for cell in ["", "Donne", "Total"]:
        grid.add_child(_label(cell, 22, TableTheme.INK))
    for seat in players:
        grid.add_child(_label(_name(seat), 22, TableTheme.INK))
        grid.add_child(_label("%+d" % int(result.changes[seat]), 22, TableTheme.INK))
        grid.add_child(_label(str(int(hand_end.scores[seat])), 22, TableTheme.INK))
    column.add_child(grid)
    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    if hand_end.game_over:
        buttons.add_child(_button("Terminer", func() -> void: left.emit()))
    else:
        buttons.add_child(_button("Continuer", func() -> void:
                _close_overlay()
                continued.emit()))
    column.add_child(buttons)
    _overlay = panel
    add_child(panel)
    panel.position = (size - panel.get_combined_minimum_size()) / 2


## Half points as French text: 45 or 45,5.
func _half(half_points: int) -> String:
    return str(half_points / 2) + (",5" if half_points % 2 == 1 else "")


func _button(text: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(200, 60)
    button.pressed.connect(action)
    return button


func _close_overlay() -> void:
    if _overlay != null:
        _overlay.queue_free()
        _overlay = null
