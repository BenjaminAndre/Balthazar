extends SceneTree
## Renders a screen for a moment and saves a screenshot, to check layouts without the editor:
##     godot --path . --resolution 64x64 -s res://tools/screenshot.gd -- out.png [setup] [width]
## setup: home, bidding, playing (default), summary. width defaults to 1600 (a 20:9 phone at 720p).
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
    else:
        var table: Control = load("res://ui/table.tscn").instantiate()
        viewport.add_child(table)
        await process_frame  # nodes added in _initialize only get _ready() once the tree runs
        table.bot.take_threshold = 0  # someone always takes, quickly
        table.new_game(4)
        match setup:
            "playing":
                _play_until(table, func() -> bool: return table.state.played.size() >= 6 \
                        and table.state.to_act == 0)
            "bidding":
                table.bot.take_threshold = 999
                table.bot.take_threshold_second = 999
                _play_until(table, func() -> bool: return table.state.to_act == 0)
            "summary":
                _play_until(table, func() -> bool: return table.state.deal_number > 0)
                table._show_summary()
        table._refresh()
    await create_timer(1.2).timeout  # let the deal and play animations land
    viewport.get_texture().get_image().save_png(output)
    quit()


## Plays every seat with the bot, without delays, until `done` holds.
func _play_until(table: Control, done: Callable) -> void:
    var state: BeloteState = table.state
    while not done.call():
        table._scored = {"taker": state.taker, "trump": state.trump}
        table.game.apply(state, table.bot.choose(table.game.view_for(state, state.to_act)))
