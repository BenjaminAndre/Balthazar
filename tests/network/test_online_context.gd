extends GutTest
## The Tube context the app opens tables with must pass Tube's own check. A wrong app
## id (it must be exactly 15 ASCII characters) made every table fail with "context is invalid".


func test_tube_accepts_the_app_context() -> void:
    var context := Online.make_context()
    assert_true(context.is_valid(), "Tube refuses the app context: the app id must be exactly 15 ASCII characters")


func test_app_id_has_tube_length() -> void:
    assert_eq(Online.APP_ID.length(), 15)
