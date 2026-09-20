extends RefCounted
class_name MenuSawChaseState

## Menu-only authority. Z decreases toward the front of the preview belt.
enum Phase {WAITING, CHASING, CATCHING, RETURNING, RESPAWNING, GRACE}
const HOME_Z := SawDockPresentation.MENU_Z
const FOLLOW_DISTANCE := 5.0
const SAFE_GAP := 1.25 # Gap from the player's body to the front blade edge.
const SPEED := 2.0
const RETURN_SPEED := 2.5
const CATCH_SECONDS := SawChaseState.CUT_SCATTER_DELAY + .60
var phase := Phase.WAITING
var local_z := HOME_Z
var previous_z := HOME_Z
var travel := 0.0
var velocity := 0.0
var clock := 0.0
var victim_mask := 0
var contact := SawChaseState.new()

func reset() -> void:
	phase=Phase.WAITING; local_z=HOME_Z; previous_z=HOME_Z
	travel=0.0; velocity=0.0; clock=0.0; victim_mask=0

func advance(dt: float, ready: bool, leader: float, victims_landed: bool, rear: float=-INF) -> void:
	previous_z=local_z; velocity=0.0
	if dt<=0.0: return
	if phase==Phase.WAITING:
		if not ready:return
		phase=Phase.CHASING
	clock+=dt
	match phase:
		Phase.CHASING:
			if is_finite(leader):
				var target := leader+FOLLOW_DISTANCE+SawChaseState.BLADE_RADIUS
				if is_finite(rear):
					target=maxf(target,rear+SawChaseState.BLADE_RADIUS+QuizGameState.PLAYER_BODY_RADIUS+SAFE_GAP)
				local_z=move_toward(local_z,minf(local_z,target),SPEED*dt)
		Phase.CATCHING:
			if clock>=CATCH_SECONDS:phase=Phase.RETURNING;clock=0.0
		Phase.RETURNING:
			local_z=move_toward(local_z,HOME_Z,RETURN_SPEED*dt)
			if is_equal_approx(local_z,HOME_Z):phase=Phase.RESPAWNING;clock=0.0
		Phase.RESPAWNING:
			if victims_landed:phase=Phase.GRACE;clock=0.0
		Phase.GRACE:
			if clock>=2.0:phase=Phase.CHASING;clock=0.0;victim_mask=0
	velocity=(local_z-previous_z)/dt
	travel+=local_z-previous_z

func hit(from: Vector2, to: Vector2) -> bool:
	if phase!=Phase.CHASING:return false
	contact.local_z=local_z
	return contact.swept_contact(from,to,previous_z,QuizGameState.PLAYER_BODY_RADIUS)

func catch_players(mask: int) -> void:
	if phase!=Phase.CHASING or mask==0:return
	victim_mask=mask;phase=Phase.CATCHING;clock=0.0;velocity=0.0

func can_respawn(index: int) -> bool:
	return victim_mask & (1<<(index-1)) == 0 or phase in [Phase.RESPAWNING,Phase.GRACE,Phase.CHASING]
