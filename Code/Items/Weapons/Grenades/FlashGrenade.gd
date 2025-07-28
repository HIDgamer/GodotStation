extends Grenade
class_name FlashbangGrenade

@export_group("Effect Ranges")
@export var inner_range: int = 2
@export var outer_range: int = 5  
@export var max_range: int = 7

@export_group("Effect Parameters")
@export var flash_duration: float = 10.0
@export var ear_damage_base: int = 5
@export var stun_duration_base: float = 20.0
@export var paralyze_duration: float = 6.0
@export var ear_damage_chance: int = 70
@export var blur_duration: float = 7.0

@export_group("Special Properties")
@export var mp_only: bool = true
@export var banglet: bool = false

# Multiplayer integration with InventorySystem
var inventory_sync_enabled: bool = true
var flashbang_pending: bool = false

# Preloaded resources
static var flash_scene: PackedScene

func _init():
	super._init()
	obj_name = "flashbang"
	obj_desc = "A grenade sometimes used by police, civilian or military, to stun targets with a flash, then a bang. May cause hearing loss, and induce feelings of overwhelming rage in victims."
	grenade_type = GrenadeType.FLASHBANG
	det_time = 4.0
	flash_range = 7
	dangerous = true
	
	if not flash_scene:
		flash_scene = preload("res://Scenes/Effects/Flash.tscn")

func _ready():
	super._ready()

# Override Item multiplayer methods to integrate with InventorySystem
func equipped(user, slot: int):
	super.equipped(user, slot)
	
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	position = Vector2.ZERO
	visible = false
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_equipped_state.rpc(active, flashbang_pending, get_item_network_id(self))

func unequipped(user, slot: int):
	super.unequipped(user, slot)
	visible = true
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_unequipped_state.rpc(active, flashbang_pending, get_item_network_id(self))

func picked_up(user):
	super.picked_up(user)
	
	if get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
	
	position = Vector2.ZERO
	visible = false
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_pickup_state.rpc(active, flashbang_pending, det_time, get_item_network_id(self))

func handle_drop(user):
	super.handle_drop(user)
	
	var world = user.get_parent()
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)
	
	global_position = user.global_position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
	visible = true
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_drop_state.rpc(active, flashbang_pending, global_position, get_item_network_id(self))

func throw_to_position(thrower, target_position: Vector2) -> bool:
	var world = thrower.get_parent()
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)
	
	global_position = thrower.global_position
	visible = true
	
	var result = await super.throw_to_position(thrower, target_position)
	
	if inventory_sync_enabled and multiplayer.has_multiplayer_peer():
		sync_grenade_throw_state.rpc(active, flashbang_pending, global_position, get_item_network_id(self))
	
	return result

func use(user):
	var result = super.use(user)
	
	if not active:
		result = activate()
	
	return result

func get_item_network_id(item) -> String:
	if item.has_method("get_network_id"):
		return item.get_network_id()
	elif "network_id" in item and item.network_id != "":
		return str(item.network_id)
	elif item.has_meta("network_id"):
		return str(item.get_meta("network_id"))
	else:
		var new_id = str(item.get_instance_id()) + "_" + str(Time.get_ticks_msec())
		item.set_meta("network_id", new_id)
		return new_id

#region INVENTORY SYSTEM INTEGRATION RPCS
@rpc("any_peer", "call_local", "reliable")
func sync_grenade_equipped_state(is_active: bool, pending_flashbang: bool, item_id: String):
	active = is_active
	flashbang_pending = pending_flashbang
	
	var user = find_item_owner(item_id)
	if user and get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
		position = Vector2.ZERO
		visible = false

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_unequipped_state(is_active: bool, pending_flashbang: bool, item_id: String):
	active = is_active
	flashbang_pending = pending_flashbang
	visible = true

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_pickup_state(is_active: bool, pending_flashbang: bool, current_det_time: float, item_id: String):
	active = is_active
	flashbang_pending = pending_flashbang
	det_time = current_det_time
	
	var user = find_item_owner(item_id)
	if user and get_parent() != user:
		if get_parent():
			get_parent().remove_child(self)
		user.add_child(self)
		position = Vector2.ZERO
		visible = false

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_drop_state(is_active: bool, pending_flashbang: bool, drop_pos: Vector2, item_id: String):
	active = is_active
	flashbang_pending = pending_flashbang
	global_position = drop_pos
	visible = true
	
	var world = get_tree().current_scene
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)

