class_name TableLink
extends Node
## The RPCs of an online table (GDD §2), over Godot's multiplayer API: Tube in the
## app, an in-memory LoopbackPeer in tests.
##
## A table is first a lobby: the host (peer 1) and the friends who joined, in the
## order they came. The host picks the game (GameCatalog.GAMES) and its settings,
## then starts: the people get seats (at the Belote, the first friend sits
## opposite the host), bots take the free seats, and a TableHost or TarotHost
## runs the game. Each guest only ever receives its own seat's packets. After
## the game, everyone comes back to the lobby, possibly for another game.
##
## A guest who drops keeps their seat: a bot plays it until they join again under
## the same name.

## The lobby for the screens: {people: [{name, here}], game, players, started,
## seats (person per seat, while started), bots, settings}.
signal lobby_changed(info: Dictionary)
## The host launched a game: open its table screen.
signal started
## A packet for this player's screen.
signal packet_received(data: Dictionary)
## The table refused us, or is gone.
signal failed(reason: String)

const MAX_PEOPLE := 5
## Belote seats for the people in joining order: host, then opposite, left, right.
const BELOTE_SEATS := [0, 2, 1, 3]

## Host only: the running game (TableHost or TarotHost), or null in the lobby.
var host: Node
var my_seat := -1
## The game being played (or chosen), e.g. "belote", "tarot4".
var game_id := "belote"
var info: Dictionary = {}
## True once this player's screen has seen the end of the game.
var game_over := false

## Host only: the people, {name, peer (0 = gone)}; index 0 is the host.
var _people: Array = []
## Host only, while started: for each seat, the index of its person, or -1 (bot).
var _seat_people: Array = []
var _started := false
var _bot_level := "difficile"
var _settings: Dictionary = {}
var _pending: Array[Dictionary] = []
var _screen_ready := false


func is_host() -> bool:
    return multiplayer.is_server()


## Host: opens the lobby with us alone in it, our profile's settings and bot level.
func open(my_name: String) -> void:
    _started = false
    _people = [{"name": my_name, "peer": 1}]
    _seat_people = []
    my_seat = 0
    game_id = "belote"
    _bot_level = Session.bot_level
    _settings = TableSettings.load_profile()
    _free_host()
    if not multiplayer.peer_disconnected.is_connected(_on_peer_left):
        multiplayer.peer_disconnected.connect(_on_peer_left)
    _publish()


## Guest: once connected, ask the host for a place.
func join(my_name: String) -> void:
    _hello.rpc_id(1, my_name)


func players() -> int:
    return int(game_id.right(1)) if game_id.right(1).is_valid_int() else 4


## Host: whether the chosen game has a seat for everyone here.
func can_start() -> bool:
    return _here_count() <= players()


func set_game(id: String) -> void:
    game_id = id
    _publish()


func set_bot_level(level: String) -> void:
    _bot_level = level
    _publish()


func set_setting(group: String, key: String, setting_value: Variant) -> void:
    var settings := _settings.duplicate(true)
    settings[group][key] = setting_value
    _settings = TableSettings.complete(settings)
    _publish()


## Host: seats everyone, starts the chosen game, and sends the guests to it.
func start_game(seed_value := -1) -> bool:
    if not can_start():
        return false
    var count := players()
    _seat_people = []
    for seat in count:
        _seat_people.append(-1)
    var order: Array = BELOTE_SEATS if game_id == "belote" else range(count)
    var next := 0
    for person in _people.size():
        if _people[person].peer == 0:
            continue
        _seat_people[order[next]] = person
        next += 1
    _free_host()
    # Hosts are loaded on demand: naming their classes here (the Online autoload loads
    # this script) made Godot leak at exit.
    if game_id == "belote":
        host = load("res://table/table_host.gd").new()
        host.set_bot_level(_bot_level)
    else:
        host = load("res://table/tarot_host.gd").new(count)
    host.settings = _settings.duplicate(true)
    for seat in count:
        var person: int = _seat_people[seat]
        host.humans[seat] = person >= 0
        host.names[seat] = _people[person].name if person >= 0 else ""
    add_child(host)
    host.packet.connect(_on_host_packet)
    _started = true
    game_over = false
    for seat in count:
        var person: int = _seat_people[seat]
        if person > 0:
            _started_rpc.rpc_id(_people[person].peer, seat, game_id)
    _publish()
    started.emit()
    host.start(seed_value)
    return true


