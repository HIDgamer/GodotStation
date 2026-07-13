using Godot;
using GodotStation.Game.Mobs;

namespace GodotStation.Game.Interaction;

// go_prone key -> MobStateSystem.SetState, ported from the old prototype
// (its own original code). Connection rebuild: IMobSystem -> IMobComponent;
// the old prototype's RPC dispatch resolved the target mob by searching a
// "World" group for a node named after the peer id - PlayerMob's node tree
// is identical across peers (see GameRoot.SpawnPlayerRpc), so a plain
// node-path RPC targeting this component directly works, same pattern
// PlayerMob's own Hud* verbs use. ToggleRest (Standing<->Sleeping) wasn't
// wired to any input in the old version either - left out entirely rather
// than ported unreachable.
public partial class StateController : Node, IMobComponent
{
    private PlayerMob? _owner;
    private MobStateSystem? _states;

    public void Initialize(Mob mob)
    {
        _owner = mob as PlayerMob;
        _states = mob.GetMobComponent<MobStateSystem>();
    }

    public void Cleanup() { }

    public override void _Input(InputEvent e)
    {
        if (_owner == null || Multiplayer.GetUniqueId() != _owner.OwnerPeerId) return;

        if (e.IsActionPressed("go_prone")) TogglePosture();
    }

    private void TogglePosture()
    {
        if (Multiplayer.IsServer()) DoTogglePosture();
        else RpcId(1, nameof(ServerTogglePosture));
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void ServerTogglePosture()
    {
        if (!Multiplayer.IsServer()) return;
        DoTogglePosture();
    }

    private void DoTogglePosture()
    {
        if (_states == null) return;

        if (_states.State == MobState.Prone) _states.SetState(MobState.Standing);
        else if (_states.State == MobState.Standing) _states.SetState(MobState.Prone);
    }
}