@rpc("any_peer", "call_local", "reliable")
func sync_grenade_throw_state(is_active: bool, pending_flashbang: bool, throw_pos: Vector2, item_id: String):
	active = is_active
	flashbang_pending = pending_flashbang
	global_position = throw_pos
	visible = true
	
	var world = get_tree().current_scene
	if get_parent() != world:
		if get_parent():
			get_parent().remove_child(self)
		world.add_child(self)

@rpc("any_peer", "call_local", "reliable")
func sync_flashbang_explosion(explosion_pos: Vector2, flashbang_data: Dictionary):
	execute_flashbang_explosion_local(explosion_pos, flashbang_data)

@rpc("any_peer", "call_local", "reliable")
func sync_flashbang_effects(targets_data: Array):
	apply_flashbang_effects_local(targets_data)

@rpc("any_peer", "call_local", "reliable")
func sync_flash_effect(pos: Vector2):
	create_flash_effect_local(pos)

@rpc("any_peer", "call_local", "reliable")
func sync_flashbang_sound(pos: Vector2):
	play_flashbang_sound_local(pos)

@rpc("any_peer", "call_local", "reliable")
func sync_skill_check_failure(user_id: String):
	handle_skill_check_failure_local(user_id)
#endregion

func find_item_owner(item_id: String) -> Node:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		var inventory = player.get_node_or_null("InventorySystem")
		if inventory and "equipped_items" in inventory:
			for slot in inventory.equipped_items:
				var item = inventory.equipped_items[slot]
				if item and get_item_network_id(item) == item_id:
					return player
	return null

func attack_self(user) -> bool:
	if mp_only and "skills" in user and user.skills.has_method("getRating"):
		var police_skill = user.skills.getRating("POLICE")
		if police_skill < 3:
			if multiplayer.has_multiplayer_peer():
				sync_skill_check_failure.rpc(get_entity_id(user))
			else:
				handle_skill_check_failure_local(get_entity_id(user))
			return false
	
	return super.attack_self(user)

func handle_skill_check_failure_local(user_id: String):
	var user = find_entity_by_id(user_id)
	if user and user.has_method("display_message"):
		user.display_message("You don't seem to know how to use [color=yellow]%s[/color]..." % [obj_name])

func explode() -> void:
	if not active:
		return
	
	var explosion_pos = global_position
	flashbang_pending = true
	
	super.explode()
	
	var flashbang_data = {
		"inner_range": inner_range,
		"outer_range": outer_range,
		"max_range": max_range,
		"flash_duration": flash_duration,
		"ear_damage_base": ear_damage_base,
		"stun_duration_base": stun_duration_base,
		"paralyze_duration": paralyze_duration,
		"ear_damage_chance": ear_damage_chance,
		"blur_duration": blur_duration
	}
	
	if multiplayer.has_multiplayer_peer():
		sync_flashbang_explosion.rpc(explosion_pos, flashbang_data)
	else:
		execute_flashbang_explosion_local(explosion_pos, flashbang_data)

func execute_flashbang_explosion_local(explosion_pos: Vector2, flashbang_data: Dictionary):
	inner_range = flashbang_data.get("inner_range", inner_range)
	outer_range = flashbang_data.get("outer_range", outer_range)
	max_range = flashbang_data.get("max_range", max_range)
	flash_duration = flashbang_data.get("flash_duration", flash_duration)
	ear_damage_base = flashbang_data.get("ear_damage_base", ear_damage_base)
	stun_duration_base = flashbang_data.get("stun_duration_base", stun_duration_base)
	paralyze_duration = flashbang_data.get("paralyze_duration", paralyze_duration)
	ear_damage_chance = flashbang_data.get("ear_damage_chance", ear_damage_chance)
	blur_duration = flashbang_data.get("blur_duration", blur_duration)
	
	create_flash_effect_local(explosion_pos)
	play_flashbang_sound_local(explosion_pos)
	apply_flashbang_effects(explosion_pos)
	
	flashbang_pending = false
	_destroy_item_local()

