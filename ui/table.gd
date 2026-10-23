extends Control
## The landscape table screen (GDD §7). It only shows what its seat may see: it
## plays the packets a TableHost sends (see TableHost) one after the other,
## animating each, and turns taps into `move_chosen`. The player always sits at
## the bottom; the others go clockwise from there: left, top (partner), right.

## The player picked a bid or a card.
signal move_chosen(move: Dictionary)
## The player closed the hand summary.
signal continued
## The player left the table (back button or the summary's Menu).
signal left

const TRICK_DELAY := 1.3
const LAST_TRICK_DELAY := 2.4
const FELT := Color(0.08, 0.33, 0.19)
const BUBBLE := Color(1, 0.98, 0.88)
const GOLD := Color(1, 0.84, 0.35)

## The host this screen runs itself (solo, or the online host), if any.
var host: TableHost
## Our seat, from the first packet.
var _me := 0
## The latest view the screen shows.
var _view: Dictionary = {}
var _queue: Array[Dictionary] = []
var _playing := false

## A short text by each seat (absolute seat index): its bid, announces, "Belote".
var _bubbles: Array[String] = ["", "", "", ""]
## The full trick shown for a moment after its fourth card: {cards, leader, winner}.
var _shown_trick: Dictionary = {}
## While the last trick of a hand shows, the next hand (already in the view) stays hidden.
var _hide_hands := false
var _show_last_trick := false
var _overlay: Control
var _layer: Control
var _felt: ShaderMaterial

# Animation bookkeeping: what the last refresh showed, so only new things move.
var _seen_deal := -1
var _seen_hand: Dictionary = {}
var _seen_backs: Array[int] = [0, 0, 0, 0]
var _seen_turned := -1
var _center_count := 0
var _center_leader := -1
var _trick_views: Array[CardView] = []
## Playable cards gently floating: [view, base_y, phase].
var _floating: Array = []
var _time := 0.0


func _ready() -> void:
    theme = TableTheme.make()
    var felt := ColorRect.new()
    felt.color = FELT
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


## A game against 3 bots: a host of our own, with us in seat 0.
func play_solo(seed_value := -1) -> TableHost:
    host = TableHost.new()
    add_child(host)
    host.set_bot_level(Session.bot_level)
    host.settings = TableSettings.load_profile()
    attach(host, 0)
    left.connect(func() -> void: get_tree().change_scene_to_file("res://ui/main.tscn"))
    host.start(seed_value)
    return host


## Wires this screen to a host in the same process, as `seat`.
func attach(host: TableHost, seat: int) -> void:
    host.packet.connect(func(s: int, data: Dictionary) -> void:
        if s == seat:
            receive(data))
    move_chosen.connect(func(move: Dictionary) -> void: host.submit(seat, move))
    continued.connect(func() -> void: host.continue_from(seat))


## One packet from the host, played after the ones before it.
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


# --- Playing the host's packets ------------------------------------------------

func _play_queue() -> void:
    _playing = true
    while not _queue.is_empty() and is_inside_tree():
        var data: Dictionary = _queue.pop_front()
        await _play(data.event, data.view)
    _playing = false


func _play(event: Dictionary, view: Dictionary) -> void:
    _me = view.seat
    if event.kind == "start":
        _view = view
        _bubbles = ["", "", "", ""]
        _close_overlay()
        _refresh()
        return
    var seat: int = event.seat
    var move: Dictionary = event.move
    if move.kind == "take":
        _bubbles = ["", "", "", ""]
    _bubbles[seat] = event.say
    if event.has("trick"):
        _shown_trick = event.trick
        _hide_hands = event.has("hand_end")
        # The view before this packet still has the trick's first three cards on the
        # table; take the new hands, scores and live points from the new one.
        _view = view
        _refresh()
        await get_tree().create_timer(LAST_TRICK_DELAY if _hide_hands else TRICK_DELAY).timeout
        await _sweep_trick(event.trick.winner)
        _shown_trick = {}
        _bubbles.assign(event.get("announces", ["", "", "", ""]))
    _view = view
    if event.has("hand_end"):
        _bubbles = ["", "", "", ""]
        _show_summary(event.hand_end)
        _refresh()
        await continued
        _hide_hands = false
        if event.hand_end.game_over:
            return
    elif event.has("redeal"):
        _bubbles = ["", "", "", ""]
        _bubbles[view.to_act] = "Relance : on redistribue" if move.kind == "relance" \
                else "Tout le monde passe : on redistribue"
    _refresh()


