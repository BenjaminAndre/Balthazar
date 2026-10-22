class_name LoopbackPeer
extends MultiplayerPeerExtension
## In-memory MultiplayerPeers for tests: a host (id 1) and its clients, in a star like WebRTC's
## server mode, exchanging packets through queues with no socket, port or network permission
## involved. Packets are delivered in order on the receiver's next poll, like a reliable ordered
## channel. Peers can leave (close) and new clients can join, to test late joins, rejoins and a
## new host taking over.

const HOST_ID := 1

var _id: int
## Host: client id -> client. Client: {1: its host}.
var _links := {}
## Each packet is [from, bytes, channel, mode]. The front one is the "current" packet.
var _inbox: Array = []
var _target := 0
var _channel := 0
var _mode := TRANSFER_MODE_RELIABLE
var _status := CONNECTION_DISCONNECTED
## Peers to announce as connected, and as gone, on the next poll.
var _arriving: Array[int] = []
var _leaving: Array[int] = []


## A host, with no client yet.
static func host() -> LoopbackPeer:
    var peer := LoopbackPeer.new()
    peer._id = HOST_ID
    peer._status = CONNECTION_CONNECTED
    return peer


## A host and a client, already paired. They connect on their first poll.
static func pair(client_id := 2) -> Array[LoopbackPeer]:
    var peer := host()
    return [peer, peer.add_client(client_id)]


## A new client of this host: each sees the other connected on its next poll.
func add_client(client_id: int) -> LoopbackPeer:
    var client := LoopbackPeer.new()
    client._id = client_id
    client._status = CONNECTION_CONNECTING
    client._links[HOST_ID] = self
    client._arriving.append(HOST_ID)
    _links[client_id] = client
    _arriving.append(client_id)
    return client


func _poll() -> void:
    if _status == CONNECTION_CONNECTING:
        _status = CONNECTION_CONNECTED
    for id in _arriving:
        peer_connected.emit(id)
    _arriving.clear()
    for id in _leaving:
        peer_disconnected.emit(id)
    _leaving.clear()
    # A client that lost its host is disconnected.
    if _id != HOST_ID and _links.is_empty() and _status == CONNECTION_CONNECTED:
        _status = CONNECTION_DISCONNECTED


func _put_packet_script(buffer: PackedByteArray) -> Error:
    if _status != CONNECTION_CONNECTED:
        return ERR_UNCONFIGURED
    for id: int in _links:
        if _target == 0 or _target == id or (_target < 0 and -_target != id):
            (_links[id] as LoopbackPeer)._inbox.append([_id, buffer, _channel, _mode])
    return OK


## Someone this peer was linked to has gone: announced on the next poll.
func _lose(id: int) -> void:
    if not _links.has(id):
        return
    _links.erase(id)
    _leaving.append(id)


func _get_available_packet_count() -> int:
    return _inbox.size()


func _get_packet_script() -> PackedByteArray:
    return _inbox.pop_front()[1]


func _get_packet_peer() -> int:
    return _inbox[0][0]


func _get_packet_channel() -> int:
    return _inbox[0][2]


func _get_packet_mode() -> TransferMode:
    return _inbox[0][3]


func _set_target_peer(peer: int) -> void:
    _target = peer


func _set_transfer_channel(channel: int) -> void:
    _channel = channel


func _get_transfer_channel() -> int:
    return _channel


func _set_transfer_mode(mode: TransferMode) -> void:
    _mode = mode


func _get_transfer_mode() -> TransferMode:
    return _mode


func _get_max_packet_size() -> int:
    return 1 << 24


func _get_unique_id() -> int:
    return _id


func _is_server() -> bool:
    return _id == HOST_ID


func _is_server_relay_supported() -> bool:
    return false


func _get_connection_status() -> ConnectionStatus:
    return _status


func _disconnect_peer(peer: int, _force: bool) -> void:
    if _links.has(peer):
        (_links[peer] as LoopbackPeer)._lose(_id)
        _lose(peer)


## This peer leaves: everyone it was linked to sees it gone.
func _close() -> void:
    if _status == CONNECTION_DISCONNECTED:
        return
    _status = CONNECTION_DISCONNECTED
    _inbox.clear()
    for id: int in _links:
        (_links[id] as LoopbackPeer)._lose(_id)
    _links.clear()