func create_flash_effect_local(pos: Vector2) -> void:
	if not flash_scene:
		return
	
	var flash = flash_scene.instantiate()
	if flash:
		get_tree().current_scene.add_child(flash)
		flash.global_position = pos
		
		create_cleanup_timer(flash, 2.0)

func play_flashbang_sound_local(pos: Vector2) -> void:
	var flashbang_sound = load("res://Sound/Grenades/flashbang2.mp3")
	if flashbang_sound:
		play_cached_sound(flashbang_sound, 10.0)

func apply_flashbang_effects(pos: Vector2) -> void:
	var tile_size = 32
	var max_distance = max_range * tile_size
	
	var entities = get_entities_in_radius(pos, max_distance)
	var targets_data = []
	
	for entity in entities:
		var distance_tiles = entity.global_position.distance_to(pos) / tile_size
		
		if is_flashbang_immune(entity):
			continue
		
		if not has_line_of_sight(pos, entity.global_position):
			continue
		
		var effect_data = calculate_effect_data(entity, pos, distance_tiles)
		if effect_data.size() > 0:
			targets_data.append({
				"target_id": get_entity_id(entity),
				"effect_data": effect_data
			})
	
	if multiplayer.has_multiplayer_peer():
		sync_flashbang_effects.rpc(targets_data)
	else:
		apply_flashbang_effects_local(targets_data)

func apply_flashbang_effects_local(targets_data: Array):
	for target_info in targets_data:
		var target_id = target_info.get("target_id", "")
		var effect_data = target_info.get("effect_data", {})
		
		apply_target_flashbang_effect_local(target_id, effect_data)

func calculate_effect_data(entity: Node, explosion_pos: Vector2, distance_tiles: float) -> Dictionary:
	var effect_data = {
		"distance_tiles": distance_tiles,
		"is_human": is_human_entity(entity),
		"ear_protection": get_ear_protection(entity),
		"is_owner": entity == inventory_owner
	}
	
	if distance_tiles <= inner_range:
		effect_data["flash_intensity"] = 10
		effect_data["blur_power"] = blur_duration
		effect_data["range_type"] = "inner"
		if effect_data["ear_protection"] == 0:
			effect_data["stun_duration"] = stun_duration_base
			effect_data["paralyze_duration"] = paralyze_duration
		else:
			effect_data["stun_duration"] = 4.0
			effect_data["paralyze_duration"] = 2.0
		effect_data["ear_damage_intensity"] = 1.0
	elif distance_tiles <= outer_range:
		effect_data["flash_intensity"] = 6
		effect_data["blur_power"] = blur_duration * 0.8
		effect_data["range_type"] = "middle"
		if effect_data["ear_protection"] == 0:
			effect_data["stun_duration"] = stun_duration_base * 0.8
		effect_data["ear_damage_intensity"] = 0.8
	elif distance_tiles <= max_range:
		effect_data["flash_intensity"] = 3
		effect_data["blur_power"] = blur_duration * 0.6
		effect_data["range_type"] = "outer"
		if effect_data["ear_protection"] == 0:
			effect_data["stun_duration"] = stun_duration_base * 0.4
		effect_data["ear_damage_intensity"] = 0.4
	
	return effect_data

func apply_target_flashbang_effect_local(target_id: String, effect_data: Dictionary):
	var entity = find_entity_by_id(target_id)
	if not entity:
		return
	
	send_flashbang_feedback_local(entity)
	apply_flash_effect_local(entity, effect_data)
	apply_blur_effect_local(entity, effect_data)
	apply_range_effects_local(entity, effect_data)

func send_flashbang_feedback_local(entity: Node) -> void:
	if entity.has_method("display_message"):
		entity.display_message("[color=red]BANG[/color]")

func apply_flash_effect_local(entity: Node, effect_data: Dictionary) -> void:
	if not entity.has_method("flash_act"):
		return
	
	var flash_intensity = effect_data.get("flash_intensity", 3)
	entity.flash_act(flash_intensity)

