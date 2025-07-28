extends BaseObject
class_name Item

signal is_equipped(user, slot)
signal is_unequipped(user, slot)
signal used(user)
signal is_thrown(user, target)
signal dropped(user)
signal is_picked_up(user)
signal throw_completed(final_position)

enum ItemFlags {
	IN_INVENTORY = 1,
	WIELDED = 2,
	DELONDROP = 4,
	NOBLUDGEON = 8,
	ABSTRACT = 16,
	IS_DEPLOYED = 32,
	CAN_BUMP_ATTACK = 64
}

enum Slots {
	NONE = 0,
	LEFT_HAND = 1,
	RIGHT_HAND = 2,
	BACKPACK = 4,
	BELT = 8,
	POCKET = 16,
	W_UNIFORM = 32,
	WEAR_SUIT = 48,
	WEAR_MASK = 64,
	HEAD = 128,
	SHOES = 256,
	GLOVES = 512,
	EARS = 1024,
	EYES = 2048,
	WEAR_ID = 4096
}

var item_name: String = "item"
var w_class: int = 3
var highlight_color: Color = Color(1.0, 1.0, 0.0, 0.3)
var is_highlighted: bool = false
var inv_hide_flags: int = 0

@export var force: int = 0
@export var sharp: bool = false
@export var edge: bool = false
@export var attack_verb: Array = ["hits"]
@export var attack_speed: float = 1.1

var equip_slot_flags: int = Slots.LEFT_HAND | Slots.RIGHT_HAND
var current_slot: int = 0
var last_equipped_slot: int = 0
var inventory_owner = null
var wielded: bool = false
var item_flags: int = 0

var equip_delay: float = 0.0
var unequip_delay: float = 0.0
var pickup_delay: float = 0.0

var throwable: bool = true

@export var tool_behaviour: String = ""
@export var toolspeed: float = 1.0
var usesound = null

var drop_sound: AudioStream = null
var pickup_sound: AudioStream = null
var throw_sound: AudioStream = null

var actions: Array = []
var network_id: String = ""

func _init():
	super._init()
	obj_flags |= ObjectFlags.CAN_BE_HIT
	pickupable = true
	network_id = str(randi()) + "_" + str(Time.get_unix_time_from_system())

func _ready():
	super._ready()
	_register_with_tile_system()
	
	if sharp:
		add_to_group("sharp_objects")
	
	if throw_sound == null:
		throw_sound = preload("res://Sound/effects/throwing/throw.wav") if ResourceLoader.exists("res://Sound/effects/throwing/throw.wav") else null
	
	_ensure_interaction_area()
	
	if not is_in_group("items"):
		add_to_group("items")
	if not is_in_group("clickable_entities"):
		add_to_group("clickable_entities")
		
	_ensure_valid_equip_slots()

func _enter_tree():
	if not is_in_group("clickable_entities"):
		add_to_group("clickable_entities")
	if not is_in_group("items"):
		add_to_group("items")

func _exit_tree():
	var world_node = get_node_or_null("/root/World")
	if world_node and "tile_occupancy_system" in world_node and world_node.tile_occupancy_system:
		var tile_system = world_node.tile_occupancy_system
		if tile_system.has_method("unregister_entity"):
			tile_system.unregister_entity(self)

func _register_with_tile_system():
	var world_node = get_node_or_null("/root/World")
	if not world_node:
		world_node = get_node_or_null("/root/GameWorld")
		if not world_node:
			world_node = get_node_or_null("/root/Level")
	
	if world_node and "tile_occupancy_system" in world_node and world_node.tile_occupancy_system:
		var tile_system = world_node.tile_occupancy_system
		
		var tile_pos
		if tile_system.has_method("world_to_tile"):
			tile_pos = tile_system.world_to_tile(global_position)
		else:
			var tile_size = 32
			if "TILE_SIZE" in world_node:
				tile_size = world_node.TILE_SIZE
			tile_pos = Vector2i(int(global_position.x / tile_size), int(global_position.y / tile_size))
		
		var z_level = 0
		
		if tile_system.has_method("register_entity"):
			tile_system.register_entity(self, tile_pos, z_level)

