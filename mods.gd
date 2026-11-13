extends RefCounted
## Ship modification definitions. Stations offer 2 random ones; the ship has 2 slots.

const MODS := {
	"thruster": {
		"name": "Bigger Thruster",
		"desc": "+25% forward speed. Score and levels go faster. Stacks with boost.",
		"color": Color(1.0, 0.55, 0.2),
	},
	"rcs": {
		"name": "RCS Jets",
		"desc": "+35% side-to-side speed and agility.",
		"color": Color(0.35, 0.8, 1.0),
	},
	"radar": {
		"name": "Radar",
		"desc": "Shows incoming asteroids at the top of the window before they appear.",
		"color": Color(0.4, 1.0, 0.55),
	},
	"hull": {
		"name": "Reinforced Hull",
		"desc": "Max hull +50% (up to 150%).",
		"color": Color(0.75, 0.78, 0.9),
	},
	"healing": {
		"name": "Healing Panel",
		"desc": "Slowly repairs the hull over time.",
		"color": Color(0.45, 1.0, 0.7),
	},
	"missile": {
		"name": "Missile Pod",
		"desc": "5 homing missiles that hit the nearest asteroid. Reloads at every station.",
		"color": Color(1.0, 0.4, 0.35),
	},
}

## Effect strengths.
const THRUSTER_SPEED := 1.25
const RCS_AGILITY := 1.35
const HULL_BONUS := 0.5
const HEAL_PER_SECOND := 0.015
## Missiles per load (refilled automatically every time you dock), and the short delay
## between shots so they can't all be fired in one instant.
const MISSILE_AMMO := 5
const MISSILE_COOLDOWN := 0.5
const MISSILE_SCORE := 25.0
## How far above the window the radar can see (pixels). Asteroids spawn this far up.
const RADAR_RANGE := 260.0


## Two different random mods the ship doesn't already have.
static func random_offer(installed: Array) -> Array[String]:
	var pool: Array[String] = []
	for id in MODS.keys():
		if not installed.has(id):
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, 2)
