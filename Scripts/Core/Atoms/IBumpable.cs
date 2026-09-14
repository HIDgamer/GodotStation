namespace GodotStation.Core.Atoms;

// Optional contract for an IDenseStructure that reacts to being walked into
// (ucfss13's own airlock bump-to-open behavior) - implemented by Door.
// Structures that don't want bump behavior (an inert crate, say) simply
// don't implement it.
public interface IBumpable
{
    void OnBumped();
}
