# Simple State Machine for Godot 4.x

A lightweight, efficient, and easy-to-use finite state machine for Godot 4.x

## Features

- Simple fluent API with method chaining
- State callbacks: `on_enter()`, `on_exit()`, `on_update()`, `on_timeout()`
- Condition-based transitions
- Global transitions (from any state)
- Automatic timeout transitions
- Lock system for cutscenes/stuns
- Signals for external observation

## Installation

1. Download `simple_state_machine.gd`
2. Place it in your project
3. Start using it!

## Full Example
```gdscript
extends CharacterBody2D
class_name Player

enum State { 
	IDLE, RUN, HURT, DEATH
}

@export_group("References")
@export var animation_player: AnimationPlayer

@export_group("Movement")
@export var max_speed: float = 100.0
@export var acceleration: float = 40.0

@export_group("Knockback")
@export var kb_force: float = 150.0

@export_group("States")
@export var death_duration: float = 2.0
@export var hurt_duration: float = 0.15

var state_machine: SimpleStateMachine = SimpleStateMachine.new()

var move_direction: Vector2
var knockback_dir: Vector2 = Vector2.UP

var current_health: float = 100.0
var damaged: bool

func _ready() -> void:
	# connect to state_changed singal in order to call on_state_changed() once state changes
	state_machine.state_changed.connect(on_state_changed)
	
	# initializing states
	state_machine.add_state(State.IDLE).on_update(update_idle)
	state_machine.add_state(State.RUN).on_update(update_run)
	# hurt state: returns to idle after taking damage
	state_machine.add_state(State.HURT).on_enter(enter_hurt).timeout_after(hurt_duration, State.IDLE)
	# death state: locks transitions and reloads scene on timeout
	state_machine.add_state(State.DEATH).on_update(update_death).on_enter(enter_death)\
		.on_timeout(on_death_timeout).timeout_after(death_duration, State.IDLE)
	
	# transition from idle to run when player begins to move (while he's idle)
	state_machine.add_transition(State.IDLE, State.RUN).on_condition(func(): return move_direction.length() != 0.0)
	# return to idle again if player stopped moving (while he is running)
	state_machine.add_transition(State.RUN, State.IDLE).on_condition(func(): return move_direction.length() == 0.0)
	
	# death transition evaluates before hurt transition (priority sorting) -> higher = first
	# transition to death state from any state if current health is zero
	state_machine.add_global_transition(State.DEATH).on_condition(func(): return current_health <= 0.0)
	# checked after death to prevent overlapping !
	state_machine.add_global_transition(State.HURT).on_condition(func(): return damaged)
	
	# the state player will begin with
	state_machine.set_initial_state(State.IDLE)
	# start the state machine (must be called after initializing)
	state_machine.start()

func _physics_process(delta: float) -> void:
	move_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	# update current state & current transitions
	state_machine.update_states(delta)
	
	move_and_slide()

func accelerate(direction: Vector2, delta: float) -> void:
	var smoothing: float = 1.0 - exp(-acceleration * delta)
	var desired: Vector2 = direction.normalized() * max_speed
	
	velocity = velocity.lerp(desired, smoothing)

# Called when a state changes
# usually used to collect animations in one place and do external tasks
# that have nothing to do with state methods (update, enter, exit)
func on_state_changed(previous_id: int, current_id: int) -> void:
	# use match statement for better code structure.
	# or even simpler (if the animation name is the same as state)
	var current_state_name: String = State.keys()[current_id].to_lower()
	animation_player.play(current_state_name)

#region Idle State
func update_idle(delta: float) -> void:
	# decelerate until player stops moving (smooth)
	accelerate(Vector2.ZERO, delta)
#endregion

#region Run State
func update_run(delta: float) -> void:
	# move towards the move direction (left, right, up, down)
	accelerate(move_direction, delta)
#endregion

#region Hurt State
func enter_hurt() -> void:
	# apply knockback effect
	velocity += knockback_dir.normalized() * kb_force
	damaged = false # reset damaged flag
#endregion

#region Death State
func enter_death() -> void:
	# lock state machine so player can't avoid death
	state_machine.locked = true

func update_death(delta: float) -> void:
	# stop moving
	velocity = Vector2.ZERO

func exit_death() -> void:
	# exit doesn't work here since locked is true
	# consider using state.on_timeout() instead
	pass

func on_death_timeout() -> void:
	# reload the game after player dies
	get_tree().reload_current_scene()
#endregion
```

