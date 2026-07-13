namespace GodotStation.Core.Subsystems;

public enum SubsystemThreadAffinity
{
    // Ticks on the main thread, in priority order. Required for anything that
    // touches the scene tree / Godot nodes directly.
    MainThread,

    // Ticks on its own dedicated background thread. For subsystems that do
    // sustained pure computation (e.g. pathfinding) and want a stable thread
    // rather than sharing a pool.
    Worker,

    // Ticks via the shared ThreadPool. For bursty/occasional background work.
    WorkerPool,
}

public interface IGameSubsystem
{
    string Name { get; }
    double TickIntervalSeconds { get; }
    SubsystemThreadAffinity ThreadAffinity { get; }

    // Lower runs first among MainThread subsystems within the same frame.
    int Priority { get; }

    void Initialize();
    void Tick(double delta);
    void Shutdown();
}
