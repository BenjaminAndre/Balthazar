extends GutTest
## The relay's answer, read as Tube needs it: its TURN entries only, since the STUN ones
## are already in the context. The request itself is not run here: it would open a socket.

const ANSWER := '{"iceServers": [{"urls": ["stun:stun.example.com:3478"]}, ' \
        + '{"urls": ["turns:turn.example.com:5349"], "username": "u", "credential": "c"}]}'


func test_keeps_only_the_turn_entries() -> void:
    var servers := Online.turn_servers_from(ANSWER.to_utf8_buffer())
    assert_eq(servers.size(), 1)
    assert_eq(servers[0]["username"], "u")
    assert_eq(servers[0]["credential"], "c")


func test_a_string_url_is_read_too() -> void:
    var answer := '{"iceServers": [{"urls": "turn:turn.example.com:3478", "username": "u", "credential": "c"}]}'
    assert_eq(Online.turn_servers_from(answer.to_utf8_buffer()).size(), 1)


## Leaving while the relay is asked must drop the pending create or join.
func test_leaving_while_asking_starts_nothing() -> void:
    var started := [false]
    Online._start_when_ready = func() -> void: started[0] = true
    Online.leave()
    Online._start_now()
    assert_false(started[0])


func test_a_bad_answer_gives_no_relay() -> void:
    assert_eq(Online.turn_servers_from("pas du JSON".to_utf8_buffer()).size(), 0)
    assert_eq(Online.turn_servers_from("{}".to_utf8_buffer()).size(), 0)
    assert_eq(Online.turn_servers_from('{"iceServers": "non"}'.to_utf8_buffer()).size(), 0)
