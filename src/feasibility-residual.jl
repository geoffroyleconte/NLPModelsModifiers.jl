export FeasibilityResidual

# TODO: Extend to handle bounds
"""
A feasibility residual model is created from a NLPModel of the form
```math
\\begin{aligned}
       \\min_x \\quad & f(x) \\\\
\\mathrm{s.t.} \\quad & c_L ≤ c(x) ≤ c_U \\\\
                      & \\ell ≤   x  ≤ u,
\\end{aligned}
```
by creating slack variables ``s = c(x)`` and defining an NLS problem from the equality constraints.
The resulting problem is a bound-constrained nonlinear least-squares problem with residual
function NLPModels.``F(x,s) = c(x) - s``:
```math
\\begin{aligned}
       \\min_{x,s} \\quad & \\tfrac{1}{2} \\|c(x) - s\\|^2 \\\\
\\mathrm{s.t.} \\quad & \\ell ≤ x ≤ u \\\\
                      & c_L ≤ s ≤ c_U.
\\end{aligned}
```
Notice that this problem is an `AbstractNLSModel`, thus the residual value, Jacobian and Hessian are explicitly defined through the NLS API.
The slack variables are created using SlackModel.
If ``\\ell_i = u_i``, no slack variable is created.
In particular, if there are only equality constrained of the form ``c(x) = 0``, the resulting NLS is simply ``\\min_x \\tfrac{1}{2}\\|c(x)\\|^2``.
"""
mutable struct FeasibilityResidual{T, S, M <: AbstractNLPModel{T, S}} <: AbstractNLSModel{T, S}
  meta::NLPModelMeta{T, S}
  nls_meta::NLSMeta{T, S}
  counters::NLSCounters
  nlp::M

  y::S # pre-allocated vector of length nequ
  Hiv::S # pre-allocated vector of length nvar
  Jvcx::S # pre-allocated vector of length nlp.meta.ncon
end

function NLPModels.show_header(io::IO, nls::FeasibilityResidual)
  println(
    io,
    "FeasibilityResidual - Nonlinear least-squares defined from constraints of another problem",
  )
end

function FeasibilityResidual(
  nlp::AbstractNLPModel{T, S};
  name = "$(nlp.meta.name)-feasres",
) where {T, S}
  if !equality_constrained(nlp)
    if unconstrained(nlp)
      throw(ErrorException("Can't handle unconstrained problem"))
    elseif nlp isa AbstractNLSModel
      return FeasibilityResidual(SlackNLSModel(nlp), name = name)
    else
      return FeasibilityResidual(SlackModel(nlp), name = name)
    end
  end

  m, n = nlp.meta.ncon, nlp.meta.nvar
  # TODO: What is copied?
  meta = NLPModelMeta{T, S}(
    n,
    x0 = nlp.meta.x0,
    name = name,
    lvar = nlp.meta.lvar,
    uvar = nlp.meta.uvar,
    nnzj = 0,
  )
  nls_meta = NLSMeta{T, S}(m, n, nnzj = nlp.meta.nnzj, nnzh = nlp.meta.nnzh, lin = nlp.meta.lin)
  y = similar(nlp.meta.x0, nls_meta.nequ)
  Hiv = similar(nlp.meta.x0)
  Jvcx = similar(nlp.meta.x0, m)
  nls = FeasibilityResidual(meta, nls_meta, NLSCounters(), nlp, y, Hiv, Jvcx)
  finalizer(nls -> finalize(nls.nlp), nls)

  return nls
end

function NLPModels.residual!(nls::FeasibilityResidual, x::AbstractVector, Fx::AbstractVector)
  increment!(nls, :neval_residual)
  cons!(nls.nlp, x, Fx)
  Fx .-= nls.nlp.meta.lcon
  return Fx
end

function NLPModels.jac_residual(nls::FeasibilityResidual, x::AbstractVector)
  increment!(nls, :neval_jac_residual)
  return jac(nls.nlp, x)
end

function NLPModels.jac_structure_residual!(
  nls::FeasibilityResidual,
  rows::AbstractVector{<:Integer},
  cols::AbstractVector{<:Integer},
)
  return jac_structure!(nls.nlp, rows, cols)
end