func _ensure_interaction_area():
	var interaction_area = get_node_or_null("InteractionArea")
	
	if interaction_area == null:
		interaction_area = Area2D.new()
		interaction_area.name = "InteractionArea"
		
		var collision_shape = CollisionShape2D.new()
		collision_shape.name = "CollisionShape2D"
		
		var shape = CircleShape2D.new()
		shape.radius = 16.0
		
		var sprite = get_node_or_null("Icon")
		if sprite and sprite.texture:
			var texture_size = sprite.texture.get_size()
			var area_radius = max(texture_size.x, texture_size.y) / 2.0
			shape.radius = area_radius * 1.2
		
		collision_shape.shape = shape
		interaction_area.add_child(collision_shape)
		interaction_area.collision_layer = 8
		interaction_area.collision_mask = 0
		
		add_child(interaction_area)
		interaction_area.add_to_group("interaction_areas")

func _ensure_valid_equip_slots():
	if pickupable:
		if equip_slot_flags == 0:
			equip_slot_flags = Slots.LEFT_HAND | Slots.RIGHT_HAND

func update_appearance() -> void:
	super.update_appearance()
	
	if has_flag(item_flags, ItemFlags.WIELDED):
		pass

func has_flag(flags, flag):
	return (flags & flag) != 0

func set_flag(flags_var: String, flag: int, enabled: bool = true) -> void:
	if enabled:
		self[flags_var] |= flag
	else:
		self[flags_var] &= ~flag

func get_network_id() -> String:
	return network_id

# Fixed multiplayer RPCs with proper integration
@rpc("any_peer", "call_local", "reliable")
func sync_equipped(user_network_id: String, slot: int):
	var user = find_user_by_network_id(user_network_id)
	if user:
		_equipped_internal(user, slot)

func equipped(user, slot: int):
	_equipped_internal(user, slot)
	if multiplayer.has_multiplayer_peer():
		sync_equipped.rpc(get_user_network_id(user), slot)

func _equipped_internal(user, slot: int):
	if inventory_owner and inventory_owner != user:
		_handle_drop_internal(inventory_owner)
	
	inventory_owner = user
	current_slot = slot
	last_equipped_slot = slot
	set_flag("item_flags", ItemFlags.IN_INVENTORY, true)
	
	# Ensure proper parenting and positioning
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	# Set position and visibility for equipped items
	position = Vector2.ZERO
	visible = false
	
	var icon_node = get_node_or_null("Icon")
	if icon_node:
		icon_node.visible = false
	
	apply_to_user(user)
	
	var world = user.get_parent()
	if world and world.has_method("item_equipped"):
		world.item_equipped(self, user, slot)
	
	emit_signal("is_equipped", user, slot)

@rpc("any_peer", "call_local", "reliable")
func sync_unequipped(user_network_id: String, slot: int):
	var user = find_user_by_network_id(user_network_id)
	if user:
		_unequipped_internal(user, slot)

func unequipped(user, slot: int):
	_unequipped_internal(user, slot)
	if multiplayer.has_multiplayer_peer():
		sync_unequipped.rpc(get_user_network_id(user), slot)

func _unequipped_internal(user, slot: int):
	if inventory_owner != user:
		return
		
	remove_from_user(user)
	
	inventory_owner = null
	current_slot = 0
	set_flag("item_flags", ItemFlags.IN_INVENTORY, false)
	
	# Make visible but keep as child of user until dropped
	visible = true
	
	var icon_node = get_node_or_null("Icon")
	if icon_node:
		icon_node.visible = true
	
	emit_signal("is_unequipped", user, slot)

func apply_to_user(user):
	pass

func remove_from_user(user):
	pass

func can_equip(user, slot: int) -> bool:
	if slot == 0:
		return false
	
	if (equip_slot_flags & slot) == 0:
		return false
	
	if "get_item_in_slot" in user:
		var existing_item = user.get_item_in_slot(slot)
		if existing_item:
			return false
	
	return true

@rpc("any_peer", "call_local", "reliable")
func sync_picked_up(user_network_id: String):
	var user = find_user_by_network_id(user_network_id)
	if user:
		_picked_up_internal(user)

func picked_up(user):
	_picked_up_internal(user)
	if multiplayer.has_multiplayer_peer():
		sync_picked_up.rpc(get_user_network_id(user))

