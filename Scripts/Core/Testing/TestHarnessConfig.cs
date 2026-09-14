using Godot;

namespace GodotStation.Core.Testing;

// Plain data holder for cmdline-driven automated test scenarios (see
// Tools/multiplayer_tests/). Populated by MainMenu.gd's _parse_args() at
// startup, read later by GameRoot/PlayerMob once the relevant moment
// (hosting succeeded, this peer's own mob spawned) actually arrives - no
// live control channel, just startup flags + timers. Always compiled in,
// same convention as PlayerMob's RequestDebugDamage: harmless when the
// flags are never passed, no build-time gating needed.
public partial class TestHarnessConfig : Node
{
    public bool AutoStartRound { get; set; }
    public float AutoDropAfterSpawnSeconds { get; set; }
}
