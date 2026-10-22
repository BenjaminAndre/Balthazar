extends SceneTree
## A worker process of tools/train.gd: reads a JSON list of jobs (TrainJobs),
## runs them, and writes the JSON list of results next to it.
##     godot --headless --path . -s res://tools/train_worker.gd -- <jobs.json> <results.json>


func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    var jobs: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
    var results := []
    for job in jobs:
        results.append(TrainJobs.run(job))
    var file := FileAccess.open(args[1] + ".part", FileAccess.WRITE)
    file.store_string(JSON.stringify(results))
    file.close()
    # Renamed once complete, so the trainer never reads half a file.
    DirAccess.rename_absolute(args[1] + ".part", args[1])
    quit()
