extends GutTest
## A host and two guests in one process, each under its own multiplayer root, joined
## by in-memory LoopbackPeers (no socket: this PC has no network rights). The link
## only sees Godot's multiplayer API, so these are the same RPCs as over Tube.

var host_api: SceneMultiplayer
var roots: Array[Node] = []
var links: Array[TableLink] = []
var peers: Array[LoopbackPeer] = []
## Per link: every packet its screen received.
var inboxes: Array = []


func before_each() -> void:
    roots.clear()
    links.clear()
    peers.clear()
    inboxes.clear()
    var hub := LoopbackPeer.host()
    for i in 3:
        var root := Node.new()
        root.name = "Peer%d" % i
        add_child(root)
        var link := TableLink.new()
        link.name = "Link"
        root.add_child(link)
        var api := SceneMultiplayer.new()
        get_tree().set_multiplayer(api, root.get_path())
        var peer: LoopbackPeer = hub if i == 0 else hub.add_client(i + 1)
        api.multiplayer_peer = peer
        roots.append(root)
        links.append(link)
        peers.append(peer)
        var inbox := []
        inboxes.append(inbox)
        link.packet_received.connect(func(data: Dictionary) -> void: inbox.append(data))
    host_api = get_tree().get_multiplayer(roots[0].get_path())
    await wait_until(func() -> bool: return host_api.get_peers().size() == 2, 5.0)


func after_each() -> void:
    for i in roots.size():
        peers[i].close()
        get_tree().set_multiplayer(null, roots[i].get_path())
        roots[i].queue_free()


func _gather() -> void:
    links[0].open("Hôte")
    links[1].join("Alice")
    await wait_until(func() -> bool: return links[0].info.get("people", []).size() == 2, 5.0)
    links[2].join("Bob")
    await wait_until(_everyone_listed, 5.0)


func _everyone_listed() -> bool:
    var people: Array = links[2].info.get("people", [])
    return people.size() == 3 and people[2].name == "Bob"


## Plays like the screens: answer our turn and close the summaries; true at the end.
func _play_all(bot_for: Callable) -> bool:
    for i in 3:
        var inbox: Array = inboxes[i]
        while not inbox.is_empty():
            var data: Dictionary = inbox.pop_front()
            var view: Dictionary = data.view
            assert_false(view.has("hands"), "nobody receives the other hands")
            assert_eq(view.seat, links[i].my_seat)
            if data.event.has("hand_end"):
                links[i].continue_hand()
                if data.event.hand_end.game_over:
                    continue
            if view.to_act == view.seat and not view.legal.is_empty():
                links[i].submit(bot_for.call().choose(view))
    return links[0].host.game.is_over(links[0].host.state)


func test_people_gather_in_the_lobby_in_order() -> void:
    await _gather()
    var people: Array = links[0].info.people
    assert_eq(people.map(func(p: Dictionary) -> String: return p.name), ["Hôte", "Alice", "Bob"])
    assert_eq(links[2].info.game, "belote")
    assert_true(links[0].can_start())


func test_belote_seats_put_the_first_friend_opposite() -> void:
    await _gather()
    links[0].start_game(5)
    await wait_until(func() -> bool: return links[1].my_seat == 2 and links[2].my_seat == 1, 5.0)
    assert_eq(links[0].host.names[2], "Alice")
    assert_eq(links[0].host.names[1], "Bob")
    assert_false(links[0].host.humans[3], "the free seat is a bot")


func test_a_whole_online_belote_game() -> void:
    await _gather()
    for link in links:
        link.screen_attached()
    links[0].start_game(5)
    links[0].host.bot_delay = 0.0
    links[0].host.trick_pause = 0.0
    await wait_until(func() -> bool: return links[2].my_seat == 1, 5.0)
    await wait_until(func() -> bool: return _play_all(func() -> BeloteBot: return BeloteBot.new()), 60.0)
    assert_true(links[0].host.game.is_over(links[0].host.state))
    assert_true(links[1].game_over, "guests saw the end")


func test_a_whole_online_tarot_game_at_three() -> void:
    await _gather()
    links[0].set_game("tarot3")
    await wait_until(func() -> bool: return links[2].info.get("game", "") == "tarot3", 5.0)
    for link in links:
        link.screen_attached()
    links[0].start_game(9)
    links[0].host.bot_delay = 0.0
    links[0].host.trick_pause = 0.0
    await wait_until(func() -> bool: return links[2].my_seat == 2 and links[2].game_id == "tarot3", 5.0)
    assert_true(links[0].host is TarotHost)
    await wait_until(func() -> bool: return _play_all(func() -> TarotBot: return TarotBot.new()), 120.0)
    assert_true(links[0].host.game.is_over(links[0].host.state))
    # Back to the lobby, for another game.
    links[0].back_to_lobby()
    await wait_until(func() -> bool: return not links[1].info.get("started", true), 5.0)
    assert_null(links[0].host)


func test_a_guest_who_drops_is_replaced_by_a_bot_then_gets_the_seat_back() -> void:
    await _gather()
    for link in links:
        link.screen_attached()
    links[0].start_game(5)
    await wait_until(func() -> bool: return links[2].my_seat == 1, 5.0)
    peers[2].close()
    await wait_until(func() -> bool: return not links[0].host.humans[1], 5.0)
    assert_false(links[0].info.people[2].here)
    # Bob comes back on a new connection, under the same name.
    var api := get_tree().get_multiplayer(roots[2].get_path()) as SceneMultiplayer
    peers[2] = peers[0].add_client(9)
    api.multiplayer_peer = peers[2]
    await wait_until(func() -> bool: return host_api.get_peers().has(9), 5.0)
    links[2].join("Bob")
    await wait_until(func() -> bool: return links[0].host.humans[1], 5.0)
    assert_eq(links[2].my_seat, 1)
    await wait_until(func() -> bool: return inboxes[2].any(_is_start), 5.0)
    assert_true(inboxes[2].any(_is_start), "the table is sent again")


func test_too_many_people_for_the_game_cannot_start() -> void:
    await _gather()
    links[0].set_game("tarot3")
    assert_true(links[0].can_start(), "three people, three seats")
    links[0]._people.append({"name": "Zoé", "peer": 77})
    assert_false(links[0].can_start())
    assert_false(links[0].start_game())


func _is_start(data: Dictionary) -> bool:
    return data.event.kind == "start"