## The finished trick slides to its winner, shrinking and fading.
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


func _on_card_pressed(card: int) -> void:
    _choose({"kind": "play", "card": card})


func _choose(move: Dictionary) -> void:
    if _playing or _overlay != null or not _my_turn():
        return
    if _view.legal.has(move):
        move_chosen.emit(move)


func _my_turn() -> bool:
    return not _view.is_empty() and _view.to_act == _me and _view.phase != BeloteState.Phase.GAME_OVER


# --- Seats on screen -----------------------------------------------------------

## 0 = us at the bottom, 1 = left, 2 = top, 3 = right.
func _place(seat: int) -> int:
    return (seat - _me + 4) % 4


func _name(seat: int) -> String:
    if seat == _me:
        return "Vous"
    var names: Array = _view.get("names", [])
    if _view.get("humans", [false, false, false, false])[seat] and seat < names.size():
        return names[seat]
    return ["Vous", "Gauche", "Partenaire", "Droite"][_place(seat)]


## Our team first: "Nous", then "Eux".
func _team_points(points: Array) -> Array:
    return [points[_me % 2], points[1 - _me % 2]]


## Where a seat's cards come from and go to, on screen.
func _seat_origin(seat: int) -> Vector2:
    var card_h := size.y * 0.25
    match _place(seat):
        0: return Vector2(size.x / 2, size.y - card_h / 2)
        1: return Vector2(16 + card_h * 0.25, size.y / 2)
        2: return Vector2(size.x / 2, 12 + card_h * 0.25)
        _: return Vector2(size.x - 16 - card_h * 0.25, size.y / 2)


func _seat_anchor(seat: int, card_size: Vector2, small: Vector2) -> Vector2:
    match _place(seat):
        0: return Vector2(size.x / 2, size.y - card_size.y - 60)
        1: return Vector2(30 + small.x + 70, size.y / 2 - small.y * 0.9)
        2: return Vector2(size.x / 2, 30 + small.y + 24)
        _: return Vector2(size.x - 30 - small.x - 70, size.y / 2 - small.y * 0.9)


## Moves a freshly placed view in from `from` (centre point), with a delay.
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


# --- Drawing -------------------------------------------------------------------

func _refresh() -> void:
    if _layer == null or _view.is_empty():
        return
    for child in _layer.get_children():
        _layer.remove_child(child)
        child.queue_free()
    if _felt:
        _felt.set_shader_parameter("size", size)
    var card_size := Vector2(size.y * 0.175, size.y * 0.25)
    var small := card_size * 0.5
    _floating.clear()
    _trick_views.clear()
    # The next hand is already dealt while the last trick and the summary show:
    # deal it on screen once they are gone.
    if _overlay == null:
        if not _hide_hands and _view.deal_number != _seen_deal:
            _seen_deal = _view.deal_number
            _seen_hand.clear()
            _seen_backs = [0, 0, 0, 0]
            _seen_turned = -1
            _center_count = 0
        if not _hide_hands:
            _draw_hand(card_size)
            _draw_opponents(small)
        _draw_center(card_size)
        if not _hide_hands:
            _draw_shown_announces(card_size, small)
    _draw_bubbles(card_size, small)
    _draw_info()
    if _my_turn() and _shown_trick.is_empty() and _overlay == null and not _hide_hands \
            and _view.phase != BeloteState.Phase.PLAYING:
        _draw_bid_buttons(Vector2(size.x / 2, size.y - card_size.y - 90))