func _picked_up_internal(user):
	# Ensure proper parenting when picked up
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	# Set position and visibility
	position = Vector2.ZERO
	visible = false
	
	if pickup_sound:
		play_audio(pickup_sound, -5)
	else:
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager:
			audio_manager.play_positioned_sound("pickup", global_position, 0.4)
	
	emit_signal("is_picked_up", user)

@rpc("any_peer", "call_local", "reliable")
func sync_dropped(user_network_id: String, drop_pos: Vector2):
	var user = find_user_by_network_id(user_network_id)
	if user:
		_handle_drop_internal(user, drop_pos)

func handle_drop(user):
	var drop_pos = global_position
	_handle_drop_internal(user, drop_pos)
	if multiplayer.has_multiplayer_peer():
		sync_dropped.rpc(get_user_network_id(user), drop_pos)

func _handle_drop_internal(user, drop_pos: Vector2 = Vector2.ZERO):
	if has_flag(item_flags, ItemFlags.DELONDROP):
		# Use networked destruction for DELONDROP items
		if multiplayer.has_multiplayer_peer():
			sync_item_destroyed.rpc()
		else:
			_destroy_item_local()
		return
	
	if inventory_owner == user:
		_unequipped_internal(user, current_slot)
	
	var drop_direction = Vector2.DOWN
	var drop_strength = 30.0
	
	if "velocity" in user and user.velocity.length() > 0:
		drop_direction += Vector2(user.velocity.x, 0).normalized() * 0.5
		drop_strength *= (1.0 + user.velocity.length() / 200.0)
	
	# Move to world
	var world = user.get_parent()
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)
	
	# Set world position and make visible
	if drop_pos != Vector2.ZERO:
		global_position = drop_pos
	else:
		global_position = user.global_position + drop_direction * 16.0
	
	visible = true
	
	var icon_node = get_node_or_null("Icon")
	if icon_node:
		icon_node.visible = true
	
	if drop_sound:
		play_audio(drop_sound, -10)
	else:
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager:
			audio_manager.play_positioned_sound("drop", global_position, 0.3)
	
	emit_signal("dropped", user)
	
	if has_flag(item_flags, ItemFlags.WIELDED):
		set_flag("item_flags", ItemFlags.WIELDED, false)
		wielded = false

func play_audio(stream: AudioStream, volume_db: float = 0.0) -> void:
	var audio_player = get_node_or_null("AudioPlayer")
	
	if !audio_player:
		audio_player = AudioStreamPlayer2D.new()
		audio_player.name = "AudioPlayer"
		add_child(audio_player)
	
	audio_player.stream = stream
	audio_player.volume_db = volume_db
	audio_player.pitch_scale = randf_range(0.95, 1.05)
	audio_player.play()

func _remove_from_inventory():
	if inventory_owner != null:
		var inventory_system = inventory_owner.get_node_or_null("InventorySystem")
		if inventory_system:
			var slot = 0
			if inventory_system.has_method("get_item_slot"):
				slot = inventory_system.get_item_slot(self)
			
			if slot != 0 and inventory_system.has_method("unequip_item"):
				inventory_system.unequip_item(slot)
			elif inventory_system.has_method("remove_item"):
				inventory_system.remove_item(self)
		
		inventory_owner = null
		current_slot = 0
		set_flag("item_flags", ItemFlags.IN_INVENTORY, false)

func verify_inventory_state():
	if inventory_owner != null and !has_flag(item_flags, ItemFlags.IN_INVENTORY):
		set_flag("item_flags", ItemFlags.IN_INVENTORY, true)
	
	if inventory_owner == null and has_flag(item_flags, ItemFlags.IN_INVENTORY):
		set_flag("item_flags", ItemFlags.IN_INVENTORY, false)

@rpc("any_peer", "call_local", "reliable")
func sync_used(user_network_id: String):
	var user = find_user_by_network_id(user_network_id)
	if user:
		_use_internal(user)

func use(user):
	# Don't allow using depleted items
	if is_in_group("depleted_items"):
		return false
		
	if inventory_owner != null and inventory_owner != user:
		return false
	
	_use_internal(user)
	if multiplayer.has_multiplayer_peer():
		sync_used.rpc(get_user_network_id(user))
	return true

func _use_internal(user):
	emit_signal("used", user)

