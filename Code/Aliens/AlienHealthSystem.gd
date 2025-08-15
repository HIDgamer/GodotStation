extends HealthSystem
class_name AlienHealthSystem

const ACID_SPRAY_RADIUS: float = 64.0
const ACID_DAMAGE_PER_SECOND: float = 5.0
const ACID_DURATION: float = 10.0
const ACID_POOLS_MAX: int = 5

var acid_pools: Array = []
var acid_spray_enabled: bool = true
var acid_spray_chance: float = 0.8

var controller = null
var world = null
var sensory_system = null

func _ready():
	super._ready()
	# Override some human-specific defaults
	blood_type = "ACID"
	is_synthetic = false
	
	# Aliens don't use human medical items
	armor = {
		"melee": 15, "bullet": 20, "laser": 5, "energy": 10,
		"bomb": 30, "bio": 50, "rad": 40, "fire": 20, "acid": 80
	}
	
	controller = get_parent()
	world = controller.get_parent()
	sensory_system = world.get_node_or_null("SensorySystem")

func apply_damage(amount: float, damage_type: int, penetration: float = 0, zone: String = "", source = null) -> float:
	var actual_damage = super.apply_damage(amount, damage_type, penetration, zone, source)
	
	if actual_damage > 5.0 and acid_spray_enabled:
		trigger_acid_spray(actual_damage, source)
	
	return actual_damage

func trigger_acid_spray(damage_amount: float, source = null):
	if not _is_authority() or not controller:
		return
	
	if randf() > acid_spray_chance:
		return
	
	var spray_positions = calculate_acid_spray_positions(damage_amount)
	
	for pos in spray_positions:
		create_acid_pool(pos, damage_amount * 0.3)
	
	sync_acid_spray.rpc(spray_positions, damage_amount * 0.3)
	
	if source and source != controller:
		apply_acid_contact_damage(source, damage_amount * 0.2)

func calculate_acid_spray_positions(damage_amount: float) -> Array:
	var positions = []
	var spray_count = min(int(damage_amount / 10) + 1, 4)
	var entity_pos = controller.position
	
	for i in range(spray_count):
		var angle = randf() * 2 * PI
		var distance = randf() * ACID_SPRAY_RADIUS
		var spray_pos = entity_pos + Vector2(cos(angle), sin(angle)) * distance
		positions.append(spray_pos)
	
	return positions

func create_acid_pool(position: Vector2, acid_strength: float):
	if acid_pools.size() >= ACID_POOLS_MAX:
		remove_oldest_acid_pool()
	
	var acid_pool = {
		"position": position,
		"strength": acid_strength,
		"duration": ACID_DURATION,
		"creation_time": Time.get_ticks_msec() / 1000.0
	}
	
	acid_pools.append(acid_pool)
	
	if world and world.has_method("spawn_acid_pool"):
		world.spawn_acid_pool(position, acid_strength, ACID_DURATION)

func remove_oldest_acid_pool():
	if acid_pools.size() > 0:
		var oldest_pool = acid_pools[0]
		acid_pools.erase(oldest_pool)
		
		if world and world.has_method("remove_acid_pool"):
			world.remove_acid_pool(oldest_pool.position)

func apply_acid_contact_damage(target: Node, acid_damage: float):
	if not target or not target.has_method("take_damage"):
		return
	
	target.take_damage(acid_damage, DamageType.BURN)
	
	if target.has_method("add_status_effect"):
		target.add_status_effect("acid_burn", 5.0, acid_damage / 5.0)
	
	if sensory_system:
		var target_name = get_entity_name(target)
		sensory_system.display_message("Acid splashes onto " + target_name + "!")

func process_acid_pools(delta: float):
	var current_time = Time.get_ticks_msec() / 1000.0
	var pools_to_remove = []
	
	for i in range(acid_pools.size()):
		var pool = acid_pools[i]
		var elapsed = current_time - pool.creation_time
		
		if elapsed >= pool.duration:
			pools_to_remove.append(i)
		else:
			check_acid_pool_damage(pool)
	
	# Remove expired pools in reverse order
	for i in range(pools_to_remove.size() - 1, -1, -1):
		var pool_index = pools_to_remove[i]
		var pool = acid_pools[pool_index]
		acid_pools.remove_at(pool_index)
		
		if world and world.has_method("remove_acid_pool"):
			world.remove_acid_pool(pool.position)

func check_acid_pool_damage(pool: Dictionary):
	if not world or not world.tile_occupancy_system:
		return
	
	var tile_pos = world_to_tile(pool.position)
	var entities = world.tile_occupancy_system.get_entities_at(tile_pos, controller.current_z_level)
	
	for entity in entities:
		if entity != controller and entity.has_method("take_damage"):
			apply_acid_pool_damage(entity, pool.strength)

func apply_acid_pool_damage(target: Node, acid_strength: float):
	var damage = ACID_DAMAGE_PER_SECOND * acid_strength * get_process_delta_time()
	
	target.take_damage(damage, DamageType.BURN)
	
	if target.has_method("add_status_effect"):
		target.add_status_effect("acid_burn", 2.0, 1.0)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / 32), int(world_pos.y / 32))

func get_entity_name(entity: Node) -> String:
	if "entity_name" in entity and entity.entity_name != "":
		return entity.entity_name
	elif "name" in entity:
		return entity.name
	else:
		return "something"

func _process(delta: float):
	super._process(delta)
	
	if _is_authority() and acid_pools.size() > 0:
		process_acid_pools(delta)

# Override human-specific medical functions
func start_cpr(performer: Node) -> bool:
	if performer and performer.has_method("display_message"):
		performer.display_message("CPR has no effect on this creature!")
	return false

func apply_defibrillation(power: float = 1.0) -> bool:
	return false

# Aliens don't use human medical items
func can_use_medical_item(item: Node) -> bool:
	return false

@rpc("any_peer", "call_local", "reliable")
func sync_acid_spray(positions: Array, acid_strength: float):
	if _is_authority():
		return
	
	for pos in positions:
		create_acid_pool(pos, acid_strength)
	
	if audio_system:
		audio_system.play_positioned_sound("acid_spray", controller.position, 0.7)
