class_name TableLink
extends Node
## The RPCs of an online table (GDD §2), over Godot's multiplayer API: Tube in the
## app, an in-memory LoopbackPeer in tests. The host (peer 1) owns a TableHost and
## sits in seat 0; guests say hello with their name and get a seat (partner first).
## Each guest only ever receives its own seat's packets.
##
## A guest who drops keeps their seat: a bot plays it until they join again under
## the same name.

## Seats, names and who is there, for the lobby screen: {seats: [{name, human, here}], started}.
signal lobby_changed(info: Dictionary)
## The host launched the game: open the table screen.
signal started
## A packet for this player's screen (see TableHost).
signal packet_received(data: Dictionary)
## The table refused us, or is gone.
signal failed(reason: String)

const FILL_ORDER := [2, 1, 3]

## Host only: the game.
var host: TableHost
var my_seat := -1
var info: Dictionary = {}

## Host only: per seat, {name, peer (0 = gone), human}.
var _seats: Array = []
var _started := false
## Packets that arrived before a screen was listening.
var _pending: Array[Dictionary] = []
var _screen_ready := false


func is_host() -> bool:
    return multiplayer.is_server()


## Host: opens a table with us in seat 0 and bots elsewhere.
func open(my_name: String) -> void:
    _started = false
    _seats = []
    for seat in 4:
        _seats.append({"name": "", "peer": 0, "human": false})
    _seats[0] = {"name": my_name, "peer": 1, "human": true}
    my_seat = 0
    if host:
        host.queue_free()
    host = TableHost.new()
    add_child(host)
    host.packet.connect(_on_host_packet)
    host.set_bot_level(Session.bot_level)
    # The host's profile settings come with it; it may change them in the lobby.
    host.settings = TableSettings.load_profile()
    if not multiplayer.peer_disconnected.is_connected(_on_peer_left):
        multiplayer.peer_disconnected.connect(_on_peer_left)
    _publish()


## Guest: once connected, ask the host for a seat.
func join(my_name: String) -> void:
    _hello.rpc_id(1, my_name)


## Host: launches the game with whoever is seated.
func start_game(seed_value := -1) -> void:
    _started = true
    for seat in 4:
        host.humans[seat] = _seats[seat].human and _seats[seat].peer != 0
        host.names[seat] = _seats[seat].name
    for seat in 4:
        if seat != 0 and _seats[seat].peer != 0:
            _started_rpc.rpc_id(_seats[seat].peer, seat)
    _publish()
    started.emit()
    host.start(seed_value)


## A screen is listening: hand it what came before.
func screen_attached() -> void:
    _screen_ready = true
    var pending := _pending.duplicate()
    _pending.clear()
    for data in pending:
        packet_received.emit(data)


func screen_detached() -> void:
    _screen_ready = false


func submit(move: Dictionary) -> void:
    if is_host():
        host.submit(0, move)
    else:
        _submit.rpc_id(1, move)


func continue_hand() -> void:
    if is_host():
        host.continue_from(0)
    else:
        _continue.rpc_id(1)


# --- Host side -------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _hello(guest_name: String) -> void:
    if not is_host():
        return
    var peer := multiplayer.get_remote_sender_id()
    var seat := _seat_for(guest_name)
    if seat < 0:
        _refused.rpc_id(peer, "La table est complète")
        return
    _seats[seat] = {"name": guest_name, "peer": peer, "human": true}
    if _started:
        # Back in their seat: the bot hands it over.
        host.names[seat] = guest_name
        _started_rpc.rpc_id(peer, seat)
        host.set_human(seat, true)
        host.resend(seat)
    _publish()


## A returning name gets its seat back; otherwise the first free seat, partner first.
func _seat_for(guest_name: String) -> int:
    for seat in 4:
        if seat != 0 and _seats[seat].name == guest_name and _seats[seat].peer == 0 and guest_name != "":
            return seat
    for seat in FILL_ORDER:
        if _seats[seat].peer == 0 and (not _started or _seats[seat].name == ""):
            return seat
    return -1


@rpc("any_peer", "call_remote", "reliable")
func _submit(move: Dictionary) -> void:
    var seat := _seat_of(multiplayer.get_remote_sender_id())
    if seat > 0:
        host.submit(seat, move)


@rpc("any_peer", "call_remote", "reliable")
func _continue() -> void:
    var seat := _seat_of(multiplayer.get_remote_sender_id())
    if seat > 0:
        host.continue_from(seat)


func _seat_of(peer: int) -> int:
    for seat in 4:
        if _seats[seat].peer == peer:
            return seat
    return -1


func _on_peer_left(peer: int) -> void:
    var seat := _seat_of(peer)
    if seat <= 0:
        return
    _seats[seat].peer = 0
    if _started:
        host.set_human(seat, false)
    else:
        _seats[seat] = {"name": "", "peer": 0, "human": false}
    _publish()


func _on_host_packet(seat: int, data: Dictionary) -> void:
    if seat == my_seat:
        _deliver(data)
    elif _seats[seat].peer != 0:
        _packet.rpc_id(_seats[seat].peer, data)


func _publish() -> void:
    var seats := []
    for seat in 4:
        seats.append({"name": _seats[seat].name, "human": _seats[seat].human,
                "here": _seats[seat].peer != 0})
    info = {"seats": seats, "started": _started, "bots": host.bot_level, "settings": host.settings}
    _lobby.rpc(info)
    lobby_changed.emit(info)


# --- Guest side ------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _lobby(lobby: Dictionary) -> void:
    info = lobby
    lobby_changed.emit(lobby)


@rpc("authority", "call_remote", "reliable")
func _started_rpc(seat: int) -> void:
    my_seat = seat
    _started = true
    started.emit()


@rpc("authority", "call_remote", "reliable")
func _packet(data: Dictionary) -> void:
    _deliver(data)


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
    failed.emit(reason)


func _deliver(data: Dictionary) -> void:
    if _screen_ready:
        packet_received.emit(data)
    else:
        _pending.append(data)


## Host: which bots play the free seats; guests see it in the lobby.
func set_bot_level(level: String) -> void:
    host.set_bot_level(level)
    _publish()


## Host: changes one table setting; guests see it in the lobby.
func set_setting(group: String, key: String, setting_value: Variant) -> void:
    var settings := host.settings.duplicate(true)
    settings[group][key] = setting_value
    host.settings = TableSettings.complete(settings)
    _publish()