func interact(user) -> bool:
	super.interact(user)
	
	# Don't allow interaction with depleted items
	if is_in_group("depleted_items") or not pickupable:
		return false
	
	if pickupable and not has_flag(item_flags, ItemFlags.IN_INVENTORY):
		var inventory_system = user.get_node_or_null("InventorySystem")
		
		if not inventory_system:
			var item_interaction = user.get_node_or_null("ItemInteractionComponent")
			if item_interaction and item_interaction.has_method("try_pick_up_item"):
				return item_interaction.try_pick_up_item(self)
		
		if inventory_system and inventory_system.has_method("pick_up_item"):
			return inventory_system.pick_up_item(self)
		
		elif user.has_method("pickup_item"):
			return user.pickup_item(self)
		
		if user.get_parent() and user.get_parent().has_node("InventorySystem"):
			inventory_system = user.get_parent().get_node("InventorySystem")
			if inventory_system.has_method("pick_up_item"):
				return inventory_system.pick_up_item(self)
	
	return false

func set_highlighted(highlight: bool):
	if is_highlighted == highlight:
		return
		
	is_highlighted = highlight
	
	if is_highlighted:
		var sprite = get_node_or_null("Icon")
		if sprite:
			var material = ShaderMaterial.new()
			var shader = load("res://Shaders/outline.gdshader")
			if shader:
				material.shader = shader
				material.set_shader_parameter("outline_color", highlight_color)
				material.set_shader_parameter("outline_width", 2.0)
				sprite.material = material
			else:
				sprite.modulate = Color(1.2, 1.2, 0.8)
	else:
		var sprite = get_node_or_null("Icon")
		if sprite:
			sprite.material = null
			sprite.modulate = Color(1.0, 1.0, 1.0)

func attack_self(user):
	emit_signal("used", user)
	return false

func afterattack(target, user, proximity: bool, params: Dictionary = {}):
	return false

func can_interact_with(target, user) -> bool:
	return can_interact(user)

func can_use() -> bool:
	return true

func attack(target, user):
	if has_flag(item_flags, ItemFlags.NOBLUDGEON):
		return false
	
	if "hit_sound" in self and hit_sound:
		play_audio(hit_sound)
		
	var damage = force
	
	if has_flag(item_flags, ItemFlags.WIELDED) and "force_wielded" in self:
		damage = self.force_wielded
	
	if "take_damage" in target:
		target.take_damage(damage, "brute", "melee", true, 0.0, user)
		
	if "visible_message" in user:
		var verb = attack_verb[randi() % attack_verb.size()] if attack_verb.size() > 0 else "hits"
		user.visible_message("%s %s %s with %s" % [user.name, verb, target.name, obj_name])
	
	return true

func toggle_wielded(user) -> bool:
	if not can_be_wielded():
		return false
	
	wielded = !wielded
	set_flag("item_flags", ItemFlags.WIELDED, wielded)
	
	if wielded:
		if "visible_message" in user:
			user.visible_message("%s grips %s with both hands." % [user.name, obj_name])
	else:
		if "visible_message" in user:
			user.visible_message("%s loosens their grip on %s." % [user.name, obj_name])
	
	update_appearance()
	return true

func can_be_wielded() -> bool:
	return false

# FIXED: Proper multiplayer throw synchronization
@rpc("any_peer", "call_local", "reliable")
func sync_throw(thrower_network_id: String, start_pos: Vector2, target_pos: Vector2):
	var thrower = find_user_by_network_id(thrower_network_id)
	if thrower:
		_throw_to_position_internal(thrower, start_pos, target_pos)

func throw_to_position(thrower, target_position: Vector2) -> bool:
	# Move to world first
	var world = thrower.get_parent()
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)
	
	# Set starting position
	var start_pos = thrower.global_position
	global_position = start_pos
	visible = true
	
	# Execute throw locally
	_throw_to_position_internal(thrower, start_pos, target_position)
	
	# Sync throw across network
	if multiplayer.has_multiplayer_peer():
		sync_throw.rpc(get_user_network_id(thrower), start_pos, target_position)
	
	return true

