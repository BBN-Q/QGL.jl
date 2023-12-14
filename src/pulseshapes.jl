module PulseShapes
# provides unscaled pulse shapes for waveforms

import Base.tanh

"""
	constant(;pulse_length=0.0, sampling_rate=1.2e9)

Constant pulse shape for delays or square pulses.
"""
function constant(;pulse_length=0.0, sampling_rate=1.2e9)
	num_pts = round(Int, pulse_length*sampling_rate)
	ones(ComplexF64, num_pts)
end

"""
	gaussian(;pulse_length=0.0, sampling_rate=1.2e9, cutoff=2.0)::Vector{ComplexF64}

Gaussian shaped pulse of a given pulse_length and sampling_rate going between -cutoff and cutoff σ wide.
Shape is shifted down to avoid finite cutoff step and start and end of pulse.
"""
function gaussian(;pulse_length=0.0, sampling_rate=1.2e9, cutoff=2.0)::Vector{ComplexF64}
	num_pts = round(Int, pulse_length*sampling_rate)
	x_pts = range(-cutoff, stop=cutoff, length=num_pts)
	# pull the pulse down so there is no bit step and the start/end of the pulse
	# i.e. find the shift such that the next point in the pulse would be zero
	x_step = x_pts[2] - x_pts[1]
	next_val = exp(-0.5 * (x_pts[1] - x_step)^2)
	shape = 1/(1-next_val) .* (exp.(-0.5 .* (x_pts.^2)) .- next_val)
	complex(shape)
end

@enum HALF_GAUSSIAN_DIRECTION HALF_GAUSSIAN_RISE HALF_GAUSSIAN_FALL

"""
	half_gaussian(;pulse_length=0.0, sampling_rate=1.2e9, cutoff=2.0, direction=HALF_GAUSSIAN_RISE)

A half gaussian pulse. Can be used as an excitation pulse but also used to round a square pulse.
"""

function half_gaussian(;pulse_length=0.0, sampling_rate=1.2e9, cutoff=2.0, direction::HALF_GAUSSIAN_DIRECTION=HALF_GAUSSIAN_RISE)
	num_pts = round(Int, pulse_length*sampling_rate)
	x_pts = range(-cutoff, stop=0, length=num_pts)
	# pull the pulse down so there is no bit step and the start/end of the pulse
	# i.e. find the shift such that the next point in the pulse would be zero
	x_step = x_pts[2] - x_pts[1]
	next_val = exp(-0.5 * (x_pts[1] - x_step)^2)
	shape = 1/(1-next_val) .* (exp.(-0.5 .* (x_pts.^2)) .- next_val)
	if direction == HALF_GAUSSIAN_FALL
		reverse!(shape)
	end
	complex(shape)
end

"""
	drag(;pulse_length=0.0, sampling_rate=1.2e9, drag_scaling=1.0)::Vector{ComplexF64}

DRAG gaussian shape with -0.5 * (time derivative of gaussian) on the quadrature. The
derivative is scaled by `drag_scaling`.
"""
function drag(;pulse_length=0.0, sampling_rate=1.2e9, cutoff=2.0, drag_scaling=1.0)::Vector{ComplexF64}
	inphase = gaussian(;pulse_length=pulse_length, sampling_rate=sampling_rate, cutoff=cutoff)

	# d/dx of exp(-0.5 * x_pts.^2) = - x_pts * exp(-0.5 * x_pts.^2)
	# the time derivative needs a substitution rule from x -> t
	# where t is in units of sampling_rate
	# the pulse pulse_length in σ or x units is 2*cutoff so t = (num_points/(2*cutoff)) x
	num_pts = round(Int, pulse_length*sampling_rate)
	x_pts = range(-cutoff, stop=cutoff, length=num_pts)
	deriv_scale = 2*cutoff / num_pts
	quadrature = deriv_scale * drag_scaling * x_pts .* inphase
	complex(inphase + 1im*quadrature)
end

"""
	tanh(;pulse_length=0.0, sampling_rate=1.2e9, sigma=0.0, cutoff=2)::Vector{ComplexF64}

Square pulse with tanh rounded edges.
"""
function tanh(;pulse_length=0.0, sampling_rate=1.2e9, sigma=1e-9, cutoff=2)::Vector{ComplexF64}
	num_pts = round(Int, pulse_length*sampling_rate)
	t = range(-pulse_length/2, stop=pulse_length/2, length=num_pts)
	t₁ = -pulse_length/2 + cutoff*sigma
	t₂ = pulse_length/2 - cutoff*sigma
	shape = 0.5 .* ( tanh.((t.-t₁)./sigma) .+ tanh.((t₂.-t)./sigma) )
	complex(shape)
