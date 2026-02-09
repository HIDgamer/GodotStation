using Godot;

public partial class BulletProjectile : Node2D
{
	[Export] public float Speed = 900.0f;
	
	private Vector2 _start;
	private Vector2 _end;
	private float _travelTime;
	private float _elapsed;
	
	public void Init(Vector2 start, Vector2 end, float speed)
	{
		_start = start;
		_end = end;
		Speed = speed;
		GlobalPosition = start;
		
		float dist = start.DistanceTo(end);
		_travelTime = Speed > 0f ? dist / Speed : 0.05f;
		_travelTime = Mathf.Clamp(_travelTime, 0.03f, 0.35f);
		Rotation = (end - start).Angle();
	}
	
	public override void _Process(double delta)
	{
		if (_travelTime <= 0f)
		{
			GlobalPosition = _end;
			QueueFree();
			return;
		}
		
		_elapsed += (float)delta;
		float t = Mathf.Clamp(_elapsed / _travelTime, 0f, 1f);
		GlobalPosition = _start.Lerp(_end, t);
		
		if (t >= 1f)
			QueueFree();
	}
}
