export BlockLabel

immutable BlockLabel
  label::AbstractString
  hash::UInt
end

#define operators
==(a::BlockLabel, b::BlockLabel) = a.label == b.label
!=(a::BlockLabel, b::BlockLabel) = a.label != b.label


function BlockLabel(label)
	BlockLabel(label, hash(label))
end

#show
show(io::IO, b::BlockLabel) = print(io, "$(b.label)")

numlabels = 0

function new_label()
  global numlabels
  label = BlockLabel(asciibase(numlabels)) #convert to alphabet
  numlabels += 1
  return label
end

function end_label(seq)
  if typeof(seq[end]) != BlockLabel
    push!(seq, new_label())
  end
  return seq[end]
end

function asciibase(x)
  alphabet = string('A':'Z'...)
  s = ""
while true
    s = string(alphabet[x % 26 + 1], s)
    x = div(x, 26) - 1
    if x == -1
      break
    end
  end
    return s
end
