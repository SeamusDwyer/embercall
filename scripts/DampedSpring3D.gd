class_name DampedSpring3D
extends RefCounted
## Frame-rate-independent damped spring for Vector3 values.
##
## Uses the closed-form solution to the damped harmonic oscillator
## (m*x'' + d*x' + s*(x - goal) = 0) instead of Euler integration, so the
## motion is identical at any frame rate and never explodes on a large delta.
## Based on Ryan Juckett's "Damped Springs" and Daniel Holden's
## "Spring-It-On: The Game Developer's Spring-Roll-Call".
##
## `frequency` (Hz) controls how fast the spring reacts; `damping_ratio`
## controls the overshoot: 1.0 = critically damped (no bounce),
## < 1.0 = under-damped (bouncy), > 1.0 = over-damped.

var value: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO

const EPS := 1e-5


func reset(to: Vector3 = Vector3.ZERO) -> void:
	value = to
	velocity = Vector3.ZERO


## Advance the spring toward `target` over `delta` seconds.
func step(target: Vector3, frequency: float, damping_ratio: float, delta: float) -> void:
	if delta <= 0.0:
		return

	var s: float = pow(TAU * maxf(frequency, EPS), 2.0)
	var d: float = maxf(damping_ratio, 0.0) * 2.0 * sqrt(s)
	var y: float = d / 2.0
	var disc: float = s - (d * d) / 4.0

	var x := [value.x, value.y, value.z]
	var v := [velocity.x, velocity.y, velocity.z]
	var g := [target.x, target.y, target.z]

	if absf(disc) < EPS:
		var eydt: float = exp(-y * delta)
		for i in 3:
			var j0: float = x[i] - g[i]
			var j1: float = v[i] + j0 * y
			x[i] = j0 * eydt + delta * j1 * eydt + g[i]
			v[i] = -y * j0 * eydt - y * delta * j1 * eydt + j1 * eydt
	elif disc > 0.0:
		var w: float = sqrt(disc)
		var eydt: float = exp(-y * delta)
		for i in 3:
			var diff: float = x[i] - g[i]
			var a: float = v[i] + y * diff
			var j: float = sqrt(a * a / (w * w) + diff * diff)
			var p: float = atan2(-a / w, diff)
			x[i] = j * eydt * cos(w * delta + p) + g[i]
			v[i] = -y * j * eydt * cos(w * delta + p) - w * j * eydt * sin(w * delta + p)
	else:
		var sq: float = sqrt(d * d - 4.0 * s)
		var y0: float = (d + sq) / 2.0
		var y1: float = (d - sq) / 2.0
		var ey0dt: float = exp(-y0 * delta)
		var ey1dt: float = exp(-y1 * delta)
		for i in 3:
			var j1: float = (g[i] * y0 - x[i] * y0 - v[i]) / (y1 - y0)
			var j0: float = x[i] - j1 - g[i]
			x[i] = j0 * ey0dt + j1 * ey1dt + g[i]
			v[i] = -y0 * j0 * ey0dt - y1 * j1 * ey1dt

	value = Vector3(x[0], x[1], x[2])
	velocity = Vector3(v[0], v[1], v[2])
