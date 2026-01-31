## Made By Ahmed GD
class_name SimpleStateMachine

## Emits when a state changes: Call for separated actions like animation for example
signal state_changed(from: int, to: int)

## called when a timed state completed 
signal state_timeout(id: int)

## the states store dictionary
var states: Dictionary[int, State] = { }

## stores global transitions: transition from any state to specific state
var global_transitions: Array[Transition] = []

var current_state: State

var initial_id: int = -1
var previous_id: int = -1

## how long we have been in that state ?
var state_time: float = 0.0

## Locks/unlocks the state machine to prevent transitions.
## When locked, no automatic or manual transitions can occur.
## Important note: state.exit() doesn't work while locked is true if so, consider using state.on_timeout() instead
var locked: bool

var has_previous_state: bool:
	get: return previous_id != -1

## Call it after adding states and transitions "Must be called"
func start() -> void:
	if initial_id == -1:
		push_error("invalid initial state id, call set_initial_state() first")
		return
	transition_to(initial_id, true)

## Use to set a custom initial state to begin with
func set_initial_state(id: int) -> void:
	if !states.has(id):
		push_error("invalid state id: %s" % id)
		return
	initial_id = id

## Called in the physics_process() method to update current state transitions & its custom update method
func update_states(delta: float) -> void:
	if current_state == null:
		return
	_call_safe(current_state.update, delta)
	state_time += delta
	
	if locked:
		return
	
	if !_state_timeout():
		_update_transitions(global_transitions)
		_update_transitions(current_state.transitions)

## Call it to add new states with enter, exit, update, timeout methods
## [codeblock]
## func _ready() -> void:
##    # first added state is default initial state 
##    # unless you call set_initial_state()
##    state_machine.add_state(State.Hurt)\
##        .on_enter(func(): pass)\
##        .on_exit(func(): pass)\
##        .on_exit(func(): pass)\
##        .on_update(func(delta: float): pass)\
##        .timeout_after(1.0, State.IDLE)
## [/codeblock]
func add_state(id: int) -> State:
	var state = State.new(id)
	states[id] = state
	return state

## Can be used to auto check conditions instead of writing it in the update method.
## Imprtant note: transitions updates based on its order -> higher = first.
## Global transitions are checked before normal transitions
## [codeblock]
## func _ready() -> void:
##    # updates first
##    state_machine.add_transition(State.IDLE, State.RUN)\
##        .on_condition(func(): return x != 0) 
##    # updates after the one above
##    state_machine.add_transition(State.IDLE, State.JUMP)\
##        .on_condition(func(): return can_jump)
##    # updates before all of the normal transitions
##    state_machine.add_global_transition(State.DEATH)\
##        .on_condition(func(): return health <= 0)
## [/codeblock]
func add_transition(from: int, to: int) -> Transition:
	return states[from].add_transition(to)

## the same as add_transition() but it allows us to transition from any state to a specific state
func add_global_transition(to: int) -> Transition:
	var transition: Transition = Transition.new(-1, to)
	global_transitions.append(transition)
	
	return transition

## Can be used to transition manually between states.
## Recommended: Use transitions instead { add_transition() & add_global_transition() } in the ready method
func transition_to(id: int, bypass_exit: bool = false) -> bool:
	if !states.has(id):
		push_error("Invalid state id")
		return false
	
	if locked:
		return false
	
	if !bypass_exit && has_previous_state:
		_call_safe(current_state.exit)
	
	if current_state != null:
		previous_id = current_state.id
	
	current_state = states[id]
	state_time = 0.0
	_call_safe(current_state.enter)
	state_changed.emit(previous_id, current_state.id)
	
	return true

## Is used to call state callables without throwing errors
func _call_safe(callable: Callable, ...args: Array) -> void:
	if !callable.is_valid():
		return
	
	if args.is_empty(): callable.call()
	else: callable.callv(args)

## Updates current state transitions based on its condition
## if condition returns true -> transition_to(transition.to)
func _update_transitions(transitions: Array[Transition]) -> void:
	for transition: Transition in transitions:
		if transition.condition.is_valid() && transition.condition.call():
			transition_to(transition.to)
			return

## Early transition from current state if it has a timeout
func _state_timeout() -> bool:
	if current_state.timeout == -1 || state_time < current_state.timeout:
		return false
	
	var from_id: int = current_state.id
	var timeout_id: int = current_state.timeout_id
	
	if !states.has(timeout_id):
		push_error("Invalid timeout state id: %s" % timeout_id)
		return false
	
	_call_safe(current_state.timeout_callback)
	transition_to(timeout_id)
	state_timeout.emit(from_id)
	
	return true

## The state class which is used to specify what state we are actually in right now
## Contains essential methods like enter, exit & update(delta) methods
class State:
	var id: int
	
	var update: Callable
	var enter: Callable
	var exit: Callable
	var timeout_callback: Callable
	
	var transitions: Array[Transition] = []
	
	## if timeout is grater than 0.0, state will timeout automatically
	var timeout: float = -1.0
	var timeout_id: int
	
	func _init(new_id: int) -> void:
		id = new_id
	
	func on_update(callback: Callable) -> State:
		update = callback
		return self
	
	func on_enter(callback: Callable) -> State:
		enter = callback
		return self
	
	func on_exit(callback: Callable) -> State:
		exit = callback
		return self
	
	func on_timeout(callback: Callable) -> State:
		timeout_callback = callback
		return self
	
	func timeout_after(duration: float, to: int) -> State:
		timeout = max(0, duration)
		timeout_id = to
		return self
	
	## internal use, don't call it
	## use state_machine.add_transition() instead.
	func add_transition(to: int) -> Transition:
		var transition: Transition = Transition.new(id, to)
		transitions.append(transition)
		return transition

## transition class: checks conditions instead of writing it in the update method
class Transition:
	var from: int
	var to: int
	
	var condition: Callable
	
	func _init(from_id: int, to_id: int) -> void:
		from = from_id
		to = to_id
	
	func on_condition(method: Callable) -> Transition:
		condition = method
		return self











