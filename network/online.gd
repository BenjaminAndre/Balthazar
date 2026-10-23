extends Node
## Autoload: online tables over Tube (WebRTC peer to peer; sessions found by code
## through public WebTorrent trackers, GDD §2). It holds the TubeClient and the
## TableLink, so both survive scene changes between the lobby and the table.
## The TubeClient is only created on demand, because it takes over the
## multiplayer API of this node's branch.

signal changed

enum State { OFFLINE, CREATING, HOSTING, JOINING, JOINED }

## Readable when spoken or typed: no O/0, I/1.
const CODE_CHARACTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const APP_ID := "Balthazar-Bel0te"
const TRACKERS: Array[String] = ["wss://tracker.androodev.com", "wss://tracker.openwebtorrent.com",
        "wss://tracker.files.fm:7073/announce", "wss://tracker.btorrent.xyz/"]
const STUN_SERVERS: Array[String] = ["stun:stun.l.google.com:19302", "stun:stun.cloudflare.com:3478"]

var state := State.OFFLINE
## The table's code, to share with friends.
var code := ""
## The last problem, in French, for the screens.
var error := ""
var link: TableLink

var _tube: TubeClient
var _name := ""


func _ready() -> void:
    link = TableLink.new()
    link.name = "Link"
    add_child(link)
    link.failed.connect(func(reason: String) -> void:
        leave()
        error = reason
        changed.emit())
    link.lobby_changed.connect(func(_info: Dictionary) -> void: changed.emit())


func host_table(player_name: String) -> void:
    _ensure_tube()
    leave()
    _name = player_name
    error = ""
    state = State.CREATING
    _tube.create_session()
    changed.emit()


func join_table(table_code: String, player_name: String) -> void:
    _ensure_tube()
    leave()
    _name = player_name
    error = ""
    code = table_code.strip_edges().to_upper()
    state = State.JOINING
    _tube.join_session(code)
    changed.emit()


func leave() -> void:
    if _tube and _tube.state != TubeClient.State.IDLE:
        _tube.leave_session()
    link.screen_detached()
    if link.host:
        link.host.queue_free()
        link.host = null
    link.info = {}
    link.my_seat = -1
    link.game_over = false
    state = State.OFFLINE
    changed.emit()


func is_online() -> bool:
    return state == State.HOSTING or state == State.JOINED


## Wires the table screen to the online table.
func attach_table(table: Node) -> void:
    link.packet_received.connect(table.receive)
    table.move_chosen.connect(link.submit)
    table.continued.connect(link.continue_hand)
    table.left.connect(func() -> void:
        link.packet_received.disconnect(table.receive)
        link.screen_detached()
        if link.game_over and is_online():
            # The game is over: back to the lobby, still together, maybe for another game.
            if link.is_host():
                link.back_to_lobby()
            table.get_tree().change_scene_to_file("res://ui/lobby.tscn")
        else:
            leave()
            table.get_tree().change_scene_to_file("res://ui/main.tscn"))
    link.screen_attached()


func _ensure_tube() -> void:
    if _tube:
        return
    var context := TubeContext.new()
    context.app_id = APP_ID
    context.session_id_characters_set = CODE_CHARACTERS
    context.trackers_urls = TRACKERS
    context.stun_servers_urls = STUN_SERVERS
    _tube = TubeClient.new()
    _tube.context = context
    _tube.multiplayer_root_node = self
    add_child(_tube)
    _tube.session_created.connect(_on_session_created)
    _tube.session_joined.connect(_on_session_joined)
    _tube.peer_disconnected.connect(_on_peer_disconnected)
    _tube.session_left.connect(_on_session_left)
    _tube.error_raised.connect(_on_error)


func _on_session_created() -> void:
    code = _tube.session_id
    state = State.HOSTING
    link.open(_name)
    changed.emit()


func _on_session_joined() -> void:
    state = State.JOINED
    link.join(_name)
    changed.emit()


func _on_peer_disconnected(peer_id: int) -> void:
    if state == State.JOINED and peer_id == 1:
        _lost("L'hôte a quitté la table")


func _on_session_left() -> void:
    if state == State.JOINED:
        _lost("Connexion perdue")


## The connection to the host is gone. Joining again with the same code and name
## gives the seat back.
func _lost(reason: String) -> void:
    leave()
    error = reason + " : rejoignez avec le même code et le même pseudo."
    changed.emit()


## Signaling errors only stop new players from joining; a running table stays open.
func _on_error(error_code: int, message: String) -> void:
    if error_code == TubeClient.SessionError.CREATE_SESSION_FAILED:
        leave()
        error = "Impossible de créer la table (%s)" % message
    elif error_code == TubeClient.SessionError.JOIN_SESSION_FAILED:
        leave()
        error = "Table introuvable : vérifiez le code"
    else:
        error = message
    changed.emit()
