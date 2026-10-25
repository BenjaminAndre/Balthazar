extends GutTest
## Both table screens always show a Quitter button. It asks first, and only a confirmed
## quit emits menu_requested. The scene change itself is left to the screens' wiring:
## running it here would replace the test runner's scene.


func test_belote_quit_is_asked_first() -> void:
    await _check_quit_asks_first("res://ui/table.tscn")


func test_tarot_quit_is_asked_first() -> void:
    await _check_quit_asks_first("res://ui/tarot_table.tscn")


func _check_quit_asks_first(path: String) -> void:
    var table: Control = add_child_autofree(load(path).instantiate())
    watch_signals(table)
    _find_button(table, "Quitter").pressed.emit()
    var prompt := _prompt(table)
    assert_not_null(prompt, "leaving asks first")
    if prompt == null:
        return
    _find_button(prompt, "Rester").pressed.emit()
    await get_tree().process_frame
    assert_signal_not_emitted(table, "menu_requested", "Rester keeps the game")
    assert_null(_prompt(table), "Rester closes the question")
    _find_button(table, "Quitter").pressed.emit()
    _find_button(_prompt(table), "Quitter").pressed.emit()
    assert_signal_emitted(table, "menu_requested", "confirmed, the game goes to the menu")


func _prompt(table: Control) -> QuitPrompt:
    for child in table.get_children():
        if child is QuitPrompt:
            return child
    return null


func _find_button(node: Node, text: String) -> Button:
    if node is Button and node.text == text:
        return node
    for child in node.get_children():
        var found := _find_button(child, text)
        if found:
            return found
    return null