end

"""
	exp_decay(;pulse_length=0.0, sampling_rate=1.2e9, sigma=1e-9, steady_state=0.5)::Vector{ComplexF64}

An exponentially decaying pulse to try and populate the cavity as quickly as possible.
But then don't overdrive it.
"""
function exp_decay(;pulse_length=0.0, sampling_rate=1.2e9, sigma=1e-9, steady_state=0.5)::Vector{ComplexF64}
	num_pts = round(Int, pulse_length*sampling_rate)
	time_pts = (1.0/sampling_rate) * (0:num_pts-1)
	shape = steady_state + (1-steady_state)*exp(-time_pts / sigma)
	complex(shape)
end


"""
	CLEAR(;pulse_length=0.0, sampling_rate=1.2e9, sigma=0.0, steady_state=0.5, step_length=0.0, amp1=0.0, amp2=0.0)::Vector{ComplexF64}

Shape to quickly deplete the cavity at the end of a measurement.
Exponentially decaying measurement pulse followed by 2 steps of pulse_length `step_length` and amplitudes `amp1`, `amp2`.

Reference:

Rapid Driven Reset of a Qubit Readout Resonator

D. T. McClure, Hanhee Paik, L. S. Bishop, M. Steffen, Jerry M. Chow, and Jay M. Gambetta
Phys. Rev. Applied 5, 011001 – Published 27 January 2016 https://doi.org/10.1103/PhysRevApplied.5.011001
"""
function CLEAR(;pulse_length=0.0, sampling_rate=1.2e9, sigma=0.0, steady_state=0.5, step_length=0.0, amp1=0.0, amp2=0.0)::Vector{ComplexF64}
	meas_pulse = exp_decay(;pulse_length=pulse_length-2*step_length, sampling_rate=sampling_rate, sigma=sigma, steady_state=steady_state)
	num_pts_step = round(UInt, step_length*sampling_rate)
	clear_pulse1 = amp1 * ones(ComplexF64, num_pts_step)
	clear_pulse2 = amp2 * ones(ComplexF64, num_pts_step)
	[meas_pulse; clear_pulse1; clear_pulse2]
end

"""
	arb_axis_drag(;pulse_length=0.0, sampling_rate=1.2e9, nut_freq=10e6, rot_angle=0.0, polar_angle=0.0, drag_scaling=0.0)

Single-qubit arbitrary axis pulse implemented with phase ramping and frame change.
Parameters
    nutFreq: effective nutation frequency per unit of drive amplitude (Hz)
    rotAngle : effective rotation rotAngle (radians)
    polarAngle : polar angle of rotation axis (radians)
    aziAngle : azimuthal (radians)
"""
function arb_axis_drag(;pulse_length=0.0, sampling_rate=1.2e9, nut_freq=10e6, rot_angle=0.0, Θ=0.0, drag_scaling=0.0)::Vector{ComplexF64}
	if pulse_length > 0
		# start from a gaussian shaped pulse
		gauss_pulse = gaussian(pulse_length=pulse_length, sampling_rate=sampling_rate)
		# scale to achieve to the desired rotation
		cal_scale = (rot_angle/2/pi)*sampling_rate/sum(gauss_pulse)
		# calculate the phase ramp steps to achieve the desired Z component to the rotation axis
		phase_steps = -2π*cos(Θ)*cal_scale*gauss_pulse/sampling_rate
		# Calculate Z DRAG correction to phase steps
		# β is a conversion between XY drag scaling and Z drag scaling
		β = drag_scaling/sampling_rate
		instantaneous_detuning = β * (2π*cal_scale*sin(Θ)*gauss_pulse).^2
		phase_steps += instantaneous_detuning*(1/sampling_rate)
		#center phase ramp around the middle of the pulse time steps
		phase_ramp = cumsum(phase_steps) - phase_steps/2
		shape = (1/nut_freq)*sin(Θ)*cal_scale*gauss_pulse.*exp(1im*phase_ramp)
	elseif abs(Θ) <1e-10
		#Otherwise assume we have a zero-length Z rotation
		shape = Vector{ComplexF64}()
	else
		error("Non-zero transverse rotation with zero-length pulse.")
	end
	complex(shape)
end
end