## Host: back to the lobby after a game (the guests come back on their own).
func back_to_lobby() -> void:
    _started = false
    _seat_people = []
    _free_host()
    _publish()


func screen_attached() -> void:
    _screen_ready = true
    var pending := _pending.duplicate()
    _pending.clear()
    for data in pending:
        _deliver(data)


func screen_detached() -> void:
    _screen_ready = false


func submit(move: Dictionary) -> void:
    if is_host():
        if host:
            host.submit(0, move)
    else:
        _submit.rpc_id(1, move)


func continue_hand() -> void:
    if is_host():
        if host:
            host.continue_from(0)
    else:
        _continue.rpc_id(1)


func _free_host() -> void:
    if host:
        host.queue_free()
        host = null


func _here_count() -> int:
    var count := 0
    for person in _people:
        if person.peer != 0:
            count += 1
    return count


# --- Host side -------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _hello(guest_name: String) -> void:
    if not is_host():
        return
    var peer := multiplayer.get_remote_sender_id()
    # A returning name gets its place (and seat) back.
    var person := -1
    for i in range(1, _people.size()):
        if _people[i].name == guest_name and _people[i].peer == 0 and guest_name != "":
            person = i
    if person < 0:
        if _here_count() >= MAX_PEOPLE or (_started and not _seat_people.has(-1)):
            _refused.rpc_id(peer, "La table est complète")
            return
        _people.append({"name": guest_name, "peer": peer})
        person = _people.size() - 1
        if _started:
            # A newcomer during a game takes over a bot's seat.
            _seat_people[_seat_people.find(-1)] = person
    _people[person].peer = peer
    if _started:
        var seat: int = _seat_people.find(person)
        if seat >= 0:
            host.names[seat] = guest_name
            _started_rpc.rpc_id(peer, seat, game_id)
            host.set_human(seat, true)
            host.resend(seat)
    _publish()


@rpc("any_peer", "call_remote", "reliable")
func _submit(move: Dictionary) -> void:
    var seat := _seat_of(multiplayer.get_remote_sender_id())
    if seat > 0 and host:
        host.submit(seat, move)


@rpc("any_peer", "call_remote", "reliable")
func _continue() -> void:
    var seat := _seat_of(multiplayer.get_remote_sender_id())
    if seat > 0 and host:
        host.continue_from(seat)


func _seat_of(peer: int) -> int:
    for seat in _seat_people.size():
        var person: int = _seat_people[seat]
        if person >= 0 and _people[person].peer == peer:
            return seat
    return -1


func _on_peer_left(peer: int) -> void:
    var person := -1
    for i in range(1, _people.size()):
        if _people[i].peer == peer:
            person = i
    if person < 0:
        return
    if _started and _seat_people.has(person):
        # Their seat waits for them; a bot plays it meanwhile.
        _people[person].peer = 0
        host.set_human(_seat_people.find(person), false)
    else:
        _people.remove_at(person)
        for seat in _seat_people.size():
            if _seat_people[seat] > person:
                _seat_people[seat] -= 1
    _publish()


func _on_host_packet(seat: int, data: Dictionary) -> void:
    if seat == my_seat:
        _deliver(data)
        return
    var person: int = _seat_people[seat] if seat < _seat_people.size() else -1
    if person >= 0 and _people[person].peer != 0:
        _packet.rpc_id(_people[person].peer, data)


func _publish() -> void:
    var people := []
    for person in _people:
        people.append({"name": person.name, "here": person.peer != 0})
    info = {"people": people, "game": game_id, "players": players(), "started": _started,
            "seats": _seat_people.duplicate(), "bots": _bot_level, "settings": _settings,
            "can_start": can_start()}
    _lobby.rpc(info)
    lobby_changed.emit(info)


# --- Guest side ------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _lobby(lobby: Dictionary) -> void:
    info = lobby
    game_id = lobby.get("game", game_id)
    lobby_changed.emit(lobby)


@rpc("authority", "call_remote", "reliable")
func _started_rpc(seat: int, game: String) -> void:
    my_seat = seat
    game_id = game
    _started = true
    game_over = false
    started.emit()


@rpc("authority", "call_remote", "reliable")
func _packet(data: Dictionary) -> void:
    _deliver(data)


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
    failed.emit(reason)


func _deliver(data: Dictionary) -> void:
    if not _screen_ready:
        _pending.append(data)
        return
    var hand_end: Dictionary = data.event.get("hand_end", {})
    if hand_end.get("game_over", false):
        game_over = true
    packet_received.emit(data)