function NLPModels.jac_coord_residual!(
  nls::FeasibilityResidual,
  x::AbstractVector,
  vals::AbstractVector,
)
  increment!(nls, :neval_jac_residual)
  return jac_coord!(nls.nlp, x, vals)
end

function NLPModels.jprod_residual!(
  nls::FeasibilityResidual,
  x::AbstractVector,
  v::AbstractVector,
  Jv::AbstractVector,
)
  increment!(nls, :neval_jprod_residual)
  return jprod!(nls.nlp, x, v, Jv)
end

function NLPModels.jtprod_residual!(
  nls::FeasibilityResidual,
  x::AbstractVector,
  v::AbstractVector,
  Jtv::AbstractVector,
)
  increment!(nls, :neval_jtprod_residual)
  return jtprod!(nls.nlp, x, v, Jtv)
end

function NLPModels.hess_residual(nls::FeasibilityResidual, x::AbstractVector, v::AbstractVector)
  increment!(nls, :neval_hess_residual)
  return hess(nls.nlp, x, v, obj_weight = zero(eltype(x)))
end

function NLPModels.hess_structure_residual!(
  nls::FeasibilityResidual,
  rows::AbstractVector{<:Integer},
  cols::AbstractVector{<:Integer},
)
  return hess_structure!(nls.nlp, rows, cols)
end

function NLPModels.hess_coord_residual!(
  nls::FeasibilityResidual,
  x::AbstractVector,
  v::AbstractVector,
  vals::AbstractVector,
)
  increment!(nls, :neval_hess_residual)
  return hess_coord!(nls.nlp, x, v, vals, obj_weight = zero(eltype(x)))
end

function NLPModels.jth_hess_residual(nls::FeasibilityResidual, x::AbstractVector, i::Int)
  increment!(nls, :neval_jhess_residual)
  T = eltype(x)
  nls.y .= zero(T)
  nls.y[i] = one(T)
  return hess(nls.nlp, x, nls.y, obj_weight = zero(T))
end

function NLPModels.hprod_residual!(
  nls::FeasibilityResidual,
  x::AbstractVector,
  i::Int,
  v::AbstractVector,
  Hiv::AbstractVector,
)
  increment!(nls, :neval_hprod_residual)
  T = eltype(x)
  nls.y .= zero(T)
  nls.y[i] = one(T)
  return hprod!(nls.nlp, x, nls.y, v, Hiv, obj_weight = zero(T))
end

function NLPModels.hess(
  nls::FeasibilityResidual,
  x::AbstractVector;
  obj_weight::Real = one(eltype(x)),
)
  increment!(nls, :neval_hess)
  cx = cons(nls.nlp, x)
  Jx = jac(nls.nlp, x)
  Hx = tril(Jx' * Jx)
  Hx .+= hess(nls.nlp, x, cx, obj_weight = zero(eltype(x))).data
  return Symmetric(obj_weight * Hx, :L)
end

function NLPModels.hprod!(
  nls::FeasibilityResidual{T},
  x::AbstractVector,
  v::AbstractVector,
  Hv::AbstractVector;
  obj_weight::Real = one(T),
) where {T}
  increment!(nls, :neval_hprod)
  return hprod!(nls, x, v, nls.Jvcx, nls.Hiv, Hv, obj_weight = obj_weight)
end

function NLPModels.hprod!(
  nls::FeasibilityResidual,
  x::AbstractVector{T},
  v::AbstractVector,
  Jvcx::AbstractVector,
  Hiv::AbstractVector,
  Hv::AbstractVector;
  obj_weight::Real = one(T),
) where {T}
  increment!(nls, :neval_hprod)
  jprod!(nls.nlp, x, v, Jvcx)
  jtprod!(nls.nlp, x, Jvcx, Hv)
  cons!(nls.nlp, x, Jvcx)
  hprod!(nls.nlp, x, Jvcx, v, Hiv, obj_weight = zero(T))
  Hv .+= Hiv
  Hv .*= obj_weight
  return Hv
end

function NLPModels.hess_structure!(::FeasibilityResidual, ::AbstractVector, ::AbstractVector)
  @notimplemented_use_nls hess_structure
end

function NLPModels.hess_coord!(
  ::FeasibilityResidual,
  ::AbstractVector{T},
  ::AbstractVector;
  kwargs...,
) where {T}
  @notimplemented_use_nls hess_coord
end