func apply_blur_effect_local(entity: Node, effect_data: Dictionary) -> void:
	if not entity.has_method("blur_eyes"):
		return
	
	var blur_power = effect_data.get("blur_power", blur_duration * 0.6)
	entity.blur_eyes(blur_power)

func apply_range_effects_local(entity: Node, effect_data: Dictionary) -> void:
	var range_type = effect_data.get("range_type", "outer")
	var is_human = effect_data.get("is_human", false)
	var ear_protection = effect_data.get("ear_protection", 0)
	
	if not is_human:
		return
	
	if "stun_duration" in effect_data and entity.has_method("apply_effects"):
		entity.apply_effects("stun", effect_data["stun_duration"])
	
	if "paralyze_duration" in effect_data and entity.has_method("apply_effects"):
		entity.apply_effects("paralyze", effect_data["paralyze_duration"])
	
	if ear_protection == 0 and "ear_damage_intensity" in effect_data:
		apply_ear_damage_local(entity, effect_data)

func apply_ear_damage_local(entity: Node, effect_data: Dictionary) -> void:
	if not entity.has_method("adjust_ear_damage"):
		return
	
	var intensity_modifier = effect_data.get("ear_damage_intensity", 0.4)
	var chance_modifier = intensity_modifier
	
	if effect_data.get("is_owner", false):
		chance_modifier *= 1.2
	
	var damage_roll = randf() * 100
	var threshold = ear_damage_chance * chance_modifier
	
	if damage_roll < threshold:
		var damage_amount = randi_range(1, int(10 * intensity_modifier))
		var deafen_amount = int(15 * intensity_modifier)
		entity.adjust_ear_damage(damage_amount, deafen_amount)
	else:
		var damage_amount = randi_range(0, int(5 * intensity_modifier))
		var deafen_amount = int(10 * intensity_modifier)
		entity.adjust_ear_damage(damage_amount, deafen_amount)

func is_flashbang_immune(entity: Node) -> bool:
	if "has_trait" in entity and entity.has_method("has_trait"):
		return entity.has_trait("FLASHBANGIMMUNE")
	return false

func is_human_entity(entity: Node) -> bool:
	return "is_human" in entity and entity.is_human

func get_ear_protection(entity: Node) -> int:
	var ear_safety = 0
	
	if "inventory" in entity and entity.inventory:
		ear_safety += check_inventory_ear_protection(entity.inventory)
	else:
		ear_safety += check_direct_ear_protection(entity)
	
	return ear_safety

func check_inventory_ear_protection(inventory: Node) -> int:
	var protection = 0
	
	var ear_item = inventory.get_item_in_slot(inventory.EquipSlot.EARS)
	if ear_item and ear_item.has_method("get_type") and ear_item.get_type() == "earmuffs":
		protection += 2
	
	var head_item = inventory.get_item_in_slot(inventory.EquipSlot.HEAD)
	if head_item and head_item.has_method("get_type"):
		var helmet_type = head_item.get_type()
		if helmet_type == "riot_helmet":
			protection += 2
		elif helmet_type == "commando_helmet":
			protection = 999
	
	return protection

func check_direct_ear_protection(entity: Node) -> int:
	var protection = 0
	
	if "wear_ear" in entity and entity.wear_ear:
		if entity.wear_ear.has_method("get_type") and entity.wear_ear.get_type() == "earmuffs":
			protection += 2
	
	if "head" in entity and entity.head:
		if entity.head.has_method("get_type"):
			var helmet_type = entity.head.get_type()
			if helmet_type == "riot_helmet":
				protection += 2
			elif helmet_type == "commando_helmet":
				protection = 999
	
	return protection

func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	return result.is_empty()

# Helper functions
func get_entity_id(entity: Node) -> String:
	if not entity:
		return ""
	
	if entity.has_method("get_network_id"):
		return entity.get_network_id()
	elif "peer_id" in entity:
		return "player_" + str(entity.peer_id)
	elif entity.has_meta("network_id"):
		return entity.get_meta("network_id")
	else:
		return entity.get_path()

