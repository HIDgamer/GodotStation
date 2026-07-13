namespace GodotStation.Game.Mobs;

// SS13's classic four-way intent selector - what "attacking" a tile actually
// does depends on this, not on a separate attack button per action.
public enum Intent
{
    Help,
    Disarm,
    Grab,
    Harm,
}