func _throw_to_position_internal(thrower, start_pos: Vector2, target_position: Vector2):
	# Set item state
	visible = true
	set_flag("item_flags", ItemFlags.IN_INVENTORY, false)
	inventory_owner = null
	
	var icon_node = get_node_or_null("Icon")
	if icon_node:
		icon_node.visible = true
	
	# Ensure item is in world
	var world = thrower.get_parent()
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)
	
	# Set starting position
	global_position = start_pos
	
	# Calculate final landing position
	var final_position = calculate_landing_position(target_position)
	
	# Play throw sound
	if throw_sound:
		play_audio(throw_sound, 0.5)
	else:
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager:
			audio_manager.play_positioned_sound("throw", start_pos, 0.4)
	
	# Animate the throw
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(self, "global_position", final_position, 0.3)
	tween.tween_property(self, "rotation", rotation + randf_range(-PI/2, PI/2), 0.3)
	
	await tween.finished
	_on_throw_complete()
	
	emit_signal("is_thrown", thrower, final_position)
	emit_signal("throw_completed", final_position)

func calculate_landing_position(target_position: Vector2) -> Vector2:
	var accuracy = 1.0 / (1.0 + (w_class - 1) * 0.3)
	
	var max_offset = 32.0 * (1.0 - accuracy)
	var offset = Vector2(
		randf_range(-max_offset, max_offset),
		randf_range(-max_offset, max_offset)
	)
	
	return target_position + offset

func _on_throw_complete():
	_register_with_tile_system()
	
	var impact_tween = create_tween()
	impact_tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.1)
	impact_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_positioned_sound("item_land", global_position, 0.4)
	
	check_throw_impact()

func check_throw_impact():
	var world = get_parent()
	if world and "tile_occupancy_system" in world and world.tile_occupancy_system:
		var tile_system = world.tile_occupancy_system
		var tile_pos = world_to_tile(global_position)
		
		if tile_system.has_method("get_entities_at"):
			var entities = tile_system.get_entities_at(tile_pos, 0)
			
			for entity in entities:
				if entity != self and "entity_type" in entity:
					if entity.entity_type == "character" or entity.entity_type == "mob":
						if entity.has_method("take_damage"):
							var throw_damage = max(force, 2.0)
							entity.take_damage(throw_damage, "blunt", "thrown", true)
						
						var audio_manager = get_node_or_null("/root/AudioManager")
						if audio_manager:
							audio_manager.play_positioned_sound("throw_hit", global_position, 0.5)
						break

func throw(thrower, direction: Vector2, force: float = 100.0) -> bool:
	var throw_distance = 160.0 * (force / 100.0)
	var target_pos = thrower.global_position + direction * throw_distance
	
	return await throw_to_position(thrower, target_pos)

func use_tool(target, user, time: float, amount: int = 0, volume: float = 0) -> bool:
	if tool_behaviour.is_empty():
		return false
	
	if usesound:
		play_audio(usesound, volume)
	
	await get_tree().create_timer(time * toolspeed).timeout
	
	return true

func get_actions() -> Array:
	return actions

func get_display_name() -> String:
	if "item_name" in self and item_name:
		return item_name
	return name

func world_to_tile(world_pos):
	var tile_size = 32
	var world = get_node_or_null("/root/World")
	if world and "TILE_SIZE" in world:
		tile_size = world.TILE_SIZE
	
	return Vector2i(int(world_pos.x / tile_size), int(world_pos.y / tile_size))

func tile_to_world(tile_pos):
	var tile_size = 32
	var world = get_node_or_null("/root/World")
	if world and "TILE_SIZE" in world:
		tile_size = world.TILE_SIZE
	
	return Vector2((tile_pos.x * tile_size) + (tile_size / 2.0), (tile_pos.y * tile_size) + (tile_size / 2.0))

func animate_throw(target_position: Vector2):
	visible = true
	
	var final_position = calculate_landing_position(target_position)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", final_position, 0.3)
	tween.tween_property(self, "rotation", rotation + randf_range(-PI/2, PI/2), 0.3)

@rpc("any_peer", "call_local", "reliable")
func show_use_effect():
	var sprite = get_node_or_null("Icon")
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.1)
		tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)

# ITEM CLEANUP SYNCHRONIZATION
@rpc("any_peer", "call_local", "reliable")
func sync_item_destroyed():
	_destroy_item_local()

@rpc("any_peer", "call_local", "reliable") 
func sync_item_depleted():
	_deplete_item_local()

func destroy_item():
	"""Permanently destroy this item across all clients"""
	if multiplayer.has_multiplayer_peer():
		sync_item_destroyed.rpc()
	else:
		_destroy_item_local()

