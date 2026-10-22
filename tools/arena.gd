extends SceneTree
## Plays two bot levels against each other on duplicate hands (BotArena):
##     godot --headless --path . -s res://tools/arena.gd -- difficile facile 300 [pimc samples]


func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    var a: String = args[0] if args.size() > 0 else "difficile"
    var b: String = args[1] if args.size() > 1 else "facile"
    var deals := int(args[2]) if args.size() > 2 else 200
    var started := Time.get_ticks_msec()
    var bot_a := BeloteBots.make(a)
    if bot_a is BeloteBotPimc and args.size() > 3:
        bot_a.samples = int(args[3])
    var result := BotArena.match_up(bot_a, BeloteBots.make(b), deals)
    print("%s vs %s over %d deals: %+.1f ± %.1f points per hand (%.1f s)" % [a, b, deals,
            result.mean, 2.0 * result.stderr, (Time.get_ticks_msec() - started) / 1000.0])
    quit()