func _draw_hand(card_size: Vector2) -> void:
    var hand: Array[int] = []
    hand.assign(_view.hand)
    hand.sort_custom(_display_order)
    var my_turn: bool = _my_turn() and _view.phase == BeloteState.Phase.PLAYING and _shown_trick.is_empty()
    var legal: Array[int] = []
    if my_turn:
        for move in _view.legal:
            legal.append(move.card)
    var n := hand.size()
    var step := minf(card_size.x * 0.85, (size.x * 0.7 - card_size.x) / maxf(n - 1, 1))
    var mid := (n - 1) / 2.0
    var deck := Vector2(size.x / 2, size.y * 0.44)
    var arriving := 0
    for i in n:
        var card := hand[i]
        var view := CardView.new(card, card_size)
        var playable := legal.has(card)
        var k := i - mid
        # A gentle fan: cards tilt outwards and drop a little towards the ends.
        view.rotation_degrees = k * 2.2
        view.position = Vector2(size.x / 2 + k * step - card_size.x / 2,
                size.y - card_size.y - 20 + k * k * 1.5 - (18 if playable else 0))
        view.dimmed = my_turn and not playable
        view.lifted = playable
        if playable:
            view.mouse_filter = Control.MOUSE_FILTER_STOP
            view.pressed.connect(_on_card_pressed)
            _floating.append([view, view.position.y, i * 0.7])
        _layer.add_child(view)
        if not _seen_hand.has(card):
            _fly_in(view, deck, arriving * 0.07)
            arriving += 1
    _seen_hand.clear()
    for card in hand:
        _seen_hand[card] = true


## Suits side by side, alternating colours, strongest first; trumps on the left.
func _display_order(a: int, b: int) -> bool:
    var trump: int = _view.trump
    var order := [Cards.Suit.PIQUE, Cards.Suit.COEUR, Cards.Suit.TREFLE, Cards.Suit.CARREAU]
    var ka: int = order.find(Cards.suit_of(a))
    var kb: int = order.find(Cards.suit_of(b))
    if trump >= 0:
        ka = -1 if Cards.suit_of(a) == trump else ka
        kb = -1 if Cards.suit_of(b) == trump else kb
    if ka != kb:
        return ka < kb
    return BeloteCards.strength(a, trump) > BeloteCards.strength(b, trump)


func _draw_opponents(small: Vector2) -> void:
    var deck := Vector2(size.x / 2, size.y * 0.44)
    for seat in 4:
        if seat == _me:
            continue
        var n: int = _view.hand_sizes[seat]
        var mid := (n - 1) / 2.0
        for i in n:
            var back := CardView.new(-1, small)
            var k := i - mid
            # Held cards fan towards the centre of the table.
            var c: Vector2
            match _place(seat):
                1:
                    c = Vector2(16 + small.y / 2 - k * k * 0.8, size.y / 2 + k * 15)
                    back.rotation_degrees = 90 + k * 3
                2:
                    c = Vector2(size.x / 2 + k * 18, 12 + small.y / 2 - k * k * 0.8)
                    back.rotation_degrees = 180 - k * 3
                _:
                    c = Vector2(size.x - 16 - small.y / 2 + k * k * 0.8, size.y / 2 + k * 15)
                    back.rotation_degrees = -90 - k * 3
            back.position = c - small / 2
            _layer.add_child(back)
            if i >= _seen_backs[seat]:
                _fly_in(back, deck, (i - _seen_backs[seat]) * 0.07, 1.6)
        _seen_backs[seat] = n