func _destroy_item_local():
	"""Locally destroy the item - remove from inventory and free from scene"""
	# Remove from inventory if equipped
	if inventory_owner:
		var inventory_system = inventory_owner.get_node_or_null("InventorySystem")
		if inventory_system:
			var slot = inventory_system.find_slot_with_item(self)
			if slot != inventory_system.EquipSlot.NONE:
				inventory_system.equipped_items[slot] = null
				inventory_system.remove_from_lists(self)
				inventory_system.update_slot_visuals(slot)
				inventory_system.emit_signal("inventory_updated")
	
	# Remove from parent
	if get_parent():
		get_parent().remove_child(self)
	
	# Free the item
	queue_free()

func deplete_item():
	"""Mark item as depleted/unusable across all clients"""
	if multiplayer.has_multiplayer_peer():
		sync_item_depleted.rpc()
	else:
		_deplete_item_local()

func _deplete_item_local():
	"""Locally mark item as depleted - make unusable but keep in scene"""
	# Mark as unusable
	pickupable = false
	
	# Update visual appearance to show depletion
	var sprite = get_node_or_null("Icon")
	if sprite:
		sprite.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Grayed out
	
	# Add to a "depleted" group for identification
	if not is_in_group("depleted_items"):
		add_to_group("depleted_items")
	
	# Emit signal for other systems
	emit_signal("used", null)  # Signal that it's been consumed

# Helper functions for multiplayer
func get_user_network_id(user: Node) -> String:
	if not user:
		return ""
	
	if user.has_method("get_network_id"):
		return user.get_network_id()
	elif "peer_id" in user:
		return "player_" + str(user.peer_id)
	elif user.has_meta("network_id"):
		return user.get_meta("network_id")
	else:
		return user.get_path()

func find_user_by_network_id(network_id: String) -> Node:
	if network_id == "":
		return null
	
	# Handle player targets
	if network_id.begins_with("player_"):
		var peer_id_str = network_id.split("_")[1]
		var peer_id_val = peer_id_str.to_int()
		return find_player_by_peer_id(peer_id_val)
	
	# Handle path-based targets
	if network_id.begins_with("/"):
		return get_node_or_null(network_id)
	
	return null

func find_player_by_peer_id(peer_id_val: int) -> Node:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.has_meta("peer_id") and player.get_meta("peer_id") == peer_id_val:
			return player
		if "peer_id" in player and player.peer_id == peer_id_val:
			return player
	
	return null

func serialize():
	var data = {
		"item_name": item_name,
		"description": description,
		"force": force,
		"w_class": w_class,
		"sharp": sharp,
		"edge": edge,
		"attack_speed": attack_speed,
		"equip_slot_flags": equip_slot_flags,
		"item_flags": item_flags,
		"current_slot": current_slot,
		"last_equipped_slot": last_equipped_slot,
		"wielded": wielded,
		"pickupable": pickupable,
		"inv_hide_flags": inv_hide_flags,
		"obj_integrity": obj_integrity,
		"max_integrity": max_integrity,
		"network_id": network_id,
		"is_depleted": is_in_group("depleted_items")
	}
	return data

func deserialize(data):
	if "item_name" in data: item_name = data.item_name
	if "description" in data: description = data.description
	if "force" in data: force = data.force
	if "w_class" in data: w_class = data.w_class
	if "sharp" in data: sharp = data.sharp
	if "edge" in data: edge = data.edge
	if "attack_speed" in data: attack_speed = data.attack_speed
	if "equip_slot_flags" in data: equip_slot_flags = data.equip_slot_flags
	if "item_flags" in data: item_flags = data.item_flags
	if "current_slot" in data: current_slot = data.current_slot
	if "last_equipped_slot" in data: last_equipped_slot = data.last_equipped_slot
	if "wielded" in data: wielded = data.wielded
	if "pickupable" in data: pickupable = data.pickupable
	if "inv_hide_flags" in data: inv_hide_flags = data.inv_hide_flags
	if "obj_integrity" in data: obj_integrity = data.obj_integrity
	if "max_integrity" in data: max_integrity = data.max_integrity
	if "network_id" in data: network_id = data.network_id
	if "is_depleted" in data and data.is_depleted: 
		_deplete_item_local()
