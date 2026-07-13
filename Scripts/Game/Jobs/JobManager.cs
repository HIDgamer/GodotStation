using System.Collections.Generic;
using Godot;

namespace GodotStation.Game.Jobs;

public sealed class JobSlot
{
    public required string JobName;
    public required string Department;
    public int MaxSlots;
    public int FilledSlots;
    public int Priority;

    public int AvailableSlots => MaxSlots - FilledSlots;
    public bool IsFull => FilledSlots >= MaxSlots;
}

// Job/role roster + per-peer assignment, ported from the old prototype.
// Connection rebuild: the roster is self-contained (the old version pulled
// available_roles from PreferenceManager.gd - that dependency returns with
// the preferences port in P2, this data is identical to what it held);
// server-authoritative like everything else - mutators no-op off-server,
// GameRoot consults it during spawn.
public partial class JobManager : Node
{
    [Signal] public delegate void JobAvailabilityChangedEventHandler();

    public const string FallbackJob = "Rifleman";

    private readonly Dictionary<string, JobSlot> _jobSlots = new();
    private readonly Dictionary<long, string> _peerAssignments = new();

    private static readonly Dictionary<string, string[]> DepartmentRoles = new()
    {
        ["Command"] = new[] { "Commanding Officer", "Executive Officer", "Staff Officer", "Chief MP" },
        ["Security / Military Police"] = new[] { "Military Warden", "Military Police", "Auxiliary Support Officer", "Senior Enlisted Advisor (GySGT)", "Intelligence Officer" },
        ["Auxiliary"] = new[] { "Gunship Pilot", "Dropship Pilot", "Dropship Crew Chief", "Tank Crew" },
        ["Synthetic"] = new[] { "Synthetic", "Working Joe (JOE)" },
        ["Support / Civilian"] = new[] { "Corporate Liaison", "Combat Correspondent (Civ)", "Mess Technician", "Chef", "Chief Engineer", "Ordnance Technician", "Maintenance Technician" },
        ["Requisition / Cargo"] = new[] { "Quartermaster", "Cargo Technician" },
        ["Medical"] = new[] { "Chief Medical Officer", "Researcher", "Doctor (Doc)", "Field Doctor", "Nurse" },
        ["Marines / Combat"] = new[] { "Squad Leader", "Fireteam Leader", "Weapons Specialist", "Smartgunner", "Hospital Corpsman", "Combat Technician", "Rifleman" },
    };

    private static readonly Dictionary<string, int> RoleMaxSlots = new()
    {
        ["Commanding Officer"] = 1, ["Executive Officer"] = 1, ["Staff Officer"] = 2, ["Chief MP"] = 1,
        ["Military Warden"] = 1, ["Military Police"] = 4, ["Auxiliary Support Officer"] = 3,
        ["Senior Enlisted Advisor (GySGT)"] = 1, ["Intelligence Officer"] = 1,
        ["Gunship Pilot"] = 1, ["Dropship Pilot"] = 2, ["Dropship Crew Chief"] = 2, ["Tank Crew"] = 3,
        ["Synthetic"] = 1, ["Working Joe (JOE)"] = 3,
        ["Corporate Liaison"] = 1, ["Combat Correspondent (Civ)"] = 1, ["Mess Technician"] = 2, ["Chef"] = 1,
        ["Chief Engineer"] = 1, ["Ordnance Technician"] = 2, ["Maintenance Technician"] = 3,
        ["Quartermaster"] = 1, ["Cargo Technician"] = 3,
        ["Chief Medical Officer"] = 1, ["Researcher"] = 2, ["Doctor (Doc)"] = 4, ["Field Doctor"] = 4, ["Nurse"] = 3,
        ["Squad Leader"] = 4, ["Fireteam Leader"] = 8, ["Weapons Specialist"] = 6, ["Smartgunner"] = 4,
        ["Hospital Corpsman"] = 6, ["Combat Technician"] = 6, ["Rifleman"] = 999,
    };

    private static readonly Dictionary<string, int> DepartmentPriority = new()
    {
        ["Command"] = 100, ["Security / Military Police"] = 80, ["Auxiliary"] = 70, ["Synthetic"] = 65,
        ["Medical"] = 60, ["Support / Civilian"] = 50, ["Requisition / Cargo"] = 45, ["Marines / Combat"] = 30,
    };

    public override void _Ready()
    {
        foreach (var (department, roles) in DepartmentRoles)
        {
            var priority = DepartmentPriority.GetValueOrDefault(department, 10);
            foreach (var role in roles)
            {
                _jobSlots[role] = new JobSlot
                {
                    JobName = role,
                    Department = department,
                    MaxSlots = RoleMaxSlots.GetValueOrDefault(role, 3),
                    Priority = priority,
                };
            }
        }
    }

    public IReadOnlyDictionary<string, JobSlot> Jobs => _jobSlots;

    public string? GetAssignment(long peerId) => _peerAssignments.GetValueOrDefault(peerId);

    public bool AssignJob(long peerId, string jobName)
    {
        if (!Multiplayer.IsServer()) return false;
        if (!_jobSlots.TryGetValue(jobName, out var job) || job.IsFull) return false;

        ClearAssignment(peerId);
        job.FilledSlots++;
        _peerAssignments[peerId] = jobName;

        EmitSignal(SignalName.JobAvailabilityChanged);
        return true;
    }

    // Auto-assign fallback used until the lobby job-selection UI arrives
    // (P2): everyone who didn't pick becomes a Rifleman - it's the one role
    // with effectively unlimited slots, matching the old roster.
    public string AssignFallback(long peerId)
    {
        if (GetAssignment(peerId) is { } existing) return existing;
        AssignJob(peerId, FallbackJob);
        return FallbackJob;
    }

    public void ClearAssignment(long peerId)
    {
        if (!Multiplayer.IsServer()) return;
        if (!_peerAssignments.TryGetValue(peerId, out var oldJob)) return;

        if (_jobSlots.TryGetValue(oldJob, out var slot)) slot.FilledSlots--;
        _peerAssignments.Remove(peerId);
        EmitSignal(SignalName.JobAvailabilityChanged);
    }
}
