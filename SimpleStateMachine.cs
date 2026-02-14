using Godot;
using System;
using System.Collections.Generic;

namespace Utilities.Logic;

public partial class SimpleStateMachine<T> : RefCounted where T : Enum
{
    public T CurrentStateId => currentState != null ? currentState.Id : default;
    public T PreviousId => previousId;
    public float StateTime => stateTime;
    public bool HasPreviousState => !previousId.Equals(default(T));

    public bool locked;

    public event Action<T, T> StateChanged;
    public event Action<T> StateTimeout;

    private readonly Dictionary<T, State<T>> states = new();
    private readonly List<Transition<T>> globalTransitions = new();

    private State<T> currentState;

    private T initialId;
    private T previousId;

    private float stateTime;

    private bool initialized;

    public void Start()
    {
        if (!initialized)
        {
            GD.PushError("invalid initial id, call SetInitialState() first");
            return;
        }
        TransitionTo(initialId, bypassExit: true);
    }

    public void SetInitialState(T id)
    {
        if (!states.ContainsKey(id))
        {
            GD.PushError($"invalid state id: {id}");
            return;
        }
        initialId = id;
        initialized = true;
    }

    public void UpdateStates(double delta)
    {
        float dt = (float)delta;

        if (currentState == null)
            return;
        currentState.Update?.Invoke(dt);
        stateTime += dt;

        if (locked)
            return;
        
        if (!OnStateTimeout())
        {
            UpdateTransitions(globalTransitions);
            UpdateTransitions(currentState.Transitions);
        }
    }

    public State<T> AddState(T id)
    {
        if (states.TryGetValue(id, out State<T> value))
            return value;

        var state = new State<T>(id);
        states[id] = state;

        return state;
    }

    public Transition<T> AddTransition(T from, T to)
    {
        return states[from].AddTransition(to);
    }

    public Transition<T> AddGlobalTransition(T to)
    {
        var transition = new Transition<T>(default, to);
        globalTransitions.Add(transition);

        return transition;
    }

    public bool TransitionTo(T id, bool bypassExit = false)
    {
        if (!states.ContainsKey(id))
        {
            GD.PushError("Invalid State Id");
            return false;
        }

        if (locked)
            return false;
        
        if (!bypassExit && currentState != null)
            currentState.Exit?.Invoke();
        
        if (currentState != null)
            previousId = currentState.Id;

        currentState = states[id];
        stateTime = 0f;
        currentState.Enter?.Invoke();

        StateChanged?.Invoke(previousId, currentState.Id);
        return true;
    }

    private void UpdateTransitions(IEnumerable<Transition<T>> transitions)
    {
        foreach (var transition in transitions)
        {
            if (!(transition.Guard?.Invoke(stateTime) ?? true))
                continue;
            
            if (transition.Condition?.Invoke(stateTime) ?? false)
            {
                transition.OnTransition?.Invoke();
                TransitionTo(transition.To);
                return;
            }
        }
    }

    private bool OnStateTimeout()
    {
        if (currentState.Timeout == -1f || stateTime < currentState.Timeout)
            return false;
        
        var fromId = currentState.Id;
        var timeoutId = currentState.TimeoutId;

        if (!states.ContainsKey(timeoutId))
        {
            GD.PushError($"Invalid timeout state id: {timeoutId}");
            return false;
        }

        currentState.TimeoutCallback?.Invoke();
        TransitionTo(timeoutId);
        StateTimeout?.Invoke(fromId);

        return true;
    }
}

public class State<T> where T : Enum
{
    public T Id { get; private set; }

    public Action<float> Update { get; private set; }
    public Action Enter { get; private set; }
    public Action Exit { get; private set; }

    public float Timeout { get; private set; }
    public T TimeoutId { get; private set; }
    public Action TimeoutCallback { get; private set; }

    public List<Transition<T>> Transitions { get; private set; }

    public State(T id)
    {
        Id = id;
        Timeout = -1f;

        Transitions = new();
    }

    public State<T> OnUpdate(Action<float> callback)
    {
        Update = callback;
        return this;
    }

    public State<T> OnEnter(Action callback)
    {
        Enter = callback;
        return this;
    }

    public State<T> OnExit(Action callback)
    {
        Exit = callback;
        return this;
    }

    public State<T> OnTimeout(Action callback)
    {
        TimeoutCallback = callback;
        return this;
    }

    public State<T> TimeoutAfter(float duration, T to)
    {
        Timeout = Mathf.Max(0f, duration);
        TimeoutId = to;
        return this;
    }

    internal Transition<T> AddTransition(T to)
    {
        var transition = new Transition<T>(Id, to);
        Transitions.Add(transition);
        return transition;
    }
}

public class Transition<T> where T : Enum
{
    public T From { get; private set;}
    public T To { get; private set; }
    
    public Predicate<float> Condition { get; private set; }
    public Predicate<float> Guard { get; private set; }
    
    public Action OnTransition { get; private set; }

    public Transition(T from, T to)
    {
        From = from;
        To = to;
    }

    public Transition<T> When(Predicate<float> condition)
    {
        Condition = condition;
        return this;
    }

    public Transition<T> IfOnly(Predicate<float> guard)
    {
        Guard = guard;
        return this;
    }

    public Transition<T> Do(Action callback)
    {
        OnTransition = callback;
        return this;
    }
}