## API Reference

### Core Methods

#### `start() -> void`
Initializes and starts the state machine execution. This method transitions to the initial state and must be called after all states have been added and the initial state has been set. Calling this before setting an initial state will result in an error.

---

#### `set_initial_state(id: int) -> void`
Designates which state the machine should begin in when started. The state ID must correspond to a state that has already been added to the machine. If the provided ID doesn't exist, an error will be logged.

**Parameters:**
- `id` - The unique identifier for the starting state

---

#### `update_states(delta: float) -> void`
The main update loop for the state machine. This should be called every frame from either `_process()` or `_physics_process()`. It executes the current state's update callback, increments the state timer, and evaluates all transitions in priority order: timeouts first, then global transitions, then state-specific transitions. If the machine is locked, only the update callback runs.

**Parameters:**
- `delta` - The time elapsed since the last frame in seconds

---

#### `add_state(id: int) -> State`
Creates a new state and registers it with the state machine. Returns the state object, allowing you to chain callback methods immediately. Each state must have a unique ID, typically from an enum.

**Parameters:**
- `id` - Unique identifier for this state

**Returns:** The newly created State object for method chaining

---

#### `add_transition(from: int, to: int) -> Transition`
Creates a conditional transition between two specific states. The transition will only trigger when its condition callback returns true. Transitions are evaluated in the order they're added, so earlier transitions have higher priority.

**Parameters:**
- `from` - The state this transition originates from
- `to` - The state this transition leads to

**Returns:** The Transition object for adding a condition callback

---

#### `add_global_transition(to: int) -> Transition`
Creates a conditional transition that can trigger from any state, not just a specific one. These are particularly useful for events that should interrupt normal flow, such as death, stuns, or cutscenes. Global transitions are always checked before state-specific transitions.

**Parameters:**
- `to` - The destination state

**Returns:** The Transition object for adding a condition callback

---

#### `transition_to(id: int, bypass_exit: bool = false) -> bool`
Forces an immediate transition to the specified state, bypassing normal transition conditions. This is useful for event-driven state changes that don't fit the condition model. By default, this will call the current state's exit callback, but this can be bypassed with the second parameter. Manual transitions are blocked when the machine is locked.

**Parameters:**
- `id` - The target state identifier
- `bypass_exit` - When true, skips calling the current state's exit callback

**Returns:** True if the transition succeeded, false if the state doesn't exist or the machine is locked

---

### State Class Methods

All state methods return the state object itself, enabling fluent method chaining.

#### `on_enter(callback: Callable) -> State`
Registers a function to execute once when transitioning into this state. This is called after the state has become active but before any update logic runs. Common uses include playing animations, resetting variables, or triggering one-time effects.

**Parameters:**
- `callback` - A function with no parameters and no return value

**Returns:** Self for method chaining

---

#### `on_exit(callback: Callable) -> State`
Registers a function to execute once when leaving this state. This is called before transitioning to the new state. Useful for cleanup tasks, stopping effects, or saving state information. Not called if the machine is locked or if the transition bypasses exit callbacks.

**Parameters:**
- `callback` - A function with no parameters and no return value

**Returns:** Self for method chaining

---

#### `on_update(callback: Callable) -> State`
Registers a function to execute every frame while this state is active. This is where the main logic for the state should live. The callback receives delta time as a parameter.

**Parameters:**
- `callback` - A function that accepts a single float parameter (delta time)

**Returns:** Self for method chaining

---

#### `on_timeout(callback: Callable) -> State`
Registers a function to execute when the state's timeout duration expires, but before the timeout transition occurs. This is called after the timeout duration has elapsed and before transitioning to the timeout target state. Useful for triggering completion effects or finalizing state-specific logic.

**Parameters:**
- `callback` - A function with no parameters and no return value

**Returns:** Self for method chaining

---

#### `timeout_after(duration: float, to: int) -> State`
Configures this state to automatically transition to another state after a specified duration. The timer starts when entering the state and resets on each transition. Timeout transitions have the highest priority and are checked before all other transitions.

**Parameters:**
- `duration` - Time in seconds before the automatic transition
- `to` - The state ID to transition to when time expires

**Returns:** Self for method chaining

