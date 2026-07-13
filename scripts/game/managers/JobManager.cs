using Godot;
using Godot.Collections;
using System.Linq;

public partial class JobSlot : GodotObject
{
	public string JobName { get; set; }
	public int MaxSlots { get; set; }
	public int FilledSlots { get; set; }
	public string Department { get; set; }
	public int Priority { get; set; }

	public int AvailableSlots => MaxSlots - FilledSlots;
	public bool IsFull => FilledSlots >= MaxSlots;

	public JobSlot()
	{
	}
}

public partial class JobManager : Node
{
	[Signal] public delegate void JobAvailabilityChangedEventHandler();

	private Dictionary<string, JobSlot> _jobSlots = new();
	private Dictionary<int, string> _peerAssignments = new();

	private static readonly System.Collections.Generic.Dictionary<string, int> _roleMaxSlots = new()
	{
		{ "Commanding Officer", 1 },
		{ "Executive Officer", 1 },
		{ "Staff Officer", 2 },
		{ "Chief MP", 1 },
		{ "Military Warden", 1 },
		{ "Military Police", 4 },
		{ "Auxiliary Support Officer", 3 },
		{ "Senior Enlisted Advisor (GySGT)", 1 },
		{ "Intelligence Officer", 1 },
		{ "Gunship Pilot", 1 },
		{ "Dropship Pilot", 2 },
		{ "Dropship Crew Chief", 2 },
		{ "Tank Crew", 3 },
		{ "Synthetic", 1 },
		{ "Working Joe (JOE)", 3 },
		{ "Corporate Liaison", 1 },
		{ "Combat Correspondent (Civ)", 1 },
		{ "Mess Technician", 2 },
		{ "Chef", 1 },
		{ "Chief Engineer", 1 },
		{ "Ordnance Technician", 2 },
		{ "Maintenance Technician", 3 },
		{ "Quartermaster", 1 },
		{ "Cargo Technician", 3 },
		{ "Chief Medical Officer", 1 },
		{ "Researcher", 2 },
		{ "Doctor (Doc)", 4 },
		{ "Field Doctor", 4 },
		{ "Nurse", 3 },
		{ "Squad Leader", 4 },
		{ "Fireteam Leader", 8 },
		{ "Weapons Specialist", 6 },
		{ "Smartgunner", 4 },
		{ "Hospital Corpsman", 6 },
		{ "Combat Technician", 6 },
		{ "Rifleman", 999 },
	};

	private static readonly System.Collections.Generic.Dictionary<string, int> _departmentPriority = new()
	{
		{ "Command", 100 },
		{ "Security / Military Police", 80 },
		{ "Auxiliary", 70 },
		{ "Synthetic", 65 },
		{ "Medical", 60 },
		{ "Support / Civilian", 50 },
		{ "Requisition / Cargo", 45 },
		{ "Marines / Combat", 30 },
	};

	public override void _Ready()
	{
		InitializeJobsFromPreferenceManager();
	}

	private void InitializeJobsFromPreferenceManager()
	{
		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (prefManager == null)
		{
			GD.PushError("JobManager: PreferenceManager not found, no jobs loaded.");
			return;
		}

		var availableRoles = (Dictionary)prefManager.Get("available_roles");
		if (availableRoles == null || availableRoles.Count == 0)
		{
			GD.PushError("JobManager: available_roles is empty.");
			return;
		}

		foreach (var deptKey in availableRoles.Keys)
		{
			string department = deptKey.ToString();
			var roles = (Godot.Collections.Array)availableRoles[deptKey];
			int deptPriority = _departmentPriority.ContainsKey(department) ? _departmentPriority[department] : 10;

			foreach (var roleObj in roles)
			{
				string roleName = roleObj.ToString();
				int maxSlots = _roleMaxSlots.ContainsKey(roleName) ? _roleMaxSlots[roleName] : 3;
				AddJob(roleName, maxSlots, department, deptPriority);
			}
		}
	}

	private void AddJob(string jobName, int maxSlots, string department, int priority)
	{
		_jobSlots[jobName] = new JobSlot
		{
			JobName = jobName,
			MaxSlots = maxSlots,
			FilledSlots = 0,
			Department = department,
			Priority = priority
		};
	}

