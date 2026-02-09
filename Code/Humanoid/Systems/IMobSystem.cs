/// Interface for mob systems to be detected and piloted by Mob.cs
public interface IMobSystem
{
    /// Initialize the system with the mob it's attached to
    void Init(Mob mob);
    
    /// Process method called every frame
    void Process(double delta);
    
    /// Cleanup method called when the system is being removed
    void Cleanup();
}