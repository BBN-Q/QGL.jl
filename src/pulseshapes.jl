module PulseShapes
# provides unscaled pulse shapes for waveforms

import Base.tanh

"""
	constant(;pulse_length=0.0, sampling_rate=1.2e9)

Constant pulse shape for delays or square pulses.
"""
function constant(;pulse_length=0.0, sampling_rate=1.2e9)
	num_pts = round(UInt, pulse_length*sampling_rate)
	ones(Complex128, num_pts)
end

"""
	gaussian(;pulse_length=0.0, sampling_rate=1.2e9, cutoff=2.0)::Vector{Complex128}

Gaussian shaped pulse of a given pulse_length and sampling_rate going between -cutoff and cutoff σ wide.
Shape is shifted down to avoid finite cutoff step and start and end of pulse.
"""
function gaussian(;pulse_length=0.0, sampling_rate=1.2e9, cutoff=2.0)::Vector{Complex128}
	num_pts = round(UInt, pulse_length*sampling_rate)
	x_pts = linspace(-cutoff, cutoff, num_pts)
	# pull the pulse down so there is no bit step and the start/end of the pulse
	# i.e. find the shift such that the next point in the pulse would be zero
	x_step = x_pts[2] - x_pts[1]
	next_val = exp(-0.5 * (x_pts[1] - x_step)^2)
	shape = 1/(1-next_val) .* (exp.(-0.5 * (x_pts.^2)) - next_val)
	complex(shape)
end

@enum HALF_GAUSSIAN_DIRECTION HALF_GAUSSIAN_RISE HALF_GAUSSIAN_FALL

"""
	half_gaussian(;pulse_length=0.0, sampling_rate=1.2e9, cutoff=2.0, direction=HALF_GAUSSIAN_RISE)

A half gaussian pulse. Can be used as an excitation pulse but also used to round a square pulse.
"""

function half_gaussian(;pulse_length=0.0, sampling_rate=1.2e9, cutoff=2.0, direction::HALF_GAUSSIAN_DIRECTION=HALF_GAUSSIAN_RISE)
	num_pts = round(UInt, pulse_length*sampling_rate)
	x_pts = linspace(-cutoff, 0, num_pts)
	# pull the pulse down so there is no bit step and the start/end of the pulse
	# i.e. find the shift such that the next point in the pulse would be zero
	x_step = x_pts[2] - x_pts[1]
	next_val = exp(-0.5 * (x_pts[1] - x_step)^2)
	shape = 1/(1-next_val) .* (exp.(-0.5 * (x_pts.^2)) - next_val)
	if direction == HALF_GAUSSIAN_FALL
		reverse!(shape)
	end
	complex(shape)
end

"""
	drag(;pulse_length=0.0, sampling_rate=1.2e9, drag_scaling=1.0)::Vector{Complex128}

DRAG gaussian shape with -0.5 * (time derivative of gaussian) on the quadrature. The
derivative is scaled by `drag_scaling`.
"""
function drag(;pulse_length=0.0, sampling_rate=1.2e9, cutoff=2.0, drag_scaling=1.0)::Vector{Complex128}
	inphase = gaussian(;pulse_length=pulse_length, sampling_rate=sampling_rate, cutoff=cutoff)

	# d/dx of exp(-0.5 * x_pts.^2) = - x_pts * exp(-0.5 * x_pts.^2)
	# the time derivative needs a substitution rule from x -> t
	# where t is in units of sampling_rate
	# the pulse pulse_length in σ or x units is 2*cutoff so t = (num_points/(2*cutoff)) x
	num_pts = round(UInt, pulse_length*sampling_rate)
	x_pts = linspace(-cutoff, cutoff, num_pts)
	deriv_scale = 2*cutoff / num_pts
	quadrature = deriv_scale * drag_scaling * x_pts .* inphase
	complex(inphase, quadrature)
end

"""
	tanh(;pulse_length=0.0, sampling_rate=1.2e9, sigma=0.0, cutoff=2)::Vector{Complex128}

Square pulse with tanh rounded edges.
"""
function tanh(;pulse_length=0.0, sampling_rate=1.2e9, sigma=1e-9, cutoff=2)::Vector{Complex128}
	num_pts = round(UInt, pulse_length*sampling_rate)
	t = linspace(-pulse_length/2, pulse_length/2, num_pts)
	t₁ = -pulse_length/2 + cutoff*sigma
	t₂ = pulse_length/2 - cutoff*sigma
	shape = 0.5 * ( tanh.((t-t₁)/sigma) + tanh.((t₂-t)/sigma) )
	complex(shape)
end

"""
	exp_decay(;pulse_length=0.0, sampling_rate=1.2e9, sigma=1e-9, steady_state=0.5)::Vector{Complex128}

An exponentially decaying pulse to try and populate the cavity as quickly as possible.
But then don't overdrive it.
"""
function exp_decay(;pulse_length=0.0, sampling_rate=1.2e9, sigma=1e-9, steady_state=0.5)::Vector{Complex128}
	num_pts = round(UInt, pulse_length*sampling_rate)
	time_pts = (1.0/sampling_rate) * (0:num_pts-1)
	shape = steady_state + (1-steady_state)*exp(-time_pts / sigma)
	complex(shape)
end


"""
	CLEAR(;pulse_length=0.0, sampling_rate=1.2e9, sigma=0.0, steady_state=0.5, step_length=0.0, amp1=0.0, amp2=0.0)::Vector{Complex128}

Shape to quickly deplete the cavity at the end of a measurement.
Exponentially decaying measurement pulse followed by 2 steps of pulse_length `step_length` and amplitudes `amp1`, `amp2`.

Reference:

Rapid Driven Reset of a Qubit Readout Resonator

D. T. McClure, Hanhee Paik, L. S. Bishop, M. Steffen, Jerry M. Chow, and Jay M. Gambetta
Phys. Rev. Applied 5, 011001 – Published 27 January 2016 https://doi.org/10.1103/PhysRevApplied.5.011001
"""
function CLEAR(;pulse_length=0.0, sampling_rate=1.2e9, sigma=0.0, steady_state=0.5, step_length=0.0, amp1=0.0, amp2=0.0)::Vector{Complex128}
	meas_pulse = exp_decay(;pulse_length=pulse_length-2*step_length, sampling_rate=sampling_rate, sigma=sigma, steady_state=steady_state)
	num_pts_step = round(UInt, step_length*sampling_rate)
	clear_pulse1 = amp1 * ones(Complex128, num_pts_step)
	clear_pulse2 = amp2 * ones(Complex128, num_pts_step)
	[meas_pulse; clear_pulse1; clear_pulse2]
end

end