func find_entity_by_id(entity_id: String) -> Node:
	if entity_id == "":
		return null
	
	if entity_id.begins_with("player_"):
		var peer_id_str = entity_id.split("_")[1]
		var peer_id_val = peer_id_str.to_int()
		return find_player_by_peer_id(peer_id_val)
	
	if entity_id.begins_with("/"):
		return get_node_or_null(entity_id)
	
	var entities = get_tree().get_nodes_in_group("networkable")
	for entity in entities:
		if entity.has_meta("network_id") and entity.get_meta("network_id") == entity_id:
			return entity
		if entity.has_method("get_network_id") and entity.get_network_id() == entity_id:
			return entity
	
	return null

func find_player_by_peer_id(peer_id_val: int) -> Node:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.has_meta("peer_id") and player.get_meta("peer_id") == peer_id_val:
			return player
		if "peer_id" in player and player.peer_id == peer_id_val:
			return player
	return null

func get_entities_in_radius(center: Vector2, radius: float) -> Array:
	var entities = []
	var all_entities = get_tree().get_nodes_in_group("entities")
	
	for entity in all_entities:
		if entity is Node2D and entity.global_position.distance_to(center) <= radius:
			entities.append(entity)
	
	return entities

func create_cleanup_timer(node: Node, duration: float):
	var timer = Timer.new()
	timer.wait_time = duration
	timer.one_shot = true
	timer.timeout.connect(func(): 
		if is_instance_valid(node):
			node.queue_free()
	)
	node.add_child(timer)
	timer.start()

func play_cached_sound(sound: AudioStream, volume: float = 0.0):
	if not sound:
		return
	
	var audio_player = AudioStreamPlayer2D.new()
	audio_player.stream = sound
	audio_player.volume_db = volume
	audio_player.autoplay = true
	audio_player.finished.connect(audio_player.queue_free)
	get_tree().current_scene.add_child(audio_player)
	audio_player.global_position = global_position

static func create_stun_variant() -> FlashbangGrenade:
	var stun_grenade = FlashbangGrenade.new()
	stun_grenade.obj_name = "stun grenade"
	stun_grenade.obj_desc = "A grenade designed to disorientate the senses of anyone caught in the blast radius with a blinding flash of light and viciously loud noise. Repeated use can cause deafness."
	
	stun_grenade.inner_range = 3
	stun_grenade.det_time = 2.0
	stun_grenade.mp_only = false
	
	stun_grenade.flash_duration = 15.0
	stun_grenade.blur_duration = 10.0
	stun_grenade.ear_damage_base = 3
	stun_grenade.stun_duration_base = 12.0
	stun_grenade.paralyze_duration = 0.0
	
	return stun_grenade

func serialize() -> Dictionary:
	var data = super.serialize()
	
	data["inner_range"] = inner_range
	data["outer_range"] = outer_range
	data["max_range"] = max_range
	data["mp_only"] = mp_only
	data["banglet"] = banglet
	data["flash_duration"] = flash_duration
	data["stun_duration_base"] = stun_duration_base
	data["paralyze_duration"] = paralyze_duration
	data["ear_damage_base"] = ear_damage_base
	data["ear_damage_chance"] = ear_damage_chance
	data["blur_duration"] = blur_duration
	data["flashbang_pending"] = flashbang_pending
	
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)
	
	if "inner_range" in data: inner_range = data.inner_range
	if "outer_range" in data: outer_range = data.outer_range
	if "max_range" in data: max_range = data.max_range
	if "mp_only" in data: mp_only = data.mp_only
	if "banglet" in data: banglet = data.banglet
	if "flash_duration" in data: flash_duration = data.flash_duration
	if "stun_duration_base" in data: stun_duration_base = data.stun_duration_base
	if "paralyze_duration" in data: paralyze_duration = data.paralyze_duration
	if "ear_damage_base" in data: ear_damage_base = data.ear_damage_base
	if "ear_damage_chance" in data: ear_damage_chance = data.ear_damage_chance
	if "blur_duration" in data: blur_duration = data.blur_duration
	if "flashbang_pending" in data: flashbang_pending = data.flashbang_pending