	public bool AssignJob(int peerId, string jobName)
	{
		if (!_jobSlots.ContainsKey(jobName))
			return false;

		var job = _jobSlots[jobName];
		if (job.IsFull)
			return false;

		if (_peerAssignments.ContainsKey(peerId))
		{
			var oldJob = _peerAssignments[peerId];
			if (_jobSlots.ContainsKey(oldJob))
				_jobSlots[oldJob].FilledSlots--;
		}

		job.FilledSlots++;
		_peerAssignments[peerId] = jobName;

		EmitSignal(SignalName.JobAvailabilityChanged);
		return true;
	}

	public string AssignJobByPriority(int peerId, Dictionary rolePriorities)
	{
		var high = new System.Collections.Generic.List<string>();
		var medium = new System.Collections.Generic.List<string>();
		var low = new System.Collections.Generic.List<string>();

		foreach (var roleKey in rolePriorities.Keys)
		{
			string role = roleKey.ToString();
			string prio = rolePriorities[roleKey].ToString();
			switch (prio)
			{
				case "High": high.Add(role); break;
				case "Medium": medium.Add(role); break;
				case "Low": low.Add(role); break;
			}
		}

		var rng = new System.Random();
		foreach (var bucket in new[] { high, medium, low })
		{
			var shuffled = bucket.OrderBy(_ => rng.Next()).ToList();
			foreach (var role in shuffled)
			{
				if (_jobSlots.ContainsKey(role) && !_jobSlots[role].IsFull)
				{
					AssignJob(peerId, role);
					return role;
				}
			}
		}

		foreach (var kvp in _jobSlots.OrderByDescending(j => j.Value.Priority))
		{
			if (!kvp.Value.IsFull)
			{
				AssignJob(peerId, kvp.Key);
				return kvp.Key;
			}
		}

		return "";
	}

	public void UnassignPeer(int peerId)
	{
		if (!_peerAssignments.ContainsKey(peerId))
			return;

		var jobName = _peerAssignments[peerId];
		if (_jobSlots.ContainsKey(jobName))
			_jobSlots[jobName].FilledSlots--;

		_peerAssignments.Remove(peerId);
		EmitSignal(SignalName.JobAvailabilityChanged);
	}

	public string GetAssignedJob(int peerId)
	{
		return _peerAssignments.ContainsKey(peerId) ? _peerAssignments[peerId] : "";
	}

	public Array<Dictionary> GetAvailableJobs()
	{
		var jobs = new Array<Dictionary>();

		foreach (var kvp in _jobSlots.OrderByDescending(j => j.Value.Priority))
		{
			var job = kvp.Value;
			if (job.AvailableSlots > 0)
			{
				jobs.Add(new Dictionary
				{
					{ "name", job.JobName },
					{ "department", job.Department },
					{ "available", job.AvailableSlots },
					{ "max", job.MaxSlots },
					{ "priority", job.Priority }
				});
			}
		}

		return jobs;
	}

	public Array<Dictionary> GetAllJobs()
	{
		var jobs = new Array<Dictionary>();

		foreach (var kvp in _jobSlots.OrderBy(j => j.Value.Department).ThenByDescending(j => j.Value.Priority))
		{
			var job = kvp.Value;
			jobs.Add(new Dictionary
			{
				{ "name", job.JobName },
				{ "department", job.Department },
				{ "available", job.AvailableSlots },
				{ "filled", job.FilledSlots },
				{ "max", job.MaxSlots },
				{ "priority", job.Priority }
			});
		}

		return jobs;
	}

	public Dictionary GetJobsByDepartment()
	{
		var departments = new Dictionary();

		foreach (var kvp in _jobSlots)
		{
			var job = kvp.Value;
			if (!departments.ContainsKey(job.Department))
				departments[job.Department] = new Array<Dictionary>();

			var deptJobs = (Array<Dictionary>)departments[job.Department];
			deptJobs.Add(new Dictionary
			{
				{ "name", job.JobName },
				{ "available", job.AvailableSlots },
				{ "filled", job.FilledSlots },
				{ "max", job.MaxSlots },
				{ "priority", job.Priority }
			});
		}

		return departments;
	}

	public void ResetAllJobs()
	{
		foreach (var job in _jobSlots.Values)
			job.FilledSlots = 0;

		_peerAssignments.Clear();
		EmitSignal(SignalName.JobAvailabilityChanged);
	}
}
