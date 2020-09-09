"""
Functions to estimate Q|_{U^0}. See our paper for details.
"""

using LinearAlgebra
using SparseArrays
using FastRounding
using ValidatedNumerics
using ValidatedNumerics.IntervalArithmetic: round_expr

"""
Returns the maximum number of (structural) nonzeros in a row of A
"""
function max_nonzeros_per_row(A::SparseMatrixCSC)
    rows = rowvals(A)
    m, n = size(A)
    nonzeros_in_each_row = zeros(eltype(rows), m)
    for i in rows
        nonzeros_in_each_row[i] += 1
    end
    return maximum(nonzeros_in_each_row)
end

"""
γₙ constants for floating point error estimation, as in [Higham, Accuracy and Stability of Numerical Algorithms]
"""
function gamma(T, n::Integer)
    u = eps(T)
    nu = u ⊗₊ T(n)
    return nu ⊘₊ (one(T) ⊖₋ nu)
end

"""
Estimates the norms ||Q||, ||Q^2||, ... ||Q^m|| on U^0.

Q is the matrix L if is_integral_preserving==true, or
L + e*(f-f*L) otherwise.
An interval matrix LL ∋ L is given in input.

U is the matrix [ones(1,n-1); -I_(n-1,n-1)]. It is currently assumed that
f*U==0 (i.e., all elements of f are equal).

The following constants may be specified as keyword arguments:

normQ, normE, normv0, normEF, normIEF, normN

otherwise they are computed (which may be slower).

e and f must be specified in case is_integral_preserving==false
In case is_integral_preserving is true, they may be specified but they are then ignored.
(TODO: this should be better integrated in the syntax, using DiscretizedOperator).
"""
function norms_of_powers(N::Type{<:NormKind}, m::Integer, LL::SparseMatrixCSC{Interval{RealType}, IndexType}, is_integral_preserving::Bool ;
        e::Vector=[0.],
        f::Adjoint=adjoint([0.]),
        normv0::Real=-1., #used as "missing" value
        normQ::Real=-1.,
        normE::Real=-1.,
        normEF::Real=-1.,
        normIEF::Real=-1.,
        normN::Real=-1.) where {RealType, IndexType}

    n = size(LL, 1)
    M = mid.(LL)
    R = radius.(LL)
    δ = opnormbound(N, R)
    γz = gamma(RealType, max_nonzeros_per_row(LL))
    γn = gamma(RealType, n+3) # not n+2 like in the paper, because we wish to allow for f to be the result of rounding
    ϵ = zero(RealType)

    nrmM = opnormbound(N, M)

    if normQ == -1.
        if is_integral_preserving
            normQ = nrmM ⊕₊ δ
        else
            defect = opnormbound(N, f - f*LL)
            normQ = nrmM ⊕₊ δ ⊕₊ normE * defect
        end
    end

    # precompute norms
    if !is_integral_preserving
        if normE == -1.
            normE = opnormbound(N, e)
        end
        if normEF == -1.
            normEF = opnormbound(N, e*f)
        end
        if normIEF == -1.
            normIEF =  opnormbound(N, [Matrix(UniformScaling{Float64}(1),n,n) e*f])
        end
        if normN == -1.
            normN = opnormbound(N, Matrix(UniformScaling{Float64}(1),n,n) - e*f)
        end
    end

    # initialize normcachers
    normcachers = [NormCacher{N}(n) for j in 1:m]

    # main loop

    for j = 1:n-1
        v = zeros(n) # TODO: check for type stability in cases with unusual types
        v[1] = 1. # TODO: in full generality, this should contain entries of f rather than ±1
        v[j+1] = -1.
        if normv0 == -1.
            nrmv = opnormbound(N, v)
        else
            nrmv = normv0
        end
        ϵ = 0.
        nrmw = nrmv # we assume that initial vectors are already integral-preserving
        for k = 1:m
            w = M * v
            if is_integral_preserving
                v = w
                ϵ = round_expr((γz * nrmM + δ)*nrmv + normQ*ϵ, RoundUp)
            else
                v = w - e * (f*w)
                new_nrmw = opnormbound(N, w)
                ϵ = round_expr(γn*normIEF*(new_nrmw + normEF*nrmw) + normN*(γz*nrmM + δ)*nrmv + normQ*ϵ, RoundUp)
                nrmw = new_nrmw
            end
            nrmv = opnormbound(N, v)
            add_column!(normcachers[k], v, ϵ) #TODO: Could pass and reuse nrmv in the case of norm-1
        end
    end
    return map(get_norm, normcachers)
end

"""
Trivial bounds from ||Q^k|| ≤ ||Q||^k for the powers of a DiscretizedOperator (on the whole space)
"""
function norms_of_powers_trivial(N::Type{NormKind}, Q::DiscretizedOperator, m::Integer)
    norms = fill(NaN, m)
    norms[1] = opnormbound(N, Q)
    for i = 2:m
        norms[i] = norms[i-1] ⊗₀ norms[1]
    end
    return norms
end
