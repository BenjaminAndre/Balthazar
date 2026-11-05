extends SceneTree
## Measures the cost of a table screen, off-screen like tools/screenshot.gd:
##     godot --path . --resolution 64x64 -s res://tools/bench.gd -- [tarot5|belote] [width]
## Prints the draw calls per frame, the average frame time (uncapped, no vsync),
## and how long one full refresh of the table takes. A desktop GPU is far faster
## than a phone's, so compare runs with each other, not with the phone.

const FRAMES := 300


func _initialize() -> void:
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
    DisplayServer.window_set_size(Vector2i.ONE)
    DisplayServer.window_set_position(Vector2i(-32000, -32000))
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0
    OS.low_processor_usage_mode = false
    var args := OS.get_cmdline_user_args()
    var setup: String = args[0] if args.size() > 0 else "tarot5"
    var width := int(args[1]) if args.size() > 1 else 2400
    root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
    var viewport := SubViewport.new()
    viewport.size = Vector2i(width, width * 9 / 20)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var table: Control
    if setup == "belote":
        table = load("res://ui/table.tscn").instantiate()
        viewport.add_child(table)
        await process_frame
        await create_timer(0.5).timeout
        var host: TableHost = table.host
        host.auto_bots = false
        host.start(4)
        var state := host.state
        while not (state.played.size() >= 6 and state.to_act == 0):
            host.game.apply(state, host.bot.choose(host.game.view_for(state, state.to_act)))
        host.resend()
    else:
        table = load("res://ui/tarot_table.tscn").instantiate()
        table.players = int(setup.right(1))
        viewport.add_child(table)
        await process_frame
        await create_timer(0.5).timeout
        var host: TarotHost = table.host
        host.auto_bots = false
        host.start(6)
        var state := host.state
        var bot := TarotBot.new()
        while not (state.phase == TarotState.Phase.PLAYING and state.played.size() >= table.players
                and state.to_act == 0):
            host.game.apply(state, bot.choose(host.game.view_for(state, state.to_act)))
        host.resend()
    # Let the deal animations land, then measure.
    await create_timer(1.5).timeout
    var draw_calls := 0
    var objects := 0
    var started := Time.get_ticks_usec()
    for i in FRAMES:
        await process_frame
        draw_calls += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
        objects += int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
    var frame_ms := (Time.get_ticks_usec() - started) / 1000.0 / FRAMES
    started = Time.get_ticks_usec()
    for i in 10:
        table._refresh()
    var refresh_ms := (Time.get_ticks_usec() - started) / 1000.0 / 10
    await process_frame
    started = Time.get_ticks_usec()
    await process_frame
    var after_refresh_ms := (Time.get_ticks_usec() - started) / 1000.0
    print("%s at %dx%d: %.0f draw calls/frame, %.0f objects, %.2f ms/frame, refresh %.1f ms, first frame after %.1f ms, %d nodes" % [
            setup, viewport.size.x, viewport.size.y, float(draw_calls) / FRAMES, float(objects) / FRAMES,
            frame_ms, refresh_ms, after_refresh_ms, table.get_child(1).get_child_count()])
    quit()
