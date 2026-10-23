extends SceneTree
## Renders a screen for a moment and saves a screenshot, to check layouts without the editor:
##     godot --path . --resolution 64x64 -s res://tools/screenshot.gd -- out.png [setup] [width]
## setup: home, lobby, bidding, playing (default), announces, last_trick, summary. width defaults to 1600
## (a 20:9 phone at 720p).
##
## Godot only renders while a window can draw (not headless, not minimized), so the window is
## shrunk, made unfocusable and pushed off-screen, and the game renders into a SubViewport.


func _initialize() -> void:
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
    DisplayServer.window_set_size(Vector2i.ONE)
    DisplayServer.window_set_position(Vector2i(-32000, -32000))
    var args := OS.get_cmdline_user_args()
    var output := args[0] if args.size() > 0 else "user://screenshot.png"
    var setup: String = args[1] if args.size() > 1 else "playing"
    var width := int(args[2]) if args.size() > 2 else 1600
    # The project stretch settings would scale the SubViewport with the tiny window.
    root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
    var viewport := SubViewport.new()
    viewport.size = Vector2i(width, 720)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    if setup == "home":
        viewport.add_child(load("res://ui/main.tscn").instantiate())
    elif setup == "lobby":
        # A host's lobby with one friend seated, shown without Tube (no network here).
        var lobby: Control = load("res://ui/lobby.tscn").instantiate()
        lobby.preview = {"state": 2, "code": "K7QXPA", "my_seat": 0, "info": {"started": false, "seats": [
                {"name": "Benjamin", "human": true, "here": true},
                {"name": "", "human": false, "here": false},
                {"name": "Alice", "human": true, "here": true},
                {"name": "", "human": false, "here": false}]}}
        viewport.add_child(lobby)
    else:
        var table: Control = load("res://ui/table.tscn").instantiate()
        viewport.add_child(table)
        await process_frame  # nodes added in _initialize only get _ready() once the tree runs
        await create_timer(0.8).timeout
        var host: TableHost = table.host
        host.auto_bots = false
        host.start(4)
        var state := host.state
        host.bot.take_threshold = 0  # someone always takes, quickly
        match setup:
            "bidding":
                host.bot.take_threshold = 999
                host.bot.take_threshold_second = 999
                _fast_forward(host, func() -> bool: return state.to_act == 0)
                host.resend()
            "playing":
                _fast_forward(host, func() -> bool: return state.played.size() >= 6 and state.to_act == 0)
                host.resend()
            "announces":
                # The first seed whose second trick shows announces, with us to play.
                for seed_value in 200:
                    host.start(seed_value)
                    state = host.state
                    _fast_forward(host, func() -> bool: return state.played.size() >= 5 or state.deal_number > 0)
                    if state.announce_team >= 0 and state.deal_number == 0:
                        break
                host.resend()
            "last_trick", "summary":
                # Everything but the hand's last card without the screen, then the last card through it.
                _fast_forward(host, func() -> bool: return state.played.size() == 31)
                host.resend()
                await create_timer(0.8).timeout

                host.submit(state.to_act, host.bot.choose(host.game.view_for(state, state.to_act)))
                await create_timer(0.5 if setup == "last_trick" else 3.8).timeout
    await create_timer(1.2).timeout  # let the deal and play animations land
    viewport.get_texture().get_image().save_png(output)
    quit()


## Plays every seat with the bot straight on the state, without packets, until `done` holds.
func _fast_forward(host: TableHost, done: Callable) -> void:
    while not done.call():
        host.game.apply(host.state, host.bot.choose(host.game.view_for(host.state, host.state.to_act)))
