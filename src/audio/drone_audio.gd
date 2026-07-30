class_name DroneAudio
extends Node3D
## The engine-facing half of the audio consumer. RotorSynth does the sound; this does the
## propagation — where the drone is, where the ears are, and what the air does in between.
##
## Splitting it this way is what keeps the synthesiser testable headlessly (no audio device
## exists under --headless), and it also puts the physical propagation model in one place
## rather than smeared through the DSP.
##
## Distance attenuation and stereo placement are AudioStreamPlayer3D's job, because it does
## them in engine C++ and does them correctly. Doppler is deliberately NOT: the engine
## implements it by resampling a finished buffer, and since we are generating the waveform
## from scratch anyway, scaling the phase increment is both exact and free. Having both
## enabled would apply it twice.

## Where the listener stands. The default is the pilot on the ground, because that is what
## a racing quad actually sounds like to the person flying it, and because it is the only
## option where the propagation model does any work: from the chase camera the drone never
## moves relative to you, so there is no doppler, barely any distance change, and the whole
## acoustic scene collapses to "engine noise, constant volume".
enum Listener { PILOT_GROUND, CHASE_CAMERA }

## Buffer length. Long enough to survive a frame-rate hitch without the stream running dry
## (which is heard as a gap), short enough that a throttle change is not audibly late —
## 120 ms is about four frames at 30 fps.
const BUFFER_LENGTH_S := 0.12
const SAMPLE_RATE_HZ := 44100.0

## Beyond this the drone is inaudible and there is nothing to compute.
const MAX_AUDIBLE_DISTANCE_M := 400.0
## Distance at which the source plays at unit gain. A quad at 3 m is extremely loud; this
## is the reference the 1/r falloff is anchored to.
const REFERENCE_DISTANCE_M := 3.0

## Air absorbs high frequencies with distance — the reason a quad two hundred metres away
## is a buzz and the same quad overhead is a scream. The engine applies this as a low-pass
## that deepens with distance; this is its corner frequency.
const AIR_ABSORPTION_CUTOFF_HZ := 5000.0
const AIR_ABSORPTION_DB := -24.0

var synth := RotorSynth.new(SAMPLE_RATE_HZ)
var listener_mode: Listener = Listener.PILOT_GROUND
var pilot_position := Vector3.ZERO

var _player: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _listener: AudioListener3D
## Set when no audio device is available (a headless run, or a machine with no output).
## Everything else still runs; only the push to the device is skipped.
var _silent := false

func _ready() -> void:
	# A headless run has a dummy audio driver, which still hands out a valid playback object
	# and still accepts buffers — it just discards them. Synthesising into it is pure waste,
	# and it is waste in exactly the places that can least afford it: the test runner and
	# the screenshot/GIF capture scripts, which run frames as fast as they can and so ask
	# for far more audio per frame than realtime playback ever would.
	if DisplayServer.get_name() == "headless":
		_silent = true
		return

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE_HZ
	generator.buffer_length = BUFFER_LENGTH_S

	_player = AudioStreamPlayer3D.new()
	_player.stream = generator
	_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_player.unit_size = REFERENCE_DISTANCE_M
	_player.max_distance = MAX_AUDIBLE_DISTANCE_M
	_player.attenuation_filter_cutoff_hz = AIR_ABSORPTION_CUTOFF_HZ
	_player.attenuation_filter_db = AIR_ABSORPTION_DB
	# Doppler is done in the synthesiser. See the class comment.
	_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(_player)

	_listener = AudioListener3D.new()
	add_child(_listener)

	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_silent = _playback == null

## Releases our own hold on the playback as the node leaves the tree.
##
## Known, and deliberately not chased further: a run that exits immediately still prints
## "1 ObjectDB instance was leaked at exit — AudioStreamGeneratorPlayback". That reference
## is the audio server's, not ours; it is released on the server's next mix, which never
## arrives when the process quits in the same frame. Stopping the player, clearing the
## stream and nulling this reference were all tried and none of them remove it.
##
## It is a shutdown-ordering warning, not a leak during flight — nothing accumulates while
## the sim is running, and the count stays at exactly one however long the session lasts.
## Recorded here because the warning looks alarming in the capture tools' output and would
## otherwise get re-investigated.
func _exit_tree() -> void:
	if _player != null:
		if _player.playing:
			_player.stop()
		_player.stream = null
	_playback = null

## Places the listener. Called once when the course is built, and again if the pilot's
## position changes; the chase camera needs no placement because Godot uses the current
## Camera3D as the listener when no AudioListener3D is current.
func set_listener(mode: Listener, p_pilot_position: Vector3) -> void:
	listener_mode = mode
	pilot_position = p_pilot_position
	if _listener == null:
		return
	if mode == Listener.PILOT_GROUND:
		# Ear height, not ground level. It matters less than it sounds like it should, but
		# a listener at y=0 is inside the ground plane.
		_listener.global_position = p_pilot_position + Vector3(0, 1.6, 0)
		_listener.make_current()
	else:
		_listener.clear_current()

## Fed the published observables every frame. Reads nothing else — this is the whole of
## audio's coupling to the simulation.
func update(obs: Observables, camera_position: Vector3) -> void:
	if _playback == null:
		return

	_player.global_position = obs.position_m

	var listener_position := pilot_position + Vector3(0, 1.6, 0)
	if listener_mode == Listener.CHASE_CAMERA:
		listener_position = camera_position

	var doppler := RotorSynth.doppler_scale(obs.position_m, obs.velocity_mps, listener_position)

	# Fill exactly what the device has room for. Asking for a fixed block size instead
	# either overruns (the excess is dropped, which is a click) or underruns (the stream
	# runs dry, which is a gap).
	var frames := _playback.get_frames_available()
	if frames > 0:
		_playback.push_buffer(synth.render_stereo(obs, doppler, frames))

## Cuts the sound instantly, without a spin-down ramp. Used on respawn: the drone is
## somewhere else now, and interpolating its RPM across the teleport is a swoop that never
## happened.
func reset() -> void:
	synth = RotorSynth.new(SAMPLE_RATE_HZ)