func _draw_center(card_size: Vector2) -> void:
    var center := Vector2(size.x / 2, size.y * 0.44)
    var bidding: bool = _view.phase == BeloteState.Phase.BID_ROUND_1 \
            or _view.phase == BeloteState.Phase.BID_ROUND_2
    if bidding and _shown_trick.is_empty() and not _hide_hands:
        var turned := CardView.new(_view.turned, card_size)
        turned.position = center - card_size / 2
        turned.rotation_degrees = -4
        _layer.add_child(turned)
        if _seen_turned != _view.turned:
            # Turned over once the hands are dealt: a flip on the horizontal axis.
            _seen_turned = _view.turned
            turned.scale = Vector2(0, 1)
            turned.create_tween().tween_property(turned, "scale", Vector2.ONE, 0.25) \
                    .set_delay(0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        _floating.append([turned, turned.position.y, 0.0])
        return
    var cards: Array = _view.trick
    var leader: int = _view.trick_leader
    var trump: int = _view.trump
    if not _shown_trick.is_empty():
        cards = _shown_trick.cards
        leader = _shown_trick.leader
        trump = _shown_trick.get("trump", trump)
    var offsets := [Vector2(0, card_size.y * 0.33), Vector2(-card_size.x * 0.9, 0),
            Vector2(0, -card_size.y * 0.33), Vector2(card_size.x * 0.9, 0)]
    var fresh := cards.size() > _center_count and (leader == _center_leader or _center_count == 0)
    var typed: Array[int] = []
    typed.assign(cards)
    var master := BeloteCards.winning_index(typed, trump) if not typed.is_empty() and trump >= 0 else -1
    for i in cards.size():
        var card: int = cards[i]
        var seat: int = (leader + i) % 4
        var view := CardView.new(card, card_size)
        view.position = center + offsets[_place(seat)] - card_size / 2
        # Each card lands slightly askew, always the same way for the same card.
        view.rotation_degrees = ((card * 37) % 11 - 5) * 1.1
        view.highlighted = i == master
        _layer.add_child(view)
        _trick_views.append(view)
        if fresh and i == cards.size() - 1:
            _fly_in(view, _seat_origin(seat), 0.0, 0.8 if seat == _me else 0.5)
    _center_count = cards.size()
    _center_leader = leader
    if _show_last_trick and not _view.last_trick.is_empty():
        _draw_last_trick(card_size * 0.55)


## The previous trick, small, under the scores, while "Dernier pli" is on.
func _draw_last_trick(mini: Vector2) -> void:
    var last: Dictionary = _view.last_trick
    var origin := Vector2(24, 120)
    for i in last.cards.size():
        var seat: int = (int(last.leader) + i) % 4
        var view := CardView.new(last.cards[i], mini)
        var offset: Vector2 = [Vector2(1, 2), Vector2(0, 1), Vector2(1, 0), Vector2(2, 1)][_place(seat)]
        view.position = origin + offset * Vector2(mini.x * 0.75, mini.y * 0.45)
        view.highlighted = seat == int(last.winner)
        _layer.add_child(view)


func _draw_bubbles(card_size: Vector2, small: Vector2) -> void:
    for seat in 4:
        var text := _bubbles[seat]
        var anchor := _seat_anchor(seat, card_size, small)
        if seat != _me:
            var dealer := " (donneur)" if seat == _view.dealer else ""
            var name_label := _label(_name(seat) + dealer, 20, GOLD if _view.to_act == seat else Color.WHITE)
            _layer.add_child(name_label)
            name_label.position = anchor + Vector2(-name_label.get_minimum_size().x / 2, -44)
        if text.is_empty():
            continue
        var bubble := _label(text, 22, TableTheme.INK)
        var style := StyleBoxFlat.new()
        style.bg_color = BUBBLE
        style.border_color = TableTheme.GOLD
        style.set_border_width_all(2)
        style.set_corner_radius_all(12)
        style.set_content_margin_all(8)
        style.shadow_color = Color(0, 0, 0, 0.3)
        style.shadow_size = 4
        bubble.add_theme_stylebox_override("normal", style)
        _layer.add_child(bubble)
        bubble.position = anchor - Vector2(bubble.get_minimum_size().x / 2, 0)


## "34", or "34 (+20)" when announces or the belote add points apart from the cards.
func _points_text(cards: int, extra: int) -> String:
    return "%d (+%d)" % [cards, extra] if extra > 0 else str(cards)


## The announce cards the table may see (the winning team's, during the second
## trick), in small, between each announcing player and the middle of the table.
func _draw_shown_announces(card_size: Vector2, small: Vector2) -> void:
    var mini := card_size * 0.5
    var center := Vector2(size.x / 2, size.y * 0.44)
    for seat in 4:
        var cards: Array[int] = []
        for entry in _view.announces[seat]:
            for card in entry.get("cards", []):
                if not cards.has(int(card)):
                    cards.append(int(card))
        if cards.is_empty():
            continue
        var anchor := _seat_anchor(seat, card_size, small)
        var spot := anchor.lerp(center, 0.4) if seat != _me else Vector2(size.x / 2, size.y - card_size.y - 120)
        var step := mini.x * 0.62
        var left := spot.x - (step * (cards.size() - 1) + mini.x) / 2
        for i in cards.size():
            var view := CardView.new(cards[i], mini)
            view.position = Vector2(left + i * step, spot.y - mini.y / 2)
            _layer.add_child(view)


func _draw_info() -> void:
    var scores := _team_points(_view.scores)
    var score := _label("Nous %d  ·  Eux %d   (en %d)" % [scores[0], scores[1], _view.target], 24, Color.WHITE)
    score.position = Vector2(20, 12)
    _layer.add_child(score)
    if _view.phase == BeloteState.Phase.PLAYING and not _hide_hands:
        var live := _team_points(_view.live_points)
        var extra := _team_points(_view.get("live_extra", [0, 0]))
        var hand := _label("Cette donne : Nous %s  ·  Eux %s" % [_points_text(live[0], extra[0]),
                _points_text(live[1], extra[1])], 20, GOLD)
        hand.position = Vector2(20, 46)
        _layer.add_child(hand)
        var last := Button.new()
        last.text = "Masquer le pli" if _show_last_trick else "Dernier pli"
        last.add_theme_font_size_override("font_size", 18)
        last.disabled = _view.last_trick.is_empty()
        last.pressed.connect(func() -> void:
            _show_last_trick = not _show_last_trick
            _refresh())
        _layer.add_child(last)
        last.position = Vector2(20, size.y - last.get_combined_minimum_size().y - 16)
    if _view.has("bot_level") and _view.humans.has(false):
        var level := _label("Bots : %s" % BeloteBots.NAMES.get(_view.bot_level, ""), 18, Color(1, 1, 1, 0.7))
        _layer.add_child(level)
        level.position = Vector2(size.x - 20 - level.get_minimum_size().x, size.y - 34)
    if _view.reserve > 0:
        var reserve := _label("Litige en réserve : %d" % _view.reserve, 20, GOLD)
        reserve.position = Vector2(20, 76)
        _layer.add_child(reserve)
    if _view.trump < 0 or _hide_hands:
        var dealer := _label("Donneur : %s" % _name(_view.dealer), 20, Color.WHITE)
        _layer.add_child(dealer)
        dealer.position = Vector2(size.x - 20 - dealer.get_minimum_size().x, 14)
        return
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    row.add_child(_label("Atout", 22, Color.WHITE))
    var badge := PanelContainer.new()
    var style := StyleBoxFlat.new()
    style.bg_color = TableTheme.PAPER
    style.border_color = TableTheme.GOLD
    style.set_border_width_all(2)
    style.set_corner_radius_all(8)
    style.set_content_margin_all(4)
    badge.add_theme_stylebox_override("panel", style)
    var icon := SuitIcon.new()
    icon.suit = _view.trump
    icon.custom_minimum_size = Vector2(30, 30)
    badge.add_child(icon)
    row.add_child(badge)
    row.add_child(_label("pris par %s" % _name(_view.taker), 22, Color.WHITE))
    _layer.add_child(row)
    row.position = Vector2(size.x - 20 - row.get_combined_minimum_size().x, 10)


func _draw_bid_buttons(center: Vector2) -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    for move in _view.legal:
        var button := Button.new()
        button.custom_minimum_size = Vector2(150, 64)
        if move.kind == "pass":
            button.text = "Passer"
        elif move.kind == "relance":
            button.text = "Relancer"
        else:
            # "Prendre" and the suit drawn, like the cards: no glyphs (CLAUDE.md).
            var inner := HBoxContainer.new()
            inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
            inner.add_theme_constant_override("separation", 10)
            inner.set_anchors_preset(Control.PRESET_FULL_RECT)
            inner.alignment = BoxContainer.ALIGNMENT_CENTER
            var text := _label("Prendre", 26, TableTheme.INK)
            text.mouse_filter = Control.MOUSE_FILTER_IGNORE
            inner.add_child(text)
            var icon := SuitIcon.new()
            icon.suit = move.suit
            icon.custom_minimum_size = Vector2(30, 30)
            icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
            inner.add_child(icon)
            button.custom_minimum_size = Vector2(200, 64)
            button.add_child(inner)
        button.pressed.connect(_choose.bind(move))
        row.add_child(button)
    _layer.add_child(row)
    row.position = center - Vector2(row.get_combined_minimum_size().x / 2, 0)


func _label(text: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


# --- Hand and game summary -------------------------------------------------------

func _show_summary(hand_end: Dictionary) -> void:
    _close_overlay()
    var result: Dictionary = hand_end.result
    var panel := PanelContainer.new()
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    panel.add_child(column)
    var mine := _me % 2
    var taker_team := int(hand_end.taker) % 2
    var outcome: String = result.outcome
    var title: String = {"fait": "Contrat rempli", "dedans": "Dedans !", "litige": "Litige"}[outcome]
    var good: bool = (outcome == "fait") == (taker_team == mine)
    if hand_end.game_over:
        column.add_child(_label("Vous gagnez la partie !" if hand_end.winner == mine else "Vous perdez la partie",
                34, TableTheme.GREEN if hand_end.winner == mine else TableTheme.RED))
    column.add_child(_label(title, 30, TableTheme.INK if outcome == "litige"
            else (TableTheme.GREEN if good else TableTheme.RED)))
    var taken := HBoxContainer.new()
    taken.add_theme_constant_override("separation", 8)
    taken.add_child(_label("Pris par %s à" % _name(hand_end.taker), 20, TableTheme.INK.lightened(0.25)))
    var icon := SuitIcon.new()
    icon.suit = hand_end.trump
    icon.custom_minimum_size = Vector2(24, 24)
    taken.add_child(icon)
    column.add_child(taken)
    column.add_child(HSeparator.new())
    var grid := GridContainer.new()
    grid.columns = 3
    grid.add_theme_constant_override("h_separation", 48)
    grid.add_theme_constant_override("v_separation", 6)
    var rows := [["", "Nous", "Eux"],
            ["Annonces"] + _team_points(result.announces),
            ["Belote"] + _team_points(result.belote),
            ["Points"] + _team_points(result.raw),
            ["Marqués"] + _team_points(result.points),
            ["Total"] + _team_points(hand_end.scores)]
    for r in rows.size():
        for cell in rows[r]:
            var bold: bool = r == 0 or r == rows.size() - 1
            grid.add_child(_label(str(cell), 24 if bold else 22, TableTheme.INK))
    column.add_child(grid)
    var buttons := HBoxContainer.new()
    buttons.add_theme_constant_override("separation", 16)
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    if hand_end.game_over:
        buttons.add_child(_button("Menu", func() -> void: left.emit()))
    else:
        buttons.add_child(_button("Continuer", func() -> void:
                _close_overlay()
                continued.emit()))
    column.add_child(buttons)
    _overlay = panel
    add_child(panel)
    panel.position = (size - panel.get_combined_minimum_size()) / 2
    panel.pivot_offset = panel.get_combined_minimum_size() / 2
    panel.scale = Vector2.ONE * 0.85
    panel.modulate.a = 0.0
    var tween := panel.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tween.tween_property(panel, "scale", Vector2.ONE, 0.3)
    tween.tween_property(panel, "modulate:a", 1.0, 0.2)


func _button(text: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(200, 64)
    button.pressed.connect(action)
    return button


func _close_overlay() -> void:
    if _overlay != null:
        _overlay.queue_free()
        _overlay = null