---

### Transition Class Methods

#### `on_condition(callback: Callable) -> Transition`
Registers the condition function that determines when this transition should activate. The function is evaluated every frame during the state machine update. When it returns true, the transition immediately triggers. The condition should be a pure function that returns a boolean value.

**Parameters:**
- `callback` - A function with no parameters that returns a boolean

**Returns:** Self for method chaining

---

### Properties

#### `locked: bool`
Controls whether the state machine allows any transitions. When set to true, all automatic transitions (from conditions and timeouts) and manual transitions are blocked. The current state's update callback continues to run. Useful for cutscenes, death states, stun effects, or any scenario where state should be frozen temporarily.

---

#### `state_time: float`
A read-only property that tracks how long the current state has been active, measured in seconds. Automatically resets to zero whenever a state transition occurs. Useful for implementing time-based behaviors within states, such as charging attacks or diminishing effects.

---

#### `current_state: State`
A read-only reference to the currently active state object. Provides access to the state's ID and other properties. Primarily used internally but can be useful for debugging or conditional logic based on the active state.

---

#### `previous_id: int`
A read-only property containing the ID of the state that was active before the current one. Set to -1 if there is no previous state (i.e., at the very start). Useful for implementing state-dependent behaviors or transitions that care about state history.

---

#### `has_previous_state: bool`
A read-only computed property that returns true if there was a state before the current one. Equivalent to checking if previous_id is not equal to -1, but more semantically clear.

---

### Signals

#### `state_changed(from: int, to: int)`
Emitted immediately after a state transition completes. The signal fires after the new state's enter callback has been called. The from parameter will be -1 when transitioning to the very first state.

**Parameters:**
- `from` - The ID of the previous state, or -1 if no previous state
- `to` - The ID of the newly active state

**Common uses:** Triggering animations, updating UI elements, playing sound effects, logging state changes for debugging

---

#### `state_timeout(id: int)`
Emitted when a state's timeout duration expires and the timeout transition completes. This signal fires after the state has already transitioned to its timeout target state, making it distinct from the on_timeout callback which fires before the transition.

**Parameters:**
- `id` - The ID of the state that timed out

**Common uses:** Tracking completion of timed actions, analytics, triggering follow-up effects after the timeout transition

---

## Execution Order

Understanding the order of operations helps avoid common mistakes:

**When transitioning to a new state:**
1. Timeout callback executes (if transitioning due to timeout)
2. Current state's exit callback executes (unless bypassed)
3. State machine switches to new state
4. State timer resets to zero
5. New state's enter callback executes
6. state_changed signal emits
7. state_timeout signal emits (if the transition was due to timeout)

**During each frame update:**
1. Current state's update callback executes
2. State timer increments
3. If locked, stop here
4. Check timeout transition
5. Check global transitions (in order added)
6. Check state-specific transitions (in order added)
7. First true condition triggers transition and stops checking

---

## Tips & Best Practices

**State Organization**
Always use enums for state IDs rather than magic numbers. This improves code readability, prevents typos, and enables IDE autocomplete. Name states as nouns that describe what the entity is doing.

**Transition Priority**
Remember that transitions are evaluated in the order they're added. Timeout transitions are always checked first, followed by global transitions, then state-specific transitions. Add critical interrupts (like death or stuns) as global transitions before less important ones.

**Signal Usage**
Connect to the state_changed signal for logic that's external to state behavior, such as animations or UI updates. Keep state-specific logic in the state callbacks themselves (enter, exit, update).

**Timeout States**
Use timeout transitions for temporary states that should automatically end, such as attack animations, hurt states, or cooldowns. This is cleaner than manually checking timers in update callbacks.

**Locking Mechanism**
Lock the state machine during uninterruptible sequences like cutscenes or death. Remember that locking prevents all transitions but continues running the current state's update callback.

**State Time Tracking**
Leverage the state_time property for implementing time-based mechanics within states, such as charge-up attacks, combo windows, or grace periods. It's more reliable than maintaining separate timers.

**Initialization Order**
Always follow this sequence: create states, add transitions, set initial state, connect signals, then call start(). Deviating from this order can cause errors or unexpected behavior.

**Condition Purity**
Transition conditions should be pure functions that only check state and return a boolean. Avoid side effects in conditions—those belong in enter, exit, or update callbacks.
