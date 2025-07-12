extends Control
class_name RadialMenu

# Signals
signal option_selected(option)
signal menu_closed()

# Menu properties
var radius = 100
var inner_radius = 30
var option_radius = 24
var option_distance = 70
var is_open = false
var target_entity = null
var option_list = []

# Visual properties
var background_color = Color(0.1, 0.1, 0.1, 0.7)
var highlight_color = Color(0.2, 0.5, 0.8, 0.9)
var option_color = Color(0.2, 0.2, 0.2, 0.9)
var text_color = Color(1.0, 1.0, 1.0, 1.0)

# Interaction tracking
var highlighted_option = -1
var animation_player = null
var center_position = Vector2.ZERO
var option_nodes = []
var labels = []
var icon_textures = {}
var font = null

# Initialize the menu
func _ready():
	# Create animation player
	animation_player = AnimationPlayer.new()
	add_child(animation_player)
	
	# Set up initial state
	is_open = false
	visible = false
	modulate.a = 0
	
	# Preload icon textures
	_preload_icons()
	
	# Set fonts
	font = ThemeDB.fallback_font
	
	# Set mouse filter mode
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# Called when the node enters the scene tree
func _enter_tree():
	# Make sure we're on top of other UI
	z_index = 100

# Preload common icon textures
func _preload_icons():
	var icons = ["examine", "use", "pickup", "attack", "talk", "pull", "grab", "push", 
				 "open", "close", "lock", "unlock", "throw", "equip", "drop"]
				 
	for icon_name in icons:
		var path = "res://icons/" + icon_name + ".png"
		if ResourceLoader.exists(path):
			icon_textures[icon_name] = load(path)
		else:
			# Create a default texture if icon doesn't exist
			var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
			image.fill(Color(0.5, 0.5, 0.5, 1.0))
			var texture = ImageTexture.create_from_image(image)
			icon_textures[icon_name] = texture

# Draw the radial menu
func _draw():
	if !is_open:
		return
	
	# Draw background circle
	draw_circle(center_position, radius, background_color)
	
	# Draw inner circle
	draw_circle(center_position, inner_radius, option_color)
	
	# Draw each option
	for i in range(option_list.size()):
		var angle = 2 * PI * i / option_list.size()
		var option_pos = center_position + Vector2(cos(angle), sin(angle)) * option_distance
		
		# Draw option circle
		var color = highlight_color if i == highlighted_option else option_color
		draw_circle(option_pos, option_radius, color)
		
		# Draw icon if available
		var option = option_list[i]
		if "icon" in option and option.icon in icon_textures:
			var texture = icon_textures[option.icon]
			var icon_size = Vector2(option_radius * 1.5, option_radius * 1.5)
			var icon_pos = option_pos - icon_size / 2
			
			draw_texture_rect(texture, Rect2(icon_pos, icon_size), false)
	
	# Draw option labels
	for i in range(labels.size()):
		if i < option_list.size():
			var angle = 2 * PI * i / option_list.size()
			var option_pos = center_position + Vector2(cos(angle), sin(angle)) * option_distance
			
			# Position label near option
			var label = labels[i]
			label.text = option_list[i].name
			label.position = option_pos + Vector2(0, option_radius + 10)
			label.position.x -= label.size.x / 2  # Center horizontally
			
			# Update color based on highlight
			if i == highlighted_option:
				label.add_theme_color_override("font_color", highlight_color)
			else:
				label.add_theme_color_override("font_color", text_color)

# Process input for menu interaction
func _input(event):
	if !is_open:
		return
	
	if event is InputEventMouseMotion:
		_update_highlight(event.position)
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Left click - select option
			if highlighted_option >= 0 and highlighted_option < option_list.size():
				_select_option(highlighted_option)
			else:
				close()  # Close when clicking outside options
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right click - close menu
			close()

# Update highlighted option based on mouse position
func _update_highlight(mouse_pos):
	# Reset highlight
	highlighted_option = -1
	
	# Calculate distance from center
	var distance = mouse_pos.distance_to(center_position)
	
	# Check if mouse is in the option ring
	if distance > inner_radius and distance < radius:
		# Calculate angle from center
		var angle = atan2(mouse_pos.y - center_position.y, mouse_pos.x - center_position.x)
		if angle < 0:
			angle += 2 * PI
		
		# Determine which option is highlighted
		var option_count = option_list.size()
		if option_count > 0:
			var option_angle = 2 * PI / option_count
			highlighted_option = int(angle / option_angle) % option_count
	
	# Redraw menu
	queue_redraw()

# Select an option
func _select_option(index):
	if index < 0 or index >= option_list.size():
		return
	
	var option = option_list[index]
	
	# Call the callback if specified
	if "callback" in option and option.callback is Callable:
		option.callback.call()
	
	# Emit option selected signal
	emit_signal("option_selected", option)
	
	# Close the menu
	close()

# Create label nodes for options
func _create_option_labels():
	# Clear existing labels
	for label in labels:
		label.queue_free()
	
	labels.clear()
	
	# Create new labels
	for i in range(option_list.size()):
		var label = Label.new()
		label.text = option_list[i].name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", text_color)
		
		# Add to container
		add_child(label)
		labels.append(label)

# Open the radial menu
func open(entity, options, position):
	# Set target entity
	target_entity = entity
	
	# Set position
	center_position = position
	
	# Set options
	option_list = options
	
	# Create labels
	_create_option_labels()
	
	# Make visible and start animation
	visible = true
	is_open = true
	animation_player.play("open")
	
	# Make sure menu is drawn
	queue_redraw()

# Close the radial menu
func close():
	if !is_open:
		return
	
	# Play close animation
	animation_player.play("close")
	
	# Hide after animation
	await animation_player.animation_finished
	visible = false
	is_open = false
	
	# Reset state
	target_entity = null
	option_list = []
	highlighted_option = -1
	
	# Emit signal
	emit_signal("menu_closed")
