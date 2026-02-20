public interface IMobSystem
{
    void Init(Mob mob);
    
    void Process(double delta);
    
    void Cleanup();
}
