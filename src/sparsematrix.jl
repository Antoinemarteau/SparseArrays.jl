# This file is a part of Julia. License is MIT: https://julialang.org/license

# Compressed sparse columns data structure
# No assumptions about stored zeros in the data structure
# Assumes that row values in rowval for each column are sorted
#      issorted(rowval[colptr[i]:(colptr[i+1]-1)]) == true
# Assumes that 1 <= colptr[i] <= colptr[i+1] for i in 1..n
# Assumes that nnz <= length(rowval) < typemax(Ti)
# Assumes that 0   <= length(nzval) < typemax(Ti)

"""
    SparseMatrixCSC{Tv,Ti<:Integer} <: AbstractSparseMatrixCSC{Tv,Ti}

Matrix type for storing sparse matrices in the
[Compressed Sparse Column](@ref man-csc) format. The standard way
of constructing SparseMatrixCSC is through the [`sparse`](@ref) function.
See also [`spzeros`](@ref), [`spdiagm`](@ref) and [`sprand`](@ref).
"""
struct SparseMatrixCSC{Tv,Ti<:Integer} <: AbstractSparseMatrixCSC{Tv,Ti}
    m::Int                  # Number of rows
    n::Int                  # Number of columns
    colptr::Vector{Ti}      # Column i is in colptr[i]:(colptr[i+1]-1)
    rowval::Vector{Ti}      # Row indices of stored values
    nzval::Vector{Tv}       # Stored values, typically nonzeros

    function SparseMatrixCSC{Tv,Ti}(m::Integer, n::Integer, colptr::Vector{Ti},
                            rowval::Vector{Ti}, nzval::Vector{Tv}) where {Tv,Ti<:Integer}
        sparse_check_Ti(m, n, Ti)
        _goodbuffers(Int(m), Int(n), colptr, rowval, nzval) ||
            throw(ArgumentError("Invalid buffers for SparseMatrixCSC construction n=$n, colptr=$(summary(colptr)), rowval=$(summary(rowval)), nzval=$(summary(nzval))"))
        new(Int(m), Int(n), colptr, rowval, nzval)
    end
end
function SparseMatrixCSC(m::Integer, n::Integer, colptr::Vector, rowval::Vector, nzval::Vector)
    Tv = eltype(nzval)
    Ti = promote_type(eltype(colptr), eltype(rowval))
    sparse_check_Ti(m, n, Ti)
    sparse_check(n, colptr, rowval, nzval)
    # silently shorten rowval and nzval to usable index positions.
    maxlen = abs(widemul(m, n))
    isbitstype(Ti) && (maxlen = min(maxlen, typemax(Ti) - 1))
    length(rowval) > maxlen && resize!(rowval, maxlen)
    length(nzval) > maxlen && resize!(nzval, maxlen)
    SparseMatrixCSC{Tv,Ti}(m, n, colptr, rowval, nzval)
end

SparseMatrixCSC(m, n, colptr::ReadOnly, rowval::ReadOnly, nzval::Vector) =
    SparseMatrixCSC(m, n, copy(parent(colptr)), copy(parent(rowval)), nzval)

"""
    SparseMatrixCSC{Tv,Ti}(::UndefInitializer, m::Integer, n::Integer)
    SparseMatrixCSC{Tv,Ti}(::UndefInitializer, (m,n)::NTuple{2,Integer})

Creates an empty sparse matrix with element type `Tv` and integer type `Ti` of size `m × n`.
"""
SparseMatrixCSC{Tv,Ti}(::UndefInitializer, m::Integer, n::Integer) where {Tv, Ti} = spzeros(Tv, Ti, m, n)
SparseMatrixCSC{Tv,Ti}(::UndefInitializer, mn::NTuple{2,Integer}) where {Tv, Ti} = spzeros(Tv, Ti, mn...)

"""
    FixedSparseCSC{Tv,Ti<:Integer} <: AbstractSparseMatrixCSC{Tv,Ti}

Experimental AbstractSparseMatrixCSC whose non-zero index are fixed.
"""
struct FixedSparseCSC{Tv,Ti<:Integer} <: AbstractSparseMatrixCSC{Tv,Ti}
    m::Int                  # Number of rows
    n::Int                  # Number of columns
    colptr::ReadOnly{Ti,1,Vector{Ti}} # Column i is in colptr[i]:(colptr[i+1]-1)
    rowval::ReadOnly{Ti,1,Vector{Ti}} # Row indices of stored values
    nzval::Vector{Tv}       # Stored values, typically nonzeros

    function FixedSparseCSC{Tv,Ti}(m::Integer, n::Integer,
                            colptr::ReadOnly{Ti,1,Vector{Ti}},
                            rowval::ReadOnly{Ti,1,Vector{Ti}},
                            nzval::Vector{Tv}) where {Tv,Ti<:Integer}
        sparse_check_Ti(m, n, Ti)
        _goodbuffers(Int(m), Int(n), parent(colptr), parent(rowval), nzval) ||
            throw(ArgumentError("Invalid buffers for FixedSparseCSC construction n=$n, colptr=$(summary(colptr)), rowval=$(summary(rowval)), nzval=$(summary(nzval))"))
        new(Int(m), Int(n), colptr, rowval, nzval)
    end
end
@inline _is_fixed(::FixedSparseCSC) = true
FixedSparseCSC(m::Integer, n::Integer,
    colptr::ReadOnly{Ti,1,Vector{Ti}},
    rowval::ReadOnly{Ti,1,Vector{Ti}},
    nzval::Vector{Tv}) where {Tv,Ti<:Integer} =
    FixedSparseCSC{Tv,Ti}(m, n, colptr, rowval, nzval)
FixedSparseCSC{Tv,Ti}(m::Integer, n::Integer, colptr::Vector{Ti}, rowval::Vector{Ti}, nzval::Vector{Tv}) where {Tv,Ti} =
    FixedSparseCSC{Tv,Ti}(m, n, ReadOnly(colptr), ReadOnly(rowval), nzval)
FixedSparseCSC(m::Integer, n::Integer, colptr::Vector{Ti}, rowval::Vector{Ti}, nzval::Vector{Tv}) where {Tv,Ti} =
    FixedSparseCSC{Tv,Ti}(m, n, ReadOnly(colptr), ReadOnly(rowval), nzval)
FixedSparseCSC(x::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti} =
    FixedSparseCSC{Tv,Ti}(size(x, 1), size(x, 2),
        getcolptr(x), rowvals(x), nonzeros(x))
FixedSparseCSC{Tv,Ti}(x::AbstractSparseMatrixCSC) where {Tv,Ti} =
    FixedSparseCSC{Tv,Ti}(size(x, 1), size(x, 2),
        getcolptr(x), rowvals(x), nonzeros(x))

"""
    fixed(x...)

Experimental. Like `sparse` but returns a sparse array whose `_is_fixed` is `true`.
"""
fixed(x...) = move_fixed(sparse(x...))
fixed(x::AbstractSparseMatrixCSC) = FixedSparseCSC(x)

"""
    move_fixed(x::AbstractSparseMatrixCSC)

Experimental, unsafe. Make a `FixedSparseCSC` by reusing the colptr, rowvals and nonzeros of `x`.
"""
move_fixed(x::AbstractSparseMatrixCSC) = FixedSparseCSC(size(x)..., getcolptr(x), rowvals(x), nonzeros(x))
"""
    _unsafe_unfix(x)

Experimental, unsafe. Returns a modifiable version of `x` for compatibility with this codebase.
"""
_unsafe_unfix(x::FixedSparseCSC) = SparseMatrixCSC(size(x)..., parent(getcolptr(x)), parent(rowvals(x)), nonzeros(x))
_unsafe_unfix(x::SparseMatrixCSC) = x

const SorF = Union{<:SparseMatrixCSC, <:FixedSparseCSC}

"""
    SparseMatrixCSC(x::FixedSparseCSC)

Get a writable copy of x. See `_unsafe_unfix(x)`
"""
SparseMatrixCSC(x::FixedSparseCSC) = SparseMatrixCSC(size(x, 1), size(x, 2),
    copy(parent(getcolptr(x))),
    copy(parent(rowvals(x))),
    copy(nonzeros(x)))

function sparse_check_Ti(m::Integer, n::Integer, Ti::Type)
        @noinline throwTi(str, lbl, k) =
            throw(ArgumentError("$str ($lbl = $k) does not fit in Ti = $(Ti)"))
        0 ≤ m && (!isbitstype(Ti) || m ≤ typemax(Ti)) || throwTi("number of rows", "m", m)
        0 ≤ n && (!isbitstype(Ti) || n ≤ typemax(Ti)) || throwTi("number of columns", "n", n)
end

function sparse_check(n::Integer, colptr::Vector{Ti}, rowval, nzval) where Ti
    # String interpolation is a performance bottleneck when it's part of the same function,
    # ensure we only do it once committed to the error.
    throwstart(ckp) = throw(ArgumentError("$ckp == colptr[1] != 1"))
    throwmonotonic(ckp, ck, k) = throw(ArgumentError("$ckp == colptr[$(k-1)] > colptr[$k] == $ck"))

    sparse_check_length("colptr", colptr, n+1, String) # don't check upper bound
    ckp = Ti(1)
    ckp == colptr[1] || throwstart(ckp)
    @inbounds for k = 2:n+1
        ck = colptr[k]
        ckp <= ck || throwmonotonic(ckp, ck, k)
        ckp = ck
    end
    sparse_check_length("rowval", rowval, ckp-1, Ti)
    sparse_check_length("nzval", nzval, 0, Ti) # we allow empty nzval !!!
end
function sparse_check_length(rowstr, rowval, minlen, Ti)
    throwmin(len, minlen, rowstr) = throw(ArgumentError("$len == length($rowstr) < $minlen"))
    throwmax(len, max, rowstr) = throw(ArgumentError("$len == length($rowstr) >= $max"))

    len = length(rowval)
    len >= minlen || throwmin(len, minlen, rowstr)
    !isbitstype(Ti) || len < typemax(Ti) || throwmax(len, typemax(Ti), rowstr)
end

size(S::SorF) = (getfield(S, :m), getfield(S, :n))

_goodbuffers(S::AbstractSparseMatrixCSC) = _goodbuffers(size(S)..., getcolptr(S), getrowval(S), nonzeros(S))
_checkbuffers(S::AbstractSparseMatrixCSC) = (@assert _goodbuffers(S); S)
_checkbuffers(S::Union{Adjoint, Transpose}) = (_checkbuffers(parent(S)); S)

function _goodbuffers(m, n, colptr, rowval, nzval)
    (length(colptr) == n + 1 && colptr[end] - 1 == length(rowval) == length(nzval))
    # stronger check for debugging purposes
    # && all(issorted(@view rowval[colptr[i]:colptr[i+1]-1]) for i=1:n)
end

# Define an alias for views of a SparseMatrixCSC which include all rows and a unit range of the columns.
# Also define a union of SparseMatrixCSC and this view since many methods can be defined efficiently for
# this union by extracting the fields via the get function: getcolptr, getrowval, and getnzval. The key
# insight is that getcolptr on a SparseMatrixCSCView returns an offset view of the colptr of the
# underlying SparseMatrixCSC
const SparseMatrixCSCView{Tv,Ti} =
    SubArray{Tv,2,<:AbstractSparseMatrixCSC{Tv,Ti},
        Tuple{Base.Slice{Base.OneTo{Int}},I}} where {I<:AbstractUnitRange{<:Integer}}
const SparseMatrixCSCUnion{Tv,Ti} = Union{AbstractSparseMatrixCSC{Tv,Ti}, SparseMatrixCSCView{Tv,Ti}}
# Define an alias for views of a SparseMatrixCSC which include all rows and a selection of the columns.
# Also define a union of SparseMatrixCSC and this view since many methods can be defined efficiently for
# this union by extracting the fields via the get function: getrowval, and getnzval, BUT NOT getcolptr!
const SparseMatrixCSCColumnSubset{Tv,Ti} =
    SubArray{Tv,2,<:AbstractSparseMatrixCSC{Tv,Ti},
        Tuple{Base.Slice{Base.OneTo{Int}},I}} where {I<:AbstractVector{<:Integer}}
const SparseMatrixCSCUnion2{Tv,Ti} = Union{AbstractSparseMatrixCSC{Tv,Ti}, SparseMatrixCSCColumnSubset{Tv,Ti}}

getcolptr(S::SorF)     = getfield(S, :colptr)
getcolptr(S::SparseMatrixCSCView) = view(getcolptr(parent(S)), first(S.indices[2]):(last(S.indices[2]) + 1))
getcolptr(S::SparseMatrixCSCColumnSubset) = error("getcolptr not well-defined for $(typeof(S))")
getrowval(S::AbstractSparseMatrixCSC) = rowvals(S)
getrowval(S::SparseMatrixCSCColumnSubset) = rowvals(parent(S))
getnzval( S::AbstractSparseMatrixCSC) = nonzeros(S)
getnzval( S::SparseMatrixCSCColumnSubset) = nonzeros(parent(S))
nzvalview(S::AbstractSparseMatrixCSC) = view(nonzeros(S), 1:nnz(S))

"""
    nnz(A)

Returns the number of stored (filled) elements in a sparse array.

# Examples
```jldoctest
julia> A = sparse(2I, 3, 3)
3×3 SparseMatrixCSC{Int64, Int64} with 3 stored entries:
 2  ⋅  ⋅
 ⋅  2  ⋅
 ⋅  ⋅  2

julia> nnz(A)
3
```
"""
nnz(S::AbstractSparseMatrixCSC) = Int(getcolptr(S)[size(S, 2) + 1]) - 1
nnz(S::ReshapedArray{<:Any,1,<:AbstractSparseMatrixCSC}) = nnz(parent(S))
nnz(S::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}) = nnz(parent(S))
nnz(S::UpperTriangular{<:Any,<:AbstractSparseMatrixCSC}) = nnz1(S)
nnz(S::LowerTriangular{<:Any,<:AbstractSparseMatrixCSC}) = nnz1(S)
nnz(S::SparseMatrixCSCColumnSubset) = nnz1(S)
nnz1(S) = sum(length.(nzrange.(Ref(S), axes(S, 2))))

function Base._simple_count(pred, S::AbstractSparseMatrixCSC, init::T) where T
    init + T(count(pred, nzvalview(S)) + pred(zero(eltype(S)))*(prod(size(S)) - nnz(S)))
end

"""
    nonzeros(A)

Return a vector of the structural nonzero values in sparse array `A`. This
includes zeros that are explicitly stored in the sparse array. The returned
vector points directly to the internal nonzero storage of `A`, and any
modifications to the returned vector will mutate `A` as well. See
[`rowvals`](@ref) and [`nzrange`](@ref).

# Examples
```jldoctest
julia> A = sparse(2I, 3, 3)
3×3 SparseMatrixCSC{Int64, Int64} with 3 stored entries:
 2  ⋅  ⋅
 ⋅  2  ⋅
 ⋅  ⋅  2

julia> nonzeros(A)
3-element Vector{Int64}:
 2
 2
 2
```
"""
nonzeros(S::SorF) = getfield(S, :nzval)
nonzeros(S::SparseMatrixCSCColumnSubset)  = nonzeros(S.parent)
nonzeros(S::UpperTriangular{<:Any,<:SparseMatrixCSCUnion}) = nonzeros(S.data)
nonzeros(S::LowerTriangular{<:Any,<:SparseMatrixCSCUnion}) = nonzeros(S.data)

"""
    rowvals(A)

Return a vector of the row indices of sparse array `A`. Any modifications to the returned
vector will mutate `A` as well. Providing access to how the row indices are
stored internally can be useful in conjunction with iterating over structural
nonzero values. See also [`nonzeros`](@ref) and [`nzrange`](@ref).

# Examples
```jldoctest
julia> A = sparse(2I, 3, 3)
3×3 SparseMatrixCSC{Int64, Int64} with 3 stored entries:
 2  ⋅  ⋅
 ⋅  2  ⋅
 ⋅  ⋅  2

julia> rowvals(A)
3-element Vector{Int64}:
 1
 2
 3
```
"""
rowvals(S::SorF) = getfield(S, :rowval)
rowvals(S::SparseMatrixCSCColumnSubset) = rowvals(S.parent)
rowvals(S::UpperTriangular{<:Any,<:SparseMatrixCSCUnion}) = rowvals(S.data)
rowvals(S::LowerTriangular{<:Any,<:SparseMatrixCSCUnion}) = rowvals(S.data)

"""
    nzrange(A, col::Integer)

Return the range of indices to the structural nonzero values of column `col`
of sparse array `A`. In conjunction with [`nonzeros`](@ref) and
[`rowvals`](@ref), this allows for convenient iterating over a sparse matrix :

    A = sparse(I,J,V)
    rows = rowvals(A)
    vals = nonzeros(A)
    m, n = size(A)
    for j = 1:n
       for i in nzrange(A, j)
          row = rows[i]
          val = vals[i]
          # perform sparse wizardry...
       end
    end

!!! warning
    Adding or removing nonzero elements to the matrix may invalidate the `nzrange`, one should not mutate the matrix while iterating.
"""
nzrange(S::AbstractSparseMatrixCSC, col::Integer) = getcolptr(S)[col]:(getcolptr(S)[col+1]-1)
nzrange(S::SparseMatrixCSCColumnSubset, col::Integer) = nzrange(S.parent, S.indices[2][col])
nzrange(S::UpperTriangular{<:Any,<:SparseMatrixCSCUnion}, i::Integer) = nzrangeup(S.data, i)
nzrange(S::LowerTriangular{<:Any,<:SparseMatrixCSCUnion}, i::Integer) = nzrangelo(S.data, i)

const AbstractSparseMatrixCSCInclAdjointAndTranspose = Union{AbstractSparseMatrixCSC,Adjoint{<:Any,<:AbstractSparseMatrixCSC},Transpose{<:Any,<:AbstractSparseMatrixCSC}}
function Base.isstored(A::AbstractSparseMatrixCSC, i::Integer, j::Integer)
    @boundscheck checkbounds(A, i, j)
    rows = rowvals(A)
    for istored in nzrange(A, j) # could do binary search if the row indices are sorted?
        i == rows[istored] && return true
    end
    return false
end

function Base.isstored(A::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}, i::Integer, j::Integer)
    @boundscheck checkbounds(A, i, j)
    cols = rowvals(parent(A))
    for istored in nzrange(parent(A), i)
        j == cols[istored] && return true
    end
    return false
end

Base.replace_in_print_matrix(A::AbstractSparseMatrixCSCInclAdjointAndTranspose, i::Integer, j::Integer, s::AbstractString) =
    Base.isstored(A, i, j) ? s : Base.replace_with_centered_mark(s)

function Base.array_summary(io::IO, S::AbstractSparseMatrixCSCInclAdjointAndTranspose, dims::Tuple{Vararg{Base.OneTo}})
    _checkbuffers(S)

    xnnz = nnz(S)
    m, n = size(S)
    print(io, m, "×", n, " ", typeof(S), " with ", xnnz, " stored ",
              xnnz == 1 ? "entry" : "entries")
    nothing
end

# called by `show(io, MIME("text/plain"), ::AbstractSparseMatrixCSCInclAdjointAndTranspose)`
function Base.print_array(io::IO, S::AbstractSparseMatrixCSCInclAdjointAndTranspose)
    if max(size(S)...) < 16
        Base.print_matrix(io, S)
    else
        _show_with_braille_patterns(io, S)
    end
end

"""
    ColumnIndices(S::AbstractSparseMatrixCSC)

Return the column indices of the stored values in `S`.
This is an internal type that is used in displaying sparse matrices,
and is not a part of the public interface.
"""
struct ColumnIndices{Ti,S<:AbstractSparseMatrixCSC{<:Any,Ti}} <: AbstractVector{Ti}
    arr :: S
end

size(C::ColumnIndices) = (nnz(C.arr),)
# returns the column index of the n-th non-zero value from the column pointer
@inline function getindex(C::ColumnIndices, i::Int)
    @boundscheck checkbounds(C, i)
    colptr = getcolptr(C.arr)
    ind = searchsortedlast(colptr, i)
    eltype(C)(ind)
end

# always show matrices as `sparse(I, J, K)`
function Base.show(io::IO, _S::AbstractSparseMatrixCSCInclAdjointAndTranspose)
    _checkbuffers(_S)
    # can't use `findnz`, because that expects all values not to be #undef
    S = _S isa Adjoint || _S isa Transpose ? _S.parent : _S
    I = rowvals(S)
    K = nonzeros(S)
    m, n = size(S)
    if _S isa Adjoint
        print(io, "adjoint(")
    elseif _S isa Transpose
        print(io, "transpose(")
    end
    print(io, "sparse(", I, ", ")
    show(io, ColumnIndices(S))
    print(io, ", ", K, ", ", m, ", ", n, ")")
    if _S isa Adjoint || _S isa Transpose
        print(io, ")")
    end
end

const brailleBlocks = UInt16['⠁', '⠂', '⠄', '⡀', '⠈', '⠐', '⠠', '⢀']
function _show_with_braille_patterns(io::IO, S::AbstractSparseMatrixCSCInclAdjointAndTranspose)
    m, n = size(S)
    (m == 0 || n == 0) && return show(io, MIME("text/plain"), S)

    # The maximal number of characters we allow to display the matrix
    local maxHeight::Int, maxWidth::Int
    maxHeight = displaysize(io)[1] - 4 # -4 from [Prompt, header, newline after elements, new prompt]
    maxWidth = displaysize(io)[2] ÷ 2

    # In the process of generating the braille pattern to display the nonzero
    # structure of `S`, we need to be able to scale the matrix `S` to a
    # smaller matrix with the same aspect ratio as `S`, but fits on the
    # available screen space. The size of that smaller matrix is stored
    # in the variables `scaleHeight` and `scaleWidth`. If no scaling is needed,
    # we can use the size `m × n` of `S` directly.
    # We determine if scaling is needed and set the scaling factors
    # `scaleHeight` and `scaleWidth` accordingly. Note that each available
    # character can contain up to 4 braille dots in its height (⡇) and up to
    # 2 braille dots in its width (⠉).
    if get(io, :limit, true) && (m > 4maxHeight || n > 2maxWidth)
        s = min(2maxWidth / n, 4maxHeight / m)
        scaleHeight = floor(Int, s * m)
        scaleWidth = floor(Int, s * n)
    else
        scaleHeight = m
        scaleWidth = n
    end

    # Make sure that the matrix size is big enough to be able to display all
    # the corner border characters
    if scaleHeight < 8
        scaleHeight = 8
    end
    if scaleWidth < 4
        scaleWidth = 4
    end

    # `brailleGrid` is used to store the needed braille characters for
    # the matrix `S`. Each row of the braille pattern to print is stored
    # in a column of `brailleGrid`.
    brailleGrid = fill(UInt16(10240), (scaleWidth - 1) ÷ 2 + 4, (scaleHeight - 1) ÷ 4 + 1)
    brailleGrid[1,:] .= '⎢'
    brailleGrid[end-1,:] .= '⎥'
    brailleGrid[1,1] = '⎡'
    brailleGrid[1,end] = '⎣'
    brailleGrid[end-1,1] = '⎤'
    brailleGrid[end-1,end] = '⎦'
    brailleGrid[end, :] .= '\n'

    rvals = rowvals(parent(S))
    rowscale = max(1, scaleHeight - 1) / max(1, m - 1)
    colscale = max(1, scaleWidth - 1) / max(1, n - 1)
    if isa(S, AbstractSparseMatrixCSC)
        @inbounds for j in axes(S,2)
            # Scale the column index `j` to the best matching column index
            # of a matrix of size `scaleHeight × scaleWidth`
            sj = round(Int, (j - 1) * colscale + 1)
            for x in nzrange(S, j)
                # Scale the row index `i` to the best matching row index
                # of a matrix of size `scaleHeight × scaleWidth`
                si = round(Int, (rvals[x] - 1) * rowscale + 1)

                # Given the index pair `(si, sj)` of the scaled matrix,
                # calculate the corresponding triple `(k, l, p)` such that the
                # element at `(si, sj)` can be found at position `(k, l)` in the
                # braille grid `brailleGrid` and corresponds to the 1-dot braille
                # character `brailleBlocks[p]`
                k = (sj - 1) ÷ 2 + 2
                l = (si - 1) ÷ 4 + 1
                p = ((sj - 1) % 2) * 4 + ((si - 1) % 4 + 1)

                brailleGrid[k, l] |= brailleBlocks[p]
            end
        end
    else
        # If `S` is a adjoint or transpose of a sparse matrix we invert the
        # roles of the indices `i` and `j`
        @inbounds for i = 1:m
            si = round(Int, (i - 1) * rowscale + 1)
            for x in nzrange(parent(S), i)
                sj = round(Int, (rvals[x] - 1) * colscale + 1)
                k = (sj - 1) ÷ 2 + 2
                l = (si - 1) ÷ 4 + 1
                p = ((sj - 1) % 2) * 4 + ((si - 1) % 4 + 1)
                brailleGrid[k, l] |= brailleBlocks[p]
            end
        end
    end
    foreach(c -> print(io, Char(c)), @view brailleGrid[1:end-1])
end

for QT in (:LinAlgLeftQs, :LQPackedQ)
    @eval (*)(Q::$QT, B::AbstractSparseMatrixCSC) = Q * Matrix(B)
    @eval (*)(Q::$QT, B::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}) = Q * copy(B)
    @eval (*)(A::AbstractSparseMatrixCSC, Q::$QT) = Matrix(A) * Q
    @eval (*)(A::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}, Q::$QT) = copy(A) * Q

    @eval (*)(Q::AdjointQ{<:Any,<:$QT}, B::AbstractSparseMatrixCSC) = Q * Matrix(B)
    @eval (*)(Q::AdjointQ{<:Any,<:$QT}, B::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}) = Q * copy(B)
    @eval (*)(A::AbstractSparseMatrixCSC, Q::AdjointQ{<:Any,<:$QT}) = Matrix(A) * Q
    @eval (*)(A::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}, Q::AdjointQ{<:Any,<:$QT}) = copy(A) * Q
end

## Reshape

function sparse_compute_reshaped_colptr_and_rowval!(colptrS::Vector{Ti}, rowvalS::Vector{Ti},
                                                   mS::Int, nS::Int, colptrA::Vector{Ti},
                                                   rowvalA::Vector{Ti}, mA::Int, nA::Int) where Ti
    lrowvalA = length(rowvalA)
    maxrowvalA = (lrowvalA > 0) ? maximum(rowvalA) : zero(Ti)
    ((length(colptrA) == (nA+1)) && (maximum(colptrA) <= (lrowvalA+1)) && (maxrowvalA <= mA)) || throw(BoundsError())

    colptrS[1] = 1
    colA = 1
    colS = 1
    ptr = 1

    @inbounds while colA <= nA
        offsetA = (colA - 1) * mA
        while ptr <= colptrA[colA+1]-1
            rowA = rowvalA[ptr]
            i = offsetA + rowA - 1
            colSn = div(i, mS) + 1
            rowS = mod(i, mS) + 1
            while colS < colSn
                colptrS[colS+1] = ptr
                colS += 1
            end
            rowvalS[ptr] = rowS
            ptr += 1
        end
        colA += 1
    end
    @inbounds while colS <= nS
        colptrS[colS+1] = ptr
        colS += 1
    end
end

function copy(ra::ReshapedArray{<:Any,2,<:AbstractSparseMatrixCSC})
    mS,nS = size(ra)
    a = parent(ra)
    mA,nA = size(a)
    numnz = nnz(a)
    colptr = similar(getcolptr(a), nS+1)
    rowval = similar(rowvals(a))
    nzval = copy(nonzeros(a))

    sparse_compute_reshaped_colptr_and_rowval!(colptr, rowval, mS, nS, getcolptr(a), rowvals(a), mA, nA)

    return SparseMatrixCSC(mS, nS, colptr, rowval, nzval)
end

## Alias detection and prevention
using Base: dataids, unaliascopy
Base.dataids(S::AbstractSparseMatrixCSC) = _is_fixed(S) ? dataids(nonzeros(S)) : (dataids(getcolptr(S))..., dataids(rowvals(S))..., dataids(nonzeros(S))...)
Base.unaliascopy(S::AbstractSparseMatrixCSC) = typeof(S)(size(S, 1), size(S, 2),
    _is_fixed(S) ? getcolptr(S) : unaliascopy(getcolptr(S)),
    _is_fixed(S) ? rowvals(S) : unaliascopy(rowvals(S)),
    unaliascopy(nonzeros(S)))

## Constructors

copy(S::AbstractSparseMatrixCSC) =
    SparseMatrixCSC(size(S, 1), size(S, 2), copy(getcolptr(S)), copy(rowvals(S)), copy(nonzeros(S)))
copy(S::FixedSparseCSC) =
    FixedSparseCSC(size(S, 1), size(S, 2), getcolptr(S), rowvals(S), copy(nonzeros(S)))
function copyto!(A::AbstractSparseMatrixCSC, B::AbstractSparseMatrixCSC)
    # If the two matrices have the same length then all the
    # elements in A will be overwritten.
    if widelength(A) == widelength(B)
        resize!(nonzeros(A), length(nonzeros(B)))
        resize!(rowvals(A), length(rowvals(B)))
        if size(A) == size(B)
            # Simple case: we can simply copy the internal fields of B to A.
            copyto!(getcolptr(A), getcolptr(B))
            copyto!(rowvals(A), rowvals(B))
        else
            # This is like a "reshape B into A".
            sparse_compute_reshaped_colptr_and_rowval!(getcolptr(A), rowvals(A), size(A, 1), size(A, 2), getcolptr(B), rowvals(B), size(B, 1), size(B, 2))
        end
    else
        widelength(A) >= widelength(B) || throw(BoundsError())
        lB = widelength(B)
        nnzA = nnz(A)
        nnzB = nnz(B)
        # Up to which col, row, and ptr in rowval/nzval will A be overwritten?
        lastmodcolA = Int(div(lB - 1, size(A, 1))) + 1
        lastmodrowA = Int(mod(lB - 1, size(A, 1))) + 1
        lastmodptrA = getcolptr(A)[lastmodcolA]
        while lastmodptrA < getcolptr(A)[lastmodcolA+1] && rowvals(A)[lastmodptrA] <= lastmodrowA
            lastmodptrA += 1
        end
        lastmodptrA -= 1
        if lastmodptrA >= nnzB
            # A will have fewer non-zero elements; unmodified elements are kept at the end.
            deleteat!(rowvals(A), nnzB+1:lastmodptrA)
            deleteat!(nonzeros(A), nnzB+1:lastmodptrA)
        else
            # A will have more non-zero elements; unmodified elements are kept at the end.
            resize!(rowvals(A), nnzB + nnzA - lastmodptrA)
            resize!(nonzeros(A), nnzB + nnzA - lastmodptrA)
            copyto!(rowvals(A), nnzB+1, rowvals(A), lastmodptrA+1, nnzA-lastmodptrA)
            copyto!(nonzeros(A), nnzB+1, nonzeros(A), lastmodptrA+1, nnzA-lastmodptrA)
        end
        # Adjust colptr accordingly.
        @inbounds for i in 2:length(getcolptr(A))
            getcolptr(A)[i] += nnzB - lastmodptrA
        end
        sparse_compute_reshaped_colptr_and_rowval!(getcolptr(A), rowvals(A), size(A, 1), lastmodcolA-1, getcolptr(B), rowvals(B), size(B, 1), size(B, 2))
    end
    copyto!(nonzeros(A), nonzeros(B))
    return _checkbuffers(A)
end

copyto!(A::AbstractMatrix, B::AbstractSparseMatrixCSC) = _sparse_copyto!(A, B)
# Ambiguity resolution
copyto!(A::PermutedDimsArray, B::AbstractSparseMatrixCSC) = _sparse_copyto!(A, B)

function _sparse_copyto!(dest::AbstractMatrix, src::AbstractSparseMatrixCSC)
    (dest === src || isempty(src)) && return dest
    z = convert(eltype(dest), zero(eltype(src))) # should throw if not possible
    isrc = LinearIndices(src)
    checkbounds(dest, isrc)
    # If src is not dense, zero out the portion of dest spanned by isrc
    if widelength(src) > nnz(src)
        for i in isrc
            @inbounds dest[i] = z
        end
    end
    @inbounds for col in axes(src, 2), ptr in nzrange(src, col)
        row = rowvals(src)[ptr]
        val = nonzeros(src)[ptr]
        dest[isrc[row, col]] = val
    end
    return dest
end

function copyto!(dest::AbstractMatrix, Rdest::CartesianIndices{2},
                 src::AbstractSparseMatrixCSC{T}, Rsrc::CartesianIndices{2}) where {T}
    isempty(Rdest) && return dest
    if size(Rdest) != size(Rsrc)
        throw(ArgumentError("source and destination must have same size (got $(size(Rsrc)) and $(size(Rdest)))"))
    end
    checkbounds(dest, Rdest)
    checkbounds(src, Rsrc)
    src′ = Base.unalias(dest, src)
    for I in Rdest
        @inbounds dest[I] = zero(T) # implicitly convert to eltype(dest), throw if not possible
    end
    rows, cols = Rsrc.indices
    lin = LinearIndices(Base.IdentityUnitRange.(Rsrc.indices))
    @inbounds for col in cols, ptr in nzrange(src′, col)
        row = rowvals(src′)[ptr]
        if row in rows
            val = nonzeros(src′)[ptr]
            I = Rdest[lin[row, col]]
            dest[I] = val
        end
    end
    return dest
end

# Faster version for non-abstract Array and SparseMatrixCSC
function Base.copyto!(A::Array{T}, S::SparseMatrixCSC{<:Number}) where {T<:Number}
    isempty(S) && return A
    length(A) < length(S) && throw(BoundsError())

    # Zero elements that are also in S, don't change rest of A
    @inbounds for i in 1:length(S)
        A[i] = zero(T)
    end
    # Copy the structural nonzeros from S to A using
    # the linear indices (to work when size(A)!=size(S))
    num_rows = size(S,1)
    rowval = getrowval(S)
    nzval = getnzval(S)
    linear_index_col0 = 0   # Linear index before column (linear index = linear_index_col0 + row)
    for col in axes(S, 2)
        for i in nzrange(S, col)
            row = rowval[i]
            val = nzval[i]
            A[linear_index_col0+row] = val
        end
        linear_index_col0 += num_rows
    end
    return A
end

## similar
#
# parent method for similar that preserves stored-entry structure (for when new and old dims match)
function _sparsesimilar(S::AbstractSparseMatrixCSC, ::Type{TvNew}, ::Type{TiNew}) where {TvNew,TiNew}
    newcolptr = copyto!(similar(getcolptr(S), TiNew), getcolptr(S))
    newrowval = copyto!(similar(rowvals(S), TiNew), rowvals(S))
    return SparseMatrixCSC(size(S, 1), size(S, 2), newcolptr, newrowval, similar(nonzeros(S), TvNew))
end
# parent methods for similar that preserves only storage space (for when new dims are 2-d)
_sparsesimilar(S::AbstractSparseMatrixCSC, ::Type{TvNew}, ::Type{TiNew}, dims::Dims{2}) where {TvNew,TiNew} =
    sizehint!(spzeros(TvNew, TiNew, dims...), length(nonzeros(S)))
# parent method for similar that allocates an empty sparse vector (for when new dims are 1-d)
_sparsesimilar(S::AbstractSparseMatrixCSC, ::Type{TvNew}, ::Type{TiNew}, dims::Dims{1}) where {TvNew,TiNew} =
    SparseVector(dims..., similar(rowvals(S), TiNew, 0), similar(nonzeros(S), TvNew, 0))

# The following methods hook into the AbstractArray similar hierarchy. The first method
# covers similar(A[, Tv]) calls, which preserve stored-entry structure, and the latter
# methods cover similar(A[, Tv], shape...) calls, which partially preserve
# storage space when the shape calls for a two-dimensional result.

"""
    similar(A::AbstractSparseMatrixCSC{Tv,Ti}, [::Type{TvNew}, ::Type{TiNew}, m::Integer, n::Integer]) where {Tv,Ti}

Create an uninitialized mutable array with the given element type,
index type, and size, based upon the given source
`SparseMatrixCSC`. The new sparse matrix maintains the structure of
the original sparse matrix, except in the case where dimensions of the
output matrix are different from the output.

The output matrix has zeros in the same locations as the input, but
uninitialized values for the nonzero locations.
"""
similar(S::AbstractSparseMatrixCSC{<:Any,Ti}, ::Type{TvNew}) where {Ti,TvNew} =
    @if_move_fixed S _sparsesimilar(S, TvNew, Ti)

similar(S::AbstractSparseMatrixCSC{<:Any,Ti}, ::Type{TvNew}, dims::Union{Dims{1},Dims{2}}) where {Ti,TvNew} =
    @if_move_fixed S _sparsesimilar(S, TvNew, Ti, dims)

# The following methods cover similar(A, Tv, Ti[, shape...]) calls, which specify the
# result's index type in addition to its entry type, and aren't covered by the hooks above.
# The calls without shape again preserve stored-entry structure, whereas those with shape
# preserve storage space when the shape calls for a two-dimensional result.
similar(S::AbstractSparseMatrixCSC, ::Type{TvNew}, ::Type{TiNew}) where{TvNew,TiNew} =
    _sparsesimilar(S, TvNew, TiNew)
similar(S::AbstractSparseMatrixCSC, ::Type{TvNew}, ::Type{TiNew}, dims::Union{Dims{1},Dims{2}}) where {TvNew,TiNew} =
    _sparsesimilar(S, TvNew, TiNew, dims)
similar(S::AbstractSparseMatrixCSC, ::Type{TvNew}, ::Type{TiNew}, m::Integer) where {TvNew,TiNew} =
    _sparsesimilar(S, TvNew, TiNew, (m,))
similar(S::AbstractSparseMatrixCSC, ::Type{TvNew}, ::Type{TiNew}, m::Integer, n::Integer) where {TvNew,TiNew} =
    _sparsesimilar(S, TvNew, TiNew, (m, n))

function Base.sizehint!(S::SparseMatrixCSC, n::Integer)
    nhint = min(n, widelength(S))
    sizehint!(getrowval(S), nhint)
    sizehint!(nonzeros(S),  nhint)
    return S
end

# converting between SparseMatrixCSC types
SparseMatrixCSC(S::AbstractSparseMatrixCSC) = copy(S)
AbstractMatrix{Tv}(A::AbstractSparseMatrixCSC) where {Tv} = SparseMatrixCSC{Tv}(A)
SparseMatrixCSC{Tv}(S::AbstractSparseMatrixCSC{Tv}) where {Tv} = copy(S)
SparseMatrixCSC{Tv}(S::AbstractSparseMatrixCSC) where {Tv} = SparseMatrixCSC{Tv,eltype(getcolptr(S))}(S)
SparseMatrixCSC{Tv,Ti}(S::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti} = copy(S)
function SparseMatrixCSC{Tv,Ti}(S::AbstractSparseMatrixCSC) where {Tv,Ti}
    eltypeTicolptr = Vector{Ti}(getcolptr(S))
    eltypeTirowval = Vector{Ti}(rowvals(S))
    eltypeTvnzval = Vector{Tv}(nonzeros(S))
    return SparseMatrixCSC(size(S, 1), size(S, 2), eltypeTicolptr, eltypeTirowval, eltypeTvnzval)
end

# converting from other matrix types to SparseMatrixCSC (also see sparse())
SparseMatrixCSC(M::Matrix) = sparse(M)
SparseMatrixCSC(T::Tridiagonal{Tv}) where Tv = SparseMatrixCSC{Tv,Int}(T)
function SparseMatrixCSC{Tv,Ti}(T::Tridiagonal) where {Tv,Ti}
    m = length(T.d)
    m == 0 && return SparseMatrixCSC{Tv,Ti}(0, 0, ones(Ti, 1), Ti[], Tv[])
    m == 1 && return SparseMatrixCSC{Tv,Ti}(1, 1, Ti[1, 2], Ti[1], Tv[T.d[1]])

    colptr = Vector{Ti}(undef, m+1)
    colptr[1] = 1
    @inbounds for i=1:m-1
        colptr[i+1] = 3i
    end
    colptr[end] = 3m-1

    rowval = Vector{Ti}(undef, 3m-2)
    rowval[1] = 1
    rowval[2] = 2
    @inbounds for i=2:m-1, j=-1:1
        rowval[3i+j-2] = i+j
    end
    rowval[end-1] = m - 1
    rowval[end] = m

    nzval = Vector{Tv}(undef, 3m-2)
    @inbounds for i=1:(m-1)
        nzval[3i-2] = T.d[i]
        nzval[3i-1] = T.dl[i]
        nzval[3i]   = T.du[i]
    end
    nzval[end] = T.d[end]

    return SparseMatrixCSC(m, m, colptr, rowval, nzval)
end
SparseMatrixCSC(T::SymTridiagonal{Tv}) where Tv = SparseMatrixCSC{Tv,Int}(T)
function SparseMatrixCSC{Tv,Ti}(T::SymTridiagonal) where {Tv,Ti}
    m = length(T.dv)
    m == 0 && return SparseMatrixCSC{Tv,Ti}(0, 0, ones(Ti, 1), Ti[], Tv[])
    m == 1 && return SparseMatrixCSC{Tv,Ti}(1, 1, Ti[1, 2], Ti[1], Tv[T.dv[1]])

    colptr = Vector{Ti}(undef, m+1)
    colptr[1] = 1
    @inbounds for i=1:m-1
        colptr[i+1] = 3i
    end
    colptr[end] = 3m-1

    rowval = Vector{Ti}(undef, 3m-2)
    rowval[1] = 1
    rowval[2] = 2
    @inbounds for i=2:m-1, j=-1:1
        rowval[3i+j-2] = i+j
    end
    rowval[end-1] = m - 1
    rowval[end] = m

    nzval = Vector{Tv}(undef, 3m-2)
    @inbounds for i=1:(m-1)
        nzval[3i-2] = T.dv[i]
        nzval[3i-1] = T.ev[i]
        nzval[3i]   = T.ev[i]
    end
    nzval[end] = T.dv[end]

    return SparseMatrixCSC(m, m, colptr, rowval, nzval)
end
SparseMatrixCSC(B::Bidiagonal{Tv}) where Tv = SparseMatrixCSC{Tv,Int}(B)
function SparseMatrixCSC{Tv,Ti}(B::Bidiagonal) where {Tv,Ti}
    m = length(B.dv)
    m == 0 && return SparseMatrixCSC{Tv,Ti}(0, 0, ones(Ti, 1), Ti[], Tv[])

    colptr = Vector{Ti}(undef, m+1)
    colptr[1] = 1
    @inbounds for i=1:m-1
        colptr[i+1] = B.uplo == 'U' ? 2i : 2i+1
    end
    colptr[end] = 2m

    rowval = Vector{Ti}(undef, 2m-1)
    @inbounds for i=1:m-1
        rowval[2i-1] = i
        rowval[2i]   = B.uplo == 'U' ? i : i+1
    end
    rowval[end] = m

    nzval = Vector{Tv}(undef, 2m-1)
    nzval[1] = B.dv[1]
    @inbounds for i=1:m-1
        nzval[2i-1] = B.dv[i]
        nzval[2i]   = B.ev[i]
    end
    nzval[end] = B.dv[end]

    return SparseMatrixCSC(m, m, colptr, rowval, nzval)
end
SparseMatrixCSC(D::Diagonal{Tv}) where Tv = SparseMatrixCSC{Tv,Int}(D)
function SparseMatrixCSC{Tv,Ti}(D::Diagonal) where {Tv,Ti}
    m = length(D.diag)
    m == 0 && return SparseMatrixCSC{Tv,Ti}(zeros(Tv, 0, 0))

    nz = count(_isnotzero, D.diag)
    nz_counter = 1

    rowval = Vector{Ti}(undef, nz)
    nzval =  Vector{Tv}(undef, nz)

    nz == 0 && return SparseMatrixCSC{Tv,Ti}(m, m, ones(Ti, m+1), rowval, nzval)

    colptr = Vector{Ti}(undef, m+1)

    @inbounds for i=1:m
        if _isnotzero(D.diag[i])
            colptr[i] = nz_counter
            rowval[nz_counter] = i
            nzval[nz_counter]  = D.diag[i]
            nz_counter += 1
        else
            colptr[i] = nz_counter
        end
    end
    colptr[end] = nz_counter

    return SparseMatrixCSC{Tv,Ti}(m, m, colptr, rowval, nzval)
end

SparseMatrixCSC(M::AbstractMatrix{Tv}) where {Tv} = SparseMatrixCSC{Tv,Int}(M)
SparseMatrixCSC{Tv}(M::AbstractMatrix{Tv}) where {Tv} = SparseMatrixCSC{Tv,Int}(M)
function SparseMatrixCSC{Tv,Ti}(M::AbstractMatrix) where {Tv,Ti}
    require_one_based_indexing(M)
    I = Ti[]
    V = Tv[]
    i = 0
    for v in M
        i += 1
        if _isnotzero(v)
            push!(I, i)
            push!(V, v)
        end
    end
    return sparse_sortedlinearindices!(I, V, size(M)...)
end

function SparseMatrixCSC{Tv,Ti}(M::StridedMatrix) where {Tv,Ti}
    nz = count(_isnotzero, M)
    colptr = zeros(Ti, size(M, 2) + 1)
    nzval = Vector{Tv}(undef, nz)
    rowval = Vector{Ti}(undef, nz)
    colptr[1] = 1
    cnt = 1
    @inbounds for j in axes(M, 2)
        for i in axes(M, 1)
            v = M[i, j]
            if _isnotzero(v)
                rowval[cnt] = i
                nzval[cnt] = v
                cnt += 1
            end
        end
        colptr[j+1] = cnt
    end
    return SparseMatrixCSC(size(M, 1), size(M, 2), colptr, rowval, nzval)
end
SparseMatrixCSC(M::Adjoint{<:Any,<:AbstractSparseMatrixCSC}) = copy(M)
SparseMatrixCSC(M::Transpose{<:Any,<:AbstractSparseMatrixCSC}) = copy(M)
SparseMatrixCSC{Tv}(M::Adjoint{Tv,<:AbstractSparseMatrixCSC{Tv}}) where {Tv} = copy(M)
SparseMatrixCSC{Tv}(M::Transpose{Tv,<:AbstractSparseMatrixCSC{Tv}}) where {Tv} = copy(M)
SparseMatrixCSC{Tv,Ti}(M::Adjoint{Tv,<:AbstractSparseMatrixCSC{Tv,Ti}}) where {Tv,Ti} = copy(M)
SparseMatrixCSC{Tv,Ti}(M::Transpose{Tv,<:AbstractSparseMatrixCSC{Tv,Ti}}) where {Tv,Ti} = copy(M)

# converting from adjoint or transpose sparse matrices to sparse matrices with different eltype
SparseMatrixCSC{Tv}(M::Adjoint{<:Any,<:AbstractSparseMatrixCSC}) where {Tv} = SparseMatrixCSC{Tv}(copy(M))
SparseMatrixCSC{Tv}(M::Transpose{<:Any,<:AbstractSparseMatrixCSC}) where {Tv} = SparseMatrixCSC{Tv}(copy(M))
SparseMatrixCSC{Tv,Ti}(M::Adjoint{<:Any,<:AbstractSparseMatrixCSC}) where {Tv,Ti} = SparseMatrixCSC{Tv,Ti}(copy(M))
SparseMatrixCSC{Tv,Ti}(M::Transpose{<:Any,<:AbstractSparseMatrixCSC}) where {Tv,Ti} = SparseMatrixCSC{Tv,Ti}(copy(M))

# we can only view AbstractQs as columns
SparseMatrixCSC(Q::AbstractQ{Tv}) where {Tv} = SparseMatrixCSC{Tv,Int}(Q)
SparseMatrixCSC{Tv}(Q::AbstractQ{Tv}) where {Tv} = SparseMatrixCSC{Tv,Int}(Q)
SparseMatrixCSC{Tv,Ti}(Q::AbstractQ) where {Tv,Ti} = sparse_with_lmul(Tv, Ti, Q)

"""
    sparse_with_lmul(Tv, Ti, Q) -> SparseMatrixCSC

Helper function that creates a `SparseMatrixCSC{Tv,Ti}` representation of `Q`, where `Q` is
supposed to not have fast `getindex` or not admit an iteration protocol at all, but instead
a fast `lmul!(Q, v)` for dense vectors `v`. The prime example for such `Q`s is the Q factor
of a (sparse) QR decomposition.
"""
function sparse_with_lmul(Tv, Ti, Q)
    colptr = zeros(Ti, size(Q, 2) + 1)
    nzval = Tv[]
    rowval = Ti[]
    col = zeros(eltype(Q), size(Q, 1))

    colptr[1] = 1
    ind = 1
    for j in axes(Q, 2)
        fill!(col, false)
        col[j] = one(Tv)
        lmul!(Q, col)
        for (i, v) in enumerate(col)
            if _isnotzero(v)
                push!(nzval, v)
                push!(rowval, i)
                ind += 1
            end
        end
        colptr[j + 1] = ind
    end
    return SparseMatrixCSC{Tv,Ti}(size(Q)..., colptr, rowval, nzval)
end

# converting from AbstractSparseMatrixCSC to other matrix types
function Matrix(S::AbstractSparseMatrixCSC{Tv}) where Tv
    _checkbuffers(S)
    A = Matrix{Tv}(undef, size(S, 1), size(S, 2))
    copyto!(A, S)
    return A
end
Array(S::AbstractSparseMatrixCSC) = Matrix(S)

convert(T::Type{<:AbstractSparseMatrixCSC}, m::AbstractMatrix) = m isa T ? m : T(m)

convert(T::Type{<:Diagonal},       m::AbstractSparseMatrixCSC) = m isa T ? m :
    isdiag(m) ? T(m) : throw(ArgumentError("matrix cannot be represented as Diagonal"))
convert(T::Type{<:SymTridiagonal}, m::AbstractSparseMatrixCSC) = m isa T ? m :
    issymmetric(m) && isbanded(m, -1, 1) ? T(m) : throw(ArgumentError("matrix cannot be represented as SymTridiagonal"))
convert(T::Type{<:Tridiagonal},    m::AbstractSparseMatrixCSC) = m isa T ? m :
    isbanded(m, -1, 1) ? T(m) : throw(ArgumentError("matrix cannot be represented as Tridiagonal"))
convert(T::Type{<:LowerTriangular}, m::AbstractSparseMatrixCSC) = m isa T ? m :
    istril(m) ? T(m) : throw(ArgumentError("matrix cannot be represented as LowerTriangular"))
convert(T::Type{<:UpperTriangular}, m::AbstractSparseMatrixCSC) = m isa T ? m :
    istriu(m) ? T(m) : throw(ArgumentError("matrix cannot be represented as UpperTriangular"))

float(S::SparseMatrixCSC) = SparseMatrixCSC(size(S, 1), size(S, 2), getcolptr(S), rowvals(S), float(nonzeros(S)))
complex(S::SparseMatrixCSC) = SparseMatrixCSC(size(S, 1), size(S, 2), getcolptr(S), rowvals(S), complex(nonzeros(S)))

"""
    sparse(A::Union{AbstractVector, AbstractMatrix})

Convert a vector or matrix `A` into a sparse array.
Numerical zeros in `A` are turned into structural zeros.

# Examples
```jldoctest
julia> A = Matrix(1.0I, 3, 3)
3×3 Matrix{Float64}:
 1.0  0.0  0.0
 0.0  1.0  0.0
 0.0  0.0  1.0

julia> sparse(A)
3×3 SparseMatrixCSC{Float64, Int64} with 3 stored entries:
 1.0   ⋅    ⋅
  ⋅   1.0   ⋅
  ⋅    ⋅   1.0

julia> [1.0, 0.0, 1.0]
3-element Vector{Float64}:
 1.0
 0.0
 1.0

julia> sparse([1.0, 0.0, 1.0])
3-element SparseVector{Float64, Int64} with 2 stored entries:
  [1]  =  1.0
  [3]  =  1.0
```
"""
sparse(A::AbstractMatrix{Tv}) where {Tv} = convert(SparseMatrixCSC{Tv}, A)

sparse(S::AbstractSparseMatrixCSC) = copy(S)

sparse(Q::AbstractQ) = SparseMatrixCSC(Q)

sparse(T::SymTridiagonal) = SparseMatrixCSC(T)

sparse(T::Tridiagonal) = SparseMatrixCSC(T)

sparse(B::Bidiagonal) = SparseMatrixCSC(B)

sparse(D::Diagonal) = SparseMatrixCSC(D)

"""
    sparse(I, J, V,[ m, n, combine])

Create a sparse matrix `S` of dimensions `m x n` such that `S[I[k], J[k]] = V[k]`. The
`combine` function is used to combine duplicates. If `m` and `n` are not specified, they
are set to `maximum(I)` and `maximum(J)` respectively. If the `combine` function is not
supplied, `combine` defaults to `+` unless the elements of `V` are Booleans in which case
`combine` defaults to `|`. All elements of `I` must satisfy `1 <= I[k] <= m`, and all
elements of `J` must satisfy `1 <= J[k] <= n`. Numerical zeros in (`I`, `J`, `V`) are
retained as structural nonzeros; to drop numerical zeros, use [`dropzeros!`](@ref).

For additional documentation and an expert driver, see `SparseArrays.sparse!`.

# Examples
```jldoctest
julia> Is = [1; 2; 3];

julia> Js = [1; 2; 3];

julia> Vs = [1; 2; 3];

julia> sparse(Is, Js, Vs)
3×3 SparseMatrixCSC{Int64, Int64} with 3 stored entries:
 1  ⋅  ⋅
 ⋅  2  ⋅
 ⋅  ⋅  3
```
"""
function sparse(I::AbstractVector{Ti}, J::AbstractVector{Ti}, V::AbstractVector{Tv}, m::Integer, n::Integer, combine) where {Tv,Ti<:Integer}
    require_one_based_indexing(I, J, V)
    coolen = length(I)
    if length(J) != coolen || length(V) != coolen
        throw(ArgumentError(string("the first three arguments' lengths must match, ",
              "length(I) (=$(length(I))) == length(J) (= $(length(J))) == length(V) (= ",
              "$(length(V)))")))
    end
    if Base.hastypemax(Ti) && coolen >= typemax(Ti)
        throw(ArgumentError("the index type $Ti cannot hold $coolen elements; use a larger index type"))
    end
    if m == 0 || n == 0 || coolen == 0
        if coolen != 0
            if n == 0
                throw(ArgumentError("column indices J[k] must satisfy 1 <= J[k] <= n"))
            elseif m == 0
                throw(ArgumentError("row indices I[k] must satisfy 1 <= I[k] <= m"))
            end
        end
        SparseMatrixCSC(m, n, fill(one(Ti), n+1), Vector{Ti}(), Vector{Tv}())
    else
        # Allocate storage for CSR form
        csrrowptr = Vector{Ti}(undef, m+1)
        csrcolval = Vector{Ti}(undef, coolen)
        csrnzval = Vector{Tv}(undef, coolen)

        # Allocate storage for the CSC form's column pointers and a necessary workspace
        csccolptr = Vector{Ti}(undef, n+1)
        klasttouch = Vector{Ti}(undef, n)

        # Allocate empty arrays for the CSC form's row and nonzero value arrays
        # The parent method called below automagically resizes these arrays
        cscrowval = Vector{Ti}()
        cscnzval = Vector{Tv}()

        sparse!(I, J, V, m, n, combine, klasttouch,
                csrrowptr, csrcolval, csrnzval,
                csccolptr, cscrowval, cscnzval)
    end
end

sparse(I::AbstractVector, J::AbstractVector, V::AbstractVector, m::Integer, n::Integer, combine) =
    sparse(AbstractVector{Int}(I), AbstractVector{Int}(J), V, m, n, combine)

"""
    sparse!(I::AbstractVector{Ti}, J::AbstractVector{Ti}, V::AbstractVector{Tv},
            m::Integer, n::Integer, combine, klasttouch::Vector{Ti},
            csrrowptr::Vector{Ti}, csrcolval::Vector{Ti}, csrnzval::Vector{Tv},
            [csccolptr::Vector{Ti}], [cscrowval::Vector{Ti}, cscnzval::Vector{Tv}] ) where {Tv,Ti<:Integer}

Parent of and expert driver for [`sparse`](@ref);
see [`sparse`](@ref) for basic usage. This method
allows the user to provide preallocated storage for `sparse`'s intermediate objects and
result as described below. This capability enables more efficient successive construction
of [`SparseMatrixCSC`](@ref)s from coordinate representations, and also enables extraction
of an unsorted-column representation of the result's transpose at no additional cost.

This method consists of three major steps: (1) Counting-sort the provided coordinate
representation into an unsorted-row CSR form including repeated entries. (2) Sweep through
the CSR form, simultaneously calculating the desired CSC form's column-pointer array,
detecting repeated entries, and repacking the CSR form with repeated entries combined;
this stage yields an unsorted-row CSR form with no repeated entries. (3) Counting-sort the
preceding CSR form into a fully-sorted CSC form with no repeated entries.

Input arrays `csrrowptr`, `csrcolval`, and `csrnzval` constitute storage for the
intermediate CSR forms and require `length(csrrowptr) >= m + 1`,
`length(csrcolval) >= length(I)`, and `length(csrnzval >= length(I))`. Input
array `klasttouch`, workspace for the second stage, requires `length(klasttouch) >= n`.
Optional input arrays `csccolptr`, `cscrowval`, and `cscnzval` constitute storage for the
returned CSC form `S`. If necessary, these are resized automatically to satisfy
`length(csccolptr) = n + 1`, `length(cscrowval) = nnz(S)` and `length(cscnzval) = nnz(S)`; hence, if `nnz(S)` is
unknown at the outset, passing in empty vectors of the appropriate type (`Vector{Ti}()`
and `Vector{Tv}()` respectively) suffices, or calling the `sparse!` method
neglecting `cscrowval` and `cscnzval`.

On return, `csrrowptr`, `csrcolval`, and `csrnzval` contain an unsorted-column
representation of the result's transpose.

You may reuse the input arrays' storage (`I`, `J`, `V`) for the output arrays
(`csccolptr`, `cscrowval`, `cscnzval`). For example, you may call
`sparse!(I, J, V, csrrowptr, csrcolval, csrnzval, I, J, V)`.
Note that they will be resized to satisfy the conditions above.

For the sake of efficiency, this method performs no argument checking beyond
`1 <= I[k] <= m` and `1 <= J[k] <= n`. Use with care. Testing with `--check-bounds=yes`
is wise.

This method runs in `O(m, n, length(I))` time. The HALFPERM algorithm described in
F. Gustavson, "Two fast algorithms for sparse matrices: multiplication and permuted
transposition," ACM TOMS 4(3), 250-269 (1978) inspired this method's use of a pair of
counting sorts.
"""
function sparse!(I::AbstractVector{Ti}, J::AbstractVector{Ti}, V::AbstractVector{Tv},
        m::Integer, n::Integer, combine, klasttouch::Vector{Tj},
        csrrowptr::Vector{Tj}, csrcolval::Vector{Ti}, csrnzval::Vector{Tv},
        csccolptr::Vector{Ti}, cscrowval::Vector{Ti}, cscnzval::Vector{Tv}) where {Tv,Ti<:Integer,Tj<:Integer}

    require_one_based_indexing(I, J, V)
    sparse_check_Ti(m, n, Ti)
    sparse_check_length("I", I, 0, Tj)

    # This method is also used internally by spzeros! to build the sparsity pattern without
    # caring about the values. This is communicated by passing combine=nothing and in this
    # case V and csrnzval should *not* be accessed. When called from spzeros! they will both
    # alias cscnzval, which will be resized and filled with zero(Tv).
    only_sparsity_pattern = combine === nothing

    # Compute the CSR form's row counts and store them shifted forward by one in csrrowptr
    fill!(csrrowptr, Tj(0))
    coolen = length(I)
    length(J) >= coolen || throw(ArgumentError("J need length >= length(I) = $coolen"))
    only_sparsity_pattern || length(V) >= coolen || throw(ArgumentError("V need length >= length(I) = $coolen"))

    @inbounds for k in 1:coolen
        Ik = I[k]
        if 1 > Ik || m < Ik
            throw(ArgumentError("row indices I[k] must satisfy 1 <= I[k] <= m"))
        end
        csrrowptr[Ik+1] += Tj(1)
    end

    # Compute the CSR form's rowptrs and store them shifted forward by one in csrrowptr
    countsum = Tj(1)
    csrrowptr[1] = Tj(1)
    @inbounds for i in 2:(m+1)
        overwritten = csrrowptr[i]
        csrrowptr[i] = countsum
        countsum += overwritten
    end

    # Counting-sort the column and nonzero values from J and V into csrcolval and csrnzval
    # Tracking write positions in csrrowptr corrects the row pointers
    @inbounds for k in 1:coolen
        Ik, Jk = I[k], J[k]
        if Ti(1) > Jk || Ti(n) < Jk
            throw(ArgumentError("column indices J[k] must satisfy 1 <= J[k] <= n"))
        end
        csrk = csrrowptr[Ik+1]
        @assert csrk >= Tj(1) "index into csrcolval exceeds typemax(Ti)"
        csrrowptr[Ik+1] = csrk + Tj(1)
        csrcolval[csrk] = Jk
        if !only_sparsity_pattern
            csrnzval[csrk] = V[k]
        end
    end
    # This completes the unsorted-row, has-repeats CSR form's construction

    # The output array csccolptr can now be resized safely even if aliased with I
    resize!(csccolptr, n + 1)

    # Sweep through the CSR form, simultaneously (1) calculating the CSC form's column
    # counts and storing them shifted forward by one in csccolptr; (2) detecting repeated
    # entries; and (3) repacking the CSR form with the repeated entries combined.
    #
    # Minimizing extraneous communication and nonlocality of reference, primarily by using
    # only a single auxiliary array in this step, is the key to this method's performance.
    fill!(csccolptr, Ti(0))
    fill!(klasttouch, Tj(0))
    writek = Tj(1)
    newcsrrowptri = Ti(1)
    origcsrrowptri = Tj(1)
    origcsrrowptrip1 = csrrowptr[2]
    @inbounds for i in 1:m
        for readk in origcsrrowptri:(origcsrrowptrip1-Tj(1))
            j = csrcolval[readk]
            if klasttouch[j] < newcsrrowptri
                klasttouch[j] = writek
                if writek != readk
                    csrcolval[writek] = j
                    if !only_sparsity_pattern
                        csrnzval[writek] = csrnzval[readk]
                    end
                end
                writek += Tj(1)
                csccolptr[j+1] += Ti(1)
            elseif !only_sparsity_pattern
                klt = klasttouch[j]
                csrnzval[klt] = combine(csrnzval[klt], csrnzval[readk])
            end
        end
        newcsrrowptri = writek
        origcsrrowptri = origcsrrowptrip1
        origcsrrowptrip1 != writek && (csrrowptr[i+1] = writek)
        i < m && (origcsrrowptrip1 = csrrowptr[i+2])
    end

    # Compute the CSC form's colptrs and store them shifted forward by one in csccolptr
    countsum = Tj(1)
    csccolptr[1] = Ti(1)
    @inbounds for j in 2:(n+1)
        overwritten = csccolptr[j]
        csccolptr[j] = countsum
        countsum += overwritten
        Base.hastypemax(Ti) && (countsum <= typemax(Ti) || throw(ArgumentError("more than typemax(Ti)-1 == $(typemax(Ti)-1) entries")))
    end

    # Now knowing the CSC form's entry count, resize cscrowval and cscnzval
    # Note: This is done unconditionally to appease the buffer checks in the SparseMatrixCSC
    #       constructor. If these checks are lifted this resizing is only needed if the
    #       buffers are too short. csccolptr is resized above.
    cscnnz = countsum - Tj(1)
    resize!(cscrowval, cscnnz)
    resize!(cscnzval, cscnnz)

    # Finally counting-sort the row and nonzero values from the CSR form into cscrowval and
    # cscnzval. Tracking write positions in csccolptr corrects the column pointers.
    @inbounds for i in 1:m
        for csrk in csrrowptr[i]:(csrrowptr[i+1]-Tj(1))
            j = csrcolval[csrk]
            csck = csccolptr[j+1]
            csccolptr[j+1] = csck + Ti(1)
            cscrowval[csck] = i
            cscnzval[csck] = only_sparsity_pattern ? zero(Tv) : csrnzval[csrk]
        end
    end

    SparseMatrixCSC(m, n, csccolptr, cscrowval, cscnzval)
end
function sparse!(I::AbstractVector{Ti}, J::AbstractVector{Ti},
        V::AbstractVector{Tv}, m::Integer, n::Integer, combine, klasttouch::Vector{Tj},
        csrrowptr::Vector{Tj}, csrcolval::Vector{Ti}, csrnzval::Vector{Tv},
        csccolptr::Vector{Ti}) where {Tv,Ti<:Integer,Tj<:Integer}
    sparse!(I, J, V, m, n, combine, klasttouch,
            csrrowptr, csrcolval, csrnzval,
            csccolptr, Vector{Ti}(), Vector{Tv}())
end
function sparse!(I::AbstractVector{Ti}, J::AbstractVector{Ti},
        V::AbstractVector{Tv}, m::Integer, n::Integer, combine, klasttouch::Vector{Tj},
        csrrowptr::Vector{Tj}, csrcolval::Vector{Ti}, csrnzval::Vector{Tv}) where {Tv,Ti<:Integer,Tj<:Integer}
    sparse!(I, J, V, m, n, combine, klasttouch,
            csrrowptr, csrcolval, csrnzval,
            Vector{Ti}(undef, n+1), Vector{Ti}(), Vector{Tv}())
end

"""
    SparseArrays.sparse!(I, J, V, [m, n, combine]) -> SparseMatrixCSC

Variant of `sparse!` that re-uses the input vectors (`I`, `J`, `V`) for the final matrix
storage. After construction the input vectors will alias the matrix buffers; `S.colptr ===
I`, `S.rowval === J`, and `S.nzval === V` holds, and they will be `resize!`d as necessary.

Note that some work buffers will still be allocated. Specifically, this method is a
convenience wrapper around `sparse!(I, J, V, m, n, combine, klasttouch, csrrowptr,
csrcolval, csrnzval, csccolptr, cscrowval, cscnzval)` where this method allocates
`klasttouch`, `csrrowptr`, `csrcolval`, and `csrnzval` of appropriate size, but reuses `I`,
`J`, and `V` for `csccolptr`, `cscrowval`, and `cscnzval`.

Arguments `m`, `n`, and `combine` defaults to `maximum(I)`, `maximum(J)`, and `+`,
respectively.

!!! compat "Julia 1.10"
    This method requires Julia version 1.10 or later.
"""
function sparse!(I::AbstractVector{Ti}, J::AbstractVector{Ti}, V::AbstractVector{Tv},
                 m::Integer=dimlub(I), n::Integer=dimlub(J), combine::Function=+) where {Tv, Ti<:Integer}
    klasttouch = Vector{Ti}(undef, n)
    csrrowptr  = Vector{Ti}(undef, m + 1)
    csrcolval  = Vector{Ti}(undef, length(I))
    csrnzval   = Vector{Tv}(undef, length(I))
    sparse!(I, J, V, Int(m), Int(n), combine, klasttouch, csrrowptr, csrcolval, csrnzval, I, J, V)
end

dimlub(I) = isempty(I) ? 0 : Int(maximum(I)) #least upper bound on required sparse matrix dimension

sparse(I,J,v::Number) = sparse(I, J, fill(v,length(I)))

sparse(I,J,V::AbstractVector) = sparse(I, J, V, dimlub(I), dimlub(J))

sparse(I,J,v::Number,m,n) = sparse(I, J, fill(v,length(I)), Int(m), Int(n))

sparse(I,J,V::AbstractVector,m,n) = sparse(I, J, V, Int(m), Int(n), +)

sparse(I,J,V::AbstractVector{Bool},m,n) = sparse(I, J, V, Int(m), Int(n), |)

sparse(I,J,v::Number,m,n,combine::Function) = sparse(I, J, fill(v,length(I)), Int(m), Int(n), combine)

## Transposition and permutation methods

"""
    halfperm!(X::AbstractSparseMatrixCSC{Tv,Ti}, A::AbstractSparseMatrixCSC{TvA,Ti},
              q::AbstractVector{<:Integer}, f::Function = identity) where {Tv,TvA,Ti}

Column-permute and transpose `A`, simultaneously applying `f` to each entry of `A`, storing
the result `(f(A)Q)^T` (`map(f, transpose(A[:,q]))`) in `X`.

Element type `Tv` of `X` must match `f(::TvA)`, where `TvA` is the element type of `A`.
`X`'s dimensions must match those of `transpose(A)` (`size(X, 1) == size(A, 2)` and
`size(X, 2) == size(A, 1)`), and `X` must have enough storage to accommodate all allocated
entries in `A` (`length(rowvals(X)) >= nnz(A)` and `length(nonzeros(X)) >= nnz(A)`).
Column-permutation `q`'s length must match `A`'s column count (`length(q) == size(A, 2)`).

This method is the parent of several methods performing transposition and permutation
operations on [`SparseMatrixCSC`](@ref)s. As this method performs no argument checking,
prefer the safer child methods (`[c]transpose[!]`, `permute[!]`) to direct use.

This method implements the `HALFPERM` algorithm described in F. Gustavson, "Two fast
algorithms for sparse matrices: multiplication and permuted transposition," ACM TOMS 4(3),
250-269 (1978). The algorithm runs in `O(size(A, 1), size(A, 2), nnz(A))` time and requires no space
beyond that passed in.
"""
function halfperm!(X::AbstractSparseMatrixCSC{Tv,Ti}, A::AbstractSparseMatrixCSC{TvA,Ti},
        q::AbstractVector{<:Integer}, f::F = identity) where {Tv,TvA,Ti,F<:Function}
    _computecolptrs_halfperm!(X, A)
    _distributevals_halfperm!(X, A, q, f)
    return X
end
"""
Helper method for `halfperm!`. Computes `transpose(A[:,q])`'s column pointers, storing them
shifted one position forward in `getcolptr(X)`; `_distributevals_halfperm!` fixes this shift.
"""
function _computecolptrs_halfperm!(X::AbstractSparseMatrixCSC{Tv,Ti}, A::AbstractSparseMatrixCSC{TvA,Ti}) where {Tv,TvA,Ti}
    # Compute `transpose(A[:,q])`'s column counts. Store shifted forward one position in getcolptr(X).
    fill!(getcolptr(X), 0)
    @inbounds for k in 1:nnz(A)
        getcolptr(X)[rowvals(A)[k] + 1] += 1
    end
    # Compute `transpose(A[:,q])`'s column pointers. Store shifted forward one position in getcolptr(X).
    getcolptr(X)[1] = 1
    countsum = 1
    @inbounds for k in 2:(size(A, 1) + 1)
        overwritten = getcolptr(X)[k]
        getcolptr(X)[k] = countsum
        countsum += overwritten
    end
end
"""
Helper method for `halfperm!`. With `transpose(A[:,q])`'s column pointers shifted one
position forward in `getcolptr(X)`, computes `map(f, transpose(A[:,q]))` by appropriately
distributing `rowvals(A)` and `f`-transformed `nonzeros(A)` into `rowvals(X)` and `nonzeros(X)`
respectively. Simultaneously fixes the one-position-forward shift in `getcolptr(X)`.
"""
@noinline function _distributevals_halfperm!(X::AbstractSparseMatrixCSC{Tv,Ti},
        A::AbstractSparseMatrixCSC{TvA,Ti}, q::AbstractVector{<:Integer}, f::F) where {Tv,TvA,Ti,F<:Function}
    resize!(nonzeros(X), nnz(A))
    resize!(rowvals(X), nnz(A))
    @inbounds for Xi in axes(A,2)
        Aj = q[Xi]
        for Ak in nzrange(A, Aj)
            Ai = rowvals(A)[Ak]
            Xk = getcolptr(X)[Ai + 1]
            rowvals(X)[Xk] = Xi
            nonzeros(X)[Xk] = f(nonzeros(A)[Ak])
            getcolptr(X)[Ai + 1] += 1
        end
    end
    return # kill potential type instability
end
"""
    ftranspose!(X::AbstractSparseMatrixCSC{Tv,Ti}, A::AbstractSparseMatrixCSC{Tv,Ti}, f::Function) where {Tv,Ti}

Transpose `A` and store it in `X` while applying the function `f` to the non-zero elements.
Does not remove the zeros created by `f`. `size(X)` must be equal to `size(transpose(A))`.
No additional memory is allocated other than resizing the rowval and nzval of `X`, if needed.

See `halfperm!`
"""
function ftranspose!(X::AbstractSparseMatrixCSC{Tv,Ti}, A::AbstractSparseMatrixCSC{Tv,Ti}, f::F) where {Tv,Ti,F<:Function}
    # Check compatibility of source argument A and destination argument X
    if size(X, 2) != size(A, 1)
        throw(DimensionMismatch(string("destination argument `X`'s column count, ",
            "`size(X, 2) (= $(size(X, 2)))`, must match source argument `A`'s row count, `size(A, 1) (= $(size(A, 1)))`")))
    elseif size(X, 1) != size(A, 2)
        throw(DimensionMismatch(string("destination argument `X`'s row count, ",
            "`size(X, 1) (= $(size(X, 1)))`, must match source argument `A`'s column count, `size(A, 2) (= $(size(A, 2)))`")))
    end
    halfperm!(X, A, axes(A,2), f)
end

"""
    transpose!(X::AbstractSparseMatrixCSC{Tv,Ti}, A::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}

Transpose the matrix `A` and stores it in the matrix `X`.
`size(X)` must be equal to `size(transpose(A))`.
No additional memory is allocated other than resizing the rowval and nzval of `X`, if needed.

See `halfperm!`
"""
transpose!(X::AbstractSparseMatrixCSC{Tv,Ti}, A::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti} = ftranspose!(X, A, identity)

"""
    adjoint!(X::AbstractSparseMatrixCSC{Tv,Ti}, A::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}

Transpose the matrix `A` and stores the adjoint of the elements in the matrix `X`.
`size(X)` must be equal to `size(transpose(A))`.
No additional memory is allocated other than resizing the rowval and nzval of `X`, if needed.

See `halfperm!`
"""
adjoint!(X::AbstractSparseMatrixCSC{Tv,Ti}, A::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti} = ftranspose!(X, A, conj)

# manually specifying eltype allows to avoid calling return_type of f on TvA
function ftranspose(A::AbstractSparseMatrixCSC{TvA,Ti}, f::Function, eltype::Type{Tv} = TvA) where {Tv,TvA,Ti}
    X = SparseMatrixCSC(size(A, 2), size(A, 1),
                        ones(Ti, size(A, 1)+1),
                        Vector{Ti}(undef, 0),
                        Vector{Tv}(undef, 0))
    sizehint!(X, nnz(A))
    return @if_move_fixed A halfperm!(X, A, axes(A,2), f)
end

adjoint(A::AbstractSparseMatrixCSC) = Adjoint(A)
transpose(A::AbstractSparseMatrixCSC) = Transpose(A)
Base.copy(A::Adjoint{<:Any,<:AbstractSparseMatrixCSC}) =
    ftranspose(A.parent, x -> adjoint(copy(x)), eltype(A))
Base.copy(A::Transpose{<:Any,<:AbstractSparseMatrixCSC}) =
    ftranspose(A.parent, x -> transpose(copy(x)), eltype(A))
function Base.permutedims(A::AbstractSparseMatrixCSC, (a,b))
    (a, b) == (2, 1) && return ftranspose(A, identity)
    (a, b) == (1, 2) && return copy(A)
    throw(ArgumentError("no valid permutation of dimensions"))
end

"""
    unchecked_noalias_permute!(X::AbstractSparseMatrixCSC{Tv,Ti},
        A::AbstractSparseMatrixCSC{Tv,Ti}, p::AbstractVector{<:Integer},
        q::AbstractVector{<:Integer}, C::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}

See [`permute!`](@ref) for basic usage. Parent of `permute[!]`
methods operating on `SparseMatrixCSC`s that assume none of `X`, `A`, and `C` alias each
other. As this method performs no argument checking, prefer the safer child methods
(`permute[!]`) to direct use.

This method consists of two major steps: (1) Column-permute (`Q`,`I[:,q]`) and transpose `A`
to generate intermediate result `(AQ)^T` (`transpose(A[:,q])`) in `C`. (2) Column-permute
(`P^T`, I[:,p]) and transpose intermediate result `(AQ)^T` to generate result
`((AQ)^T P^T)^T = PAQ` (`A[p,q]`) in `X`.

The first step is a call to `halfperm!`, and the second is a variant on `halfperm!` that
avoids an unnecessary length-`nnz(A)` array-sweep and associated recomputation of column
pointers. See [`halfperm!`](:func:SparseArrays.halfperm!) for additional algorithmic
information.

See also `unchecked_aliasing_permute!`.
"""
function unchecked_noalias_permute!(X::AbstractSparseMatrixCSC{Tv,Ti},
        A::AbstractSparseMatrixCSC{Tv,Ti}, p::AbstractVector{<:Integer},
        q::AbstractVector{<:Integer}, C::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}
    halfperm!(C, A, q)
    _computecolptrs_permute!(X, A, q, getcolptr(X))
    _distributevals_halfperm!(X, C, p, identity)
    return X
end
"""
    unchecked_aliasing_permute!(A::AbstractSparseMatrixCSC{Tv,Ti},
        p::AbstractVector{<:Integer}, q::AbstractVector{<:Integer},
        C::AbstractSparseMatrixCSC{Tv,Ti}, workcolptr::Vector{Ti}) where {Tv,Ti}

See [`permute!`](@ref) for basic usage. Parent of `permute!`
methods operating on [`SparseMatrixCSC`](@ref)s where the source and destination matrices
are the same. See `unchecked_noalias_permute!`
for additional information; these methods are identical but for this method's requirement of
the additional `workcolptr`, `length(workcolptr) >= size(A, 2) + 1`, which enables efficient
handling of the source-destination aliasing.
"""
function unchecked_aliasing_permute!(A::AbstractSparseMatrixCSC{Tv,Ti},
        p::AbstractVector{<:Integer}, q::AbstractVector{<:Integer},
        C::AbstractSparseMatrixCSC{Tv,Ti}, workcolptr::Vector{Ti}) where {Tv,Ti}
    halfperm!(C, A, q)
    _computecolptrs_permute!(A, A, q, workcolptr)
    _distributevals_halfperm!(A, C, p, identity)
    return A
end
"""
Helper method for `unchecked_noalias_permute!` and `unchecked_aliasing_permute!`.
Computes `PAQ`'s column pointers, storing them shifted one position forward in `getcolptr(X)`;
`_distributevals_halfperm!` fixes this shift. Saves some work relative to
`_computecolptrs_halfperm!` as described in `uncheckednoalias_permute!`'s documentation.
"""
function _computecolptrs_permute!(X::AbstractSparseMatrixCSC{Tv,Ti},
        A::AbstractSparseMatrixCSC{Tv,Ti}, q::AbstractVector{<:Integer}, workcolptr::Vector{Ti}) where {Tv,Ti}
    # Compute `A[p,q]`'s column counts. Store shifted forward one position in workcolptr.
    @inbounds for k in axes(A,2)
        workcolptr[k+1] = getcolptr(A)[q[k] + 1] - getcolptr(A)[q[k]]
    end
    # Compute `A[p,q]`'s column pointers. Store shifted forward one position in getcolptr(X).
    getcolptr(X)[1] = 1
    countsum = 1
    @inbounds for k in 2:(size(X, 2) + 1)
        overwritten = workcolptr[k]
        getcolptr(X)[k] = countsum
        countsum += overwritten
    end
end

"""
Helper method for `permute` and `permute!` methods operating on `SparseMatrixCSC`s.
Checks compatibility of source argument `A`, row-permutation argument `p`, and
column-permutation argument `q`.
"""
function _checkargs_sourcecompatperms_permute!(A::AbstractSparseMatrixCSC,
        p::AbstractVector{<:Integer}, q::AbstractVector{<:Integer})
    require_one_based_indexing(p, q)
    if length(q) != size(A, 2)
         throw(DimensionMismatch(string("the length of column-permutation argument `q`, ",
             "`length(q) (= $(length(q)))`, must match source argument `A`'s column ",
             "count, `size(A, 2) (= $(size(A, 2)))`")))
     elseif length(p) != size(A, 1)
         throw(DimensionMismatch(string("the length of row-permutation argument `p`, ",
             "`length(p) (= $(length(p)))`, must match source argument `A`'s row count, ",
             "`size(A, 1) (= $(size(A, 1)))`")))
     end
end
"""
Helper method for `permute` and `permute!` methods operating on `SparseMatrixCSC`s.
Checks whether row- and column- permutation arguments `p` and `q` are valid permutations.
"""
function _checkargs_permutationsvalid_permute!(
        p::AbstractVector{<:Integer}, pcheckspace::Vector{Ti},
        q::AbstractVector{<:Integer}, qcheckspace::Vector{Ti}) where Ti<:Integer
    if !_ispermutationvalid_permute!(p, pcheckspace)
        throw(ArgumentError("row-permutation argument `p` must be a valid permutation"))
    elseif !_ispermutationvalid_permute!(q, qcheckspace)
        throw(ArgumentError("column-permutation argument `q` must be a valid permutation"))
    end
end
function _ispermutationvalid_permute!(perm::AbstractVector{<:Integer},
        checkspace::Vector{<:Integer})
    require_one_based_indexing(perm)
    n = length(perm)
    checkspace[1:n] .= 0
    for k in perm
        (0 < k ≤ n) && ((checkspace[k] ⊻= 1) == 1) || return false
    end
    return true
end
"""
Helper method for `permute` and `permute!` methods operating on `SparseMatrixCSC`s.
Checks compatibility of source argument `A` and destination argument `X`.
"""
function _checkargs_sourcecompatdest_permute!(A::AbstractSparseMatrixCSC{Tv,Ti},
        X::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}
    if size(X, 1) != size(A, 1)
        throw(DimensionMismatch(string("destination argument `X`'s row count, ",
            "`size(X, 1) (= $(size(X, 1)))`, must match source argument `A`'s row count, `size(A, 1) (= $(size(A, 1)))`")))
    elseif size(X, 2) != size(A, 2)
        throw(DimensionMismatch(string("destination argument `X`'s column count, ",
            "`size(X, 2) (= $(size(X, 2)))`, must match source argument `A`'s column count, `size(A, 2) (= $(size(A, 2)))`")))
    elseif length(rowvals(X)) < nnz(A)
        throw(ArgumentError(string("the length of destination argument `X`'s `rowval` ",
            "array, `length(rowvals(X)) (= $(length(rowvals(X))))`, must be greater than or ",
            "equal to source argument `A`'s allocated entry count, `nnz(A) (= $(nnz(A)))`")))
    elseif length(nonzeros(X)) < nnz(A)
        throw(ArgumentError(string("the length of destination argument `X`'s `nzval` ",
            "array, `length(nonzeros(X)) (= $(length(nonzeros(X))))`, must be greater than or ",
            "equal to source argument `A`'s allocated entry count, `nnz(A) (= $(nnz(A)))`")))
    end
end
"""
Helper method for `permute` and `permute!` methods operating on `SparseMatrixCSC`s.
Checks compatibility of source argument `A` and intermediate result argument `C`.
"""
function _checkargs_sourcecompatworkmat_permute!(A::AbstractSparseMatrixCSC{Tv,Ti},
        C::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}
    if size(C, 2) != size(A, 1)
        throw(DimensionMismatch(string("intermediate result argument `C`'s column count, ",
            "`size(C, 2) (= $(size(C, 2)))`, must match source argument `A`'s row count, `size(A, 1) (= $(size(A, 1)))`")))
    elseif size(C, 1) != size(A, 2)
        throw(DimensionMismatch(string("intermediate result argument `C`'s row count, ",
            "`size(C, 1) (= $(size(C, 1)))`, must match source argument `A`'s column count, `size(A, 2) (= $(size(A, 2)))`")))
    elseif length(rowvals(C)) < nnz(A)
        throw(ArgumentError(string("the length of intermediate result argument `C`'s ",
            "`rowval` array, `length(rowvals(C)) (= $(length(rowvals(C))))`, must be greater than ",
            "or equal to source argument `A`'s allocated entry count, `nnz(A) (= $(nnz(A)))`")))
    elseif length(nonzeros(C)) < nnz(A)
        throw(ArgumentError(string("the length of intermediate result argument `C`'s ",
            "`rowval` array, `length(nonzeros(C)) (= $(length(nonzeros(C))))`, must be greater than ",
            "or equal to source argument `A`'s allocated entry count, `nnz(A)` (= $(nnz(A)))")))
    end
end
"""
Helper method for `permute` and `permute!` methods operating on `SparseMatrixCSC`s.
Checks compatibility of source argument `A` and workspace argument `workcolptr`.
"""
function _checkargs_sourcecompatworkcolptr_permute!(A::AbstractSparseMatrixCSC{Tv,Ti},
        workcolptr::Vector{Ti}) where {Tv,Ti}
    if length(workcolptr) <= size(A, 2)
        throw(DimensionMismatch(string("argument `workcolptr`'s length, ",
            "`length(workcolptr) (= $(length(workcolptr)))`, must exceed source argument ",
            "`A`'s column count, `size(A, 2) (= $(size(A, 2)))`")))
    end
end
"""
    permute!(X::AbstractSparseMatrixCSC{Tv,Ti}, A::AbstractSparseMatrixCSC{Tv,Ti},
             p::AbstractVector{<:Integer}, q::AbstractVector{<:Integer},
             [C::AbstractSparseMatrixCSC{Tv,Ti}]) where {Tv,Ti}

Bilaterally permute `A`, storing result `PAQ` (`A[p,q]`) in `X`. Stores intermediate result
`(AQ)^T` (`transpose(A[:,q])`) in optional argument `C` if present. Requires that none of
`X`, `A`, and, if present, `C` alias each other; to store result `PAQ` back into `A`, use
the following method lacking `X`:

    permute!(A::AbstractSparseMatrixCSC{Tv,Ti}, p::AbstractVector{<:Integer},
             q::AbstractVector{<:Integer}[, C::AbstractSparseMatrixCSC{Tv,Ti},
             [workcolptr::Vector{Ti}]]) where {Tv,Ti}

`X`'s dimensions must match those of `A` (`size(X, 1) == size(A, 1)` and `size(X, 2) == size(A, 2)`), and `X` must
have enough storage to accommodate all allocated entries in `A` (`length(rowvals(X)) >= nnz(A)`
and `length(nonzeros(X)) >= nnz(A)`). Column-permutation `q`'s length must match `A`'s column
count (`length(q) == size(A, 2)`). Row-permutation `p`'s length must match `A`'s row count
(`length(p) == size(A, 1)`).

`C`'s dimensions must match those of `transpose(A)` (`size(C, 1) == size(A, 2)` and `size(C, 2) == size(A, 1)`), and `C`
must have enough storage to accommodate all allocated entries in `A` (`length(rowvals(C)) >= nnz(A)`
and `length(nonzeros(C)) >= nnz(A)`).

For additional (algorithmic) information, and for versions of these methods that forgo
argument checking, see (unexported) parent methods `unchecked_noalias_permute!`
and `unchecked_aliasing_permute!`.

See also [`permute`](@ref).
"""
function permute!(X::AbstractSparseMatrixCSC{Tv,Ti}, A::AbstractSparseMatrixCSC{Tv,Ti},
        p::AbstractVector{<:Integer}, q::AbstractVector{<:Integer}) where {Tv,Ti}
    _checkargs_sourcecompatdest_permute!(A, X)
    _checkargs_sourcecompatperms_permute!(A, p, q)
    # bypass strict buffer checking
    C = spzeros(Tv, Ti, size(A,2), size(A,1))
    resize!(getrowval(C), nnz(A))
    resize!(getnzval(C), nnz(A))

    _checkargs_permutationsvalid_permute!(p, getcolptr(C), q, getcolptr(X))
    unchecked_noalias_permute!(X, A, p, q, C)
end
function permute!(X::AbstractSparseMatrixCSC{Tv,Ti}, A::AbstractSparseMatrixCSC{Tv,Ti},
        p::AbstractVector{<:Integer}, q::AbstractVector{<:Integer},
        C::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}
    _checkargs_sourcecompatdest_permute!(A, X)
    _checkargs_sourcecompatperms_permute!(A, p, q)
    _checkargs_sourcecompatworkmat_permute!(A, C)
    _checkargs_permutationsvalid_permute!(p, getcolptr(C), q, getcolptr(X))
    unchecked_noalias_permute!(X, A, p, q, C)
end
function permute!(A::AbstractSparseMatrixCSC{Tv,Ti}, p::AbstractVector{<:Integer},
        q::AbstractVector{<:Integer}) where {Tv,Ti}
    _checkargs_sourcecompatperms_permute!(A, p, q)
    C = spzeros(Tv, Ti, size(A,2), size(A,1))
    resize!(getrowval(C), nnz(A))
    resize!(getnzval(C), nnz(A))
    workcolptr = Vector{Ti}(undef, size(A, 2) + 1)
    _checkargs_permutationsvalid_permute!(p, getcolptr(C), q, workcolptr)
    unchecked_aliasing_permute!(A, p, q, C, workcolptr)
end
function permute!(A::AbstractSparseMatrixCSC{Tv,Ti}, p::AbstractVector{<:Integer},
        q::AbstractVector{<:Integer}, C::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}
    _checkargs_sourcecompatperms_permute!(A, p, q)
    _checkargs_sourcecompatworkmat_permute!(A, C)
    workcolptr = Vector{Ti}(undef, size(A, 2) + 1)
    _checkargs_permutationsvalid_permute!(p, getcolptr(C), q, workcolptr)
    unchecked_aliasing_permute!(A, p, q, C, workcolptr)
end
function permute!(A::AbstractSparseMatrixCSC{Tv,Ti}, p::AbstractVector{<:Integer},
        q::AbstractVector{<:Integer}, C::AbstractSparseMatrixCSC{Tv,Ti},
        workcolptr::Vector{Ti}) where {Tv,Ti}
    _checkargs_sourcecompatperms_permute!(A, p, q)
    _checkargs_sourcecompatworkmat_permute!(A, C)
    _checkargs_sourcecompatworkcolptr_permute!(A, workcolptr)
    _checkargs_permutationsvalid_permute!(p, getcolptr(C), q, workcolptr)
    unchecked_aliasing_permute!(A, p, q, C, workcolptr)
end
"""
    permute(A::AbstractSparseMatrixCSC{Tv,Ti}, p::AbstractVector{<:Integer},
            q::AbstractVector{<:Integer}) where {Tv,Ti}

Bilaterally permute `A`, returning `PAQ` (`A[p,q]`). Column-permutation `q`'s length must
match `A`'s column count (`length(q) == size(A, 2)`). Row-permutation `p`'s length must match `A`'s
row count (`length(p) == size(A, 1)`).

For expert drivers and additional information, see [`permute!`](@ref).

# Examples
```jldoctest
julia> A = spdiagm(0 => [1, 2, 3, 4], 1 => [5, 6, 7])
4×4 SparseMatrixCSC{Int64, Int64} with 7 stored entries:
 1  5  ⋅  ⋅
 ⋅  2  6  ⋅
 ⋅  ⋅  3  7
 ⋅  ⋅  ⋅  4

julia> permute(A, [4, 3, 2, 1], [1, 2, 3, 4])
4×4 SparseMatrixCSC{Int64, Int64} with 7 stored entries:
 ⋅  ⋅  ⋅  4
 ⋅  ⋅  3  7
 ⋅  2  6  ⋅
 1  5  ⋅  ⋅

julia> permute(A, [1, 2, 3, 4], [4, 3, 2, 1])
4×4 SparseMatrixCSC{Int64, Int64} with 7 stored entries:
 ⋅  ⋅  5  1
 ⋅  6  2  ⋅
 7  3  ⋅  ⋅
 4  ⋅  ⋅  ⋅
```
"""
function permute(A::AbstractSparseMatrixCSC{Tv,Ti}, p::AbstractVector{<:Integer},
        q::AbstractVector{<:Integer}) where {Tv,Ti}
    _checkargs_sourcecompatperms_permute!(A, p, q)
    # bypass strict buffer checking
    X = spzeros(Tv, Ti, size(A,1), size(A,2))
    resize!(getrowval(X), nnz(A))
    resize!(getnzval(X), nnz(A))
    # bypass strict buffer checking
    C = spzeros(Tv, Ti, size(A,2), size(A,1))
    resize!(getrowval(C), nnz(A))
    resize!(getnzval(C), nnz(A))
    _checkargs_permutationsvalid_permute!(p, getcolptr(C), q, getcolptr(X))
    unchecked_noalias_permute!(X, A, p, q, C)
end

## fkeep! and children tril!, triu!, droptol!, dropzeros[!]

function _fkeep!(f::F, A::AbstractSparseMatrixCSC) where F<:Function
    An = size(A, 2)
    Acolptr = getcolptr(A)
    Arowval = rowvals(A)
    Anzval = nonzeros(A)

    # Sweep through columns, rewriting kept elements in their new positions
    # and updating the column pointers accordingly as we go.
    Awritepos = 1
    oldAcolptrAj = 1
    @inbounds for Aj in 1:An
        for Ak in oldAcolptrAj:(Acolptr[Aj+1]-1)
            Ai = Arowval[Ak]
            Ax = Anzval[Ak]
            # If this element should be kept, rewrite in new position
            if f(Ai, Aj, Ax)
                if Awritepos != Ak
                    Arowval[Awritepos] = Ai
                    Anzval[Awritepos] = Ax
                end
                Awritepos += 1
            end
        end
        oldAcolptrAj = Acolptr[Aj+1]
        Acolptr[Aj+1] = Awritepos
    end

    # Trim A's storage if necessary
    Annz = Acolptr[end] - 1
    resize!(Arowval, Annz)
    resize!(Anzval, Annz)

    return A
end

function _fkeep!_fixed(f::F, A::AbstractSparseMatrixCSC) where F<:Function
    @inbounds for j in axes(A,2)
        for k in getcolptr(A)[j]:getcolptr(A)[j+1]-1
            # If this element should be kept, rewrite in new position
            if !f(rowvals(A)[k], j, nonzeros(A)[k])
                nonzeros(A)[k] = zero(eltype(A))
            end
        end
    end
    return A
end

"""
    fkeep!(f, A::AbstractSparseArray)

Keep elements of `A` for which test `f` returns `true`. `f`'s signature should be

    f(i::Integer, [j::Integer,] x) -> Bool

where `i` and `j` are an element's row and column indices and `x` is the element's
value. This method makes a single sweep
through `A`, requiring `O(size(A, 2), nnz(A))`-time for matrices and `O(nnz(A))`-time for vectors
and no space beyond that passed in.

# Examples
```jldoctest
julia> A = sparse(Diagonal([1, 2, 3, 4]))
4×4 SparseMatrixCSC{Int64, Int64} with 4 stored entries:
 1  ⋅  ⋅  ⋅
 ⋅  2  ⋅  ⋅
 ⋅  ⋅  3  ⋅
 ⋅  ⋅  ⋅  4

julia> SparseArrays.fkeep!((i, j, v) -> isodd(v), A)
4×4 SparseMatrixCSC{Int64, Int64} with 2 stored entries:
 1  ⋅  ⋅  ⋅
 ⋅  ⋅  ⋅  ⋅
 ⋅  ⋅  3  ⋅
 ⋅  ⋅  ⋅  ⋅
```
"""
fkeep!(f::F, A::AbstractSparseMatrixCSC) where F<:Function = _is_fixed(A) ? _fkeep!_fixed(f, A) : _fkeep!(f, A)

# deprecated syntax
function fkeep!(x::Union{AbstractSparseMatrixCSC,AbstractCompressedVector},f::F) where F<:Function
    Base.depwarn("`fkeep!(x, f::Function)` is deprecated, use `fkeep!(f::Function, x)` instead.", :fkeep!)
    return fkeep!(f, x)
end


tril!(A::AbstractSparseMatrixCSC, k::Integer = 0) =
    fkeep!((i, j, x) -> i + k >= j, A)
triu!(A::AbstractSparseMatrixCSC, k::Integer = 0) =
    fkeep!((i, j, x) -> j >= i + k, A)

"""
    droptol!(A::AbstractSparseMatrixCSC, tol)

Removes stored values from `A` whose absolute value is less than or equal to `tol`.
"""
droptol!(A::AbstractSparseMatrixCSC, tol) =
    fkeep!((i, j, x) -> abs(x) > tol, A)

"""
    dropzeros!(A::AbstractSparseMatrixCSC;)

Removes stored numerical zeros from `A`.

For an out-of-place version, see [`dropzeros`](@ref). For
algorithmic information, see `fkeep!`.
"""

dropzeros!(A::AbstractSparseMatrixCSC) = _is_fixed(A) ? A : fkeep!((i, j, x) -> _isnotzero(x), A)

"""
    dropzeros(A::AbstractSparseMatrixCSC;)

Generates a copy of `A` and removes stored numerical zeros from that copy.

For an in-place version and algorithmic information, see [`dropzeros!`](@ref).

# Examples
```jldoctest
julia> A = sparse([1, 2, 3], [1, 2, 3], [1.0, 0.0, 1.0])
3×3 SparseMatrixCSC{Float64, Int64} with 3 stored entries:
 1.0   ⋅    ⋅
  ⋅   0.0   ⋅
  ⋅    ⋅   1.0

julia> dropzeros(A)
3×3 SparseMatrixCSC{Float64, Int64} with 2 stored entries:
 1.0   ⋅    ⋅
  ⋅    ⋅    ⋅
  ⋅    ⋅   1.0
```
"""
dropzeros(A::AbstractSparseMatrixCSC) = dropzeros!(copy(A))

## Find methods

function findall(S::AbstractSparseMatrixCSC)
    return findall(identity, S)
end

function findall(p::Function, S::AbstractSparseMatrixCSC)
    if p(zero(eltype(S)))
        return invoke(findall, Tuple{Function, Any}, p, S)
    end

    numnz = nnz(S)
    inds = Vector{CartesianIndex{2}}(undef, numnz)

    count = 0
    @inbounds for col = 1 : size(S, 2), k = getcolptr(S)[col] : (getcolptr(S)[col+1]-1)
        if p(nonzeros(S)[k])
            count += 1
            inds[count] = CartesianIndex(rowvals(S)[k], col)
        end
    end

    resize!(inds, count)

    return inds
end
findall(p::Base.Fix2{typeof(in)}, x::AbstractSparseMatrixCSC) =
    invoke(findall, Tuple{Base.Fix2{typeof(in)}, AbstractArray}, p, x)

function findnz(S::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}
    numnz = nnz(S)
    I = Vector{Ti}(undef, numnz)
    J = Vector{Ti}(undef, numnz)
    V = Vector{Tv}(undef, numnz)

    count = 1
    @inbounds for col = 1 : size(S, 2), k = getcolptr(S)[col] : (getcolptr(S)[col+1]-1)
        I[count] = rowvals(S)[k]
        J[count] = col
        V[count] = nonzeros(S)[k]
        count += 1
    end

    return (I, J, V)
end

function _sparse_findnextnz(m::AbstractSparseMatrixCSC, ij::CartesianIndex{2})
    row, col = Tuple(ij)
    col > size(m, 2) && return nothing

    lo, hi = getcolptr(m)[col], getcolptr(m)[col+1]
    n = searchsortedfirst(view(rowvals(m), lo:hi-1), row) + lo - 1
    if lo <= n <= hi-1
        return CartesianIndex(rowvals(m)[n], col)
    end
    nextcol = searchsortedfirst(view(getcolptr(m), col+1:length(getcolptr(m))), hi + 1) + col
    nextcol > length(getcolptr(m)) && return nothing
    nextlo = getcolptr(m)[nextcol-1]
    return CartesianIndex(rowvals(m)[nextlo], nextcol - 1)
end

function _sparse_findprevnz(m::AbstractSparseMatrixCSC, ij::CartesianIndex{2})
    row, col = Tuple(ij)
    iszero(col) && return nothing

    lo, hi = getcolptr(m)[col], getcolptr(m)[col+1]
    n = searchsortedlast(view(rowvals(m), lo:hi-1), row) + lo - 1
    if lo <= n <= hi-1
        return CartesianIndex(rowvals(m)[n], col)
    end
    prevcol = searchsortedlast(view(getcolptr(m), 1:col-1), lo - 1)
    prevcol < 1 && return nothing
    prevhi = getcolptr(m)[prevcol+1]
    return CartesianIndex(rowvals(m)[prevhi-1], prevcol)
end


function sparse_sortedlinearindices!(I::Vector{Ti}, V::Vector, m::Int, n::Int) where Ti
    length(I) == length(V) || throw(ArgumentError("I and V should have the same length"))
    nnz = length(V)
    colptr = Vector{Ti}(undef, n + 1)
    j, colm = 1, 0
    @inbounds for col = 1:n+1
        colptr[col] = j
        while j <= nnz && (I[j] -= colm) <= m
            j += 1
        end
        j <= nnz && (I[j] += colm)
        colm += m
    end
    return SparseMatrixCSC(m, n, colptr, I, V)
end

"""
    sprand([rng],[T::Type],m,[n],p::AbstractFloat)
    sprand([rng],m,[n],p::AbstractFloat,[rfn=rand])

Create a random length `m` sparse vector or `m` by `n` sparse matrix, in
which the probability of any element being nonzero is independently given by
`p` (and hence the mean density of nonzeros is also exactly `p`).
The optional `rng` argument specifies a random number generator, see [Random Numbers](@ref).
The optional `T` argument specifies the element type, which defaults to `Float64`.

By default, nonzero values are sampled from a uniform distribution using
the [`rand`](@ref) function, i.e. by `rand(T)`, or `rand(rng, T)` if `rng`
is supplied; for the default `T=Float64`, this corresponds to nonzero values
sampled uniformly in `[0,1)`.

You can sample nonzero values from a different distribution by passing a
custom `rfn` function instead of `rand`.   This should be a function `rfn(k)`
that returns an array of `k` random numbers sampled from the desired distribution;
alternatively, if `rng` is supplied, it should instead be a function `rfn(rng, k)`.

# Examples
```jldoctest; setup = :(using Random; Random.seed!(1234))
julia> sprand(Bool, 2, 2, 0.5)
2×2 SparseMatrixCSC{Bool, Int64} with 2 stored entries:
 1  1
 ⋅  ⋅

julia> sprand(Float64, 3, 0.75)
3-element SparseVector{Float64, Int64} with 2 stored entries:
  [1]  =  0.795547
  [2]  =  0.49425
```
"""
function sprand(r::AbstractRNG, m::Integer, n::Integer, density::AbstractFloat, rfn::Function, ::Type{T}=eltype(rfn(r, 1))) where T
    m, n = Int(m), Int(n)
    (m < 0 || n < 0) && throw(ArgumentError("invalid Array dimensions"))
    0 <= density <= 1 || throw(ArgumentError("$density not in [0,1]"))
    I = randsubseq(r, 1:(m*n), density)
    return sparse_sortedlinearindices!(I, convert(Vector{T}, rfn(r,length(I))), m, n)
end

sprand(m::Integer, n::Integer, density::AbstractFloat, rfn::Function, ::Type{T} = eltype(rfn(1))) where {T} =
    sprand(default_rng(), m, n, density, (r, i) -> rfn(i))

truebools(r::AbstractRNG, n::Integer) = fill(true, n)

sprand(m::Integer, n::Integer, density::AbstractFloat) = sprand(default_rng(), m, n, density)

sprand(r::AbstractRNG, m::Integer, n::Integer, density::AbstractFloat) =
    sprand(r, m, n, density, rand, Float64)
sprand(r::AbstractRNG, ::Type{T}, m::Integer, n::Integer, density::AbstractFloat) where {T} =
    sprand(r, m, n, density, (r, i) -> rand(r, T, i), T)
sprand(r::AbstractRNG, ::Type{Bool}, m::Integer, n::Integer, density::AbstractFloat) =
    sprand(r, m, n, density, truebools, Bool)
sprand(::Type{T}, m::Integer, n::Integer, density::AbstractFloat) where {T} =
    sprand(default_rng(), T, m, n, density)

"""
    sprandn([rng][,Type],m[,n],p::AbstractFloat)

Create a random sparse vector of length `m` or sparse matrix of size `m` by `n`
with the specified (independent) probability `p` of any entry being nonzero,
where nonzero values are sampled from the normal distribution. The optional `rng`
argument specifies a random number generator, see [Random Numbers](@ref).

!!! compat "Julia 1.1"
    Specifying the output element type `Type` requires at least Julia 1.1.

# Examples
```jldoctest; setup = :(using Random; Random.seed!(0))
julia> sprandn(2, 2, 0.75)
2×2 SparseMatrixCSC{Float64, Int64} with 3 stored entries:
 -1.20577     ⋅
  0.311817  -0.234641
```
"""
sprandn(r::AbstractRNG, m::Integer, n::Integer, density::AbstractFloat) =
    sprand(r, m, n, density, randn, Float64)
sprandn(m::Integer, n::Integer, density::AbstractFloat) =
    sprandn(default_rng(), m, n, density)
sprandn(r::AbstractRNG, ::Type{T}, m::Integer, n::Integer, density::AbstractFloat) where {T} =
    sprand(r, m, n, density, (r, i) -> randn(r, T, i), T)
sprandn(::Type{T}, m::Integer, n::Integer, density::AbstractFloat) where {T} =
    sprandn(default_rng(), T, m, n, density)

LinearAlgebra.fillstored!(S::AbstractSparseMatrixCSC, x) = (fill!(nzvalview(S), x); S)

"""
    spzeros([type,]m[,n])

Create a sparse vector of length `m` or sparse matrix of size `m x n`. This
sparse array will not contain any nonzero values. No storage will be allocated
for nonzero values during construction. The type defaults to [`Float64`](@ref) if not
specified.

# Examples
```jldoctest
julia> spzeros(3, 3)
3×3 SparseMatrixCSC{Float64, Int64} with 0 stored entries:
  ⋅    ⋅    ⋅
  ⋅    ⋅    ⋅
  ⋅    ⋅    ⋅

julia> spzeros(Float32, 4)
4-element SparseVector{Float32, Int64} with 0 stored entries
```
"""
spzeros(m::Integer, n::Integer) = spzeros(Float64, m, n)
spzeros(::Type{Tv}, m::Integer, n::Integer) where {Tv} = spzeros(Tv, Int, m, n)
function spzeros(::Type{Tv}, ::Type{Ti}, m::Integer, n::Integer) where {Tv, Ti}
    ((m < 0) || (n < 0)) && throw(ArgumentError("invalid Array dimensions"))
    SparseMatrixCSC(m, n, fill(one(Ti), n+1), Vector{Ti}(), Vector{Tv}())
end
# de-splatting variants
function spzeros(::Type{Tv}, ::Type{Ti}, sz::Tuple{Integer,Integer}) where {Tv, Ti}
    spzeros(Tv, Ti, sz[1], sz[2])
end
spzeros(::Type{Tv}, sz::Tuple{Integer,Integer}) where {Tv} = spzeros(Tv, Int, sz[1], sz[2])
spzeros(sz::Tuple{Integer,Integer}) = spzeros(Float64, Int, sz[1], sz[2])

"""
    spzeros([type], I::AbstractVector, J::AbstractVector, [m, n])

Create a sparse matrix `S` of dimensions `m x n` with structural zeros at `S[I[k], J[k]]`.

This method can be used to construct the sparsity pattern of the matrix, and is more
efficient than using e.g. `sparse(I, J, zeros(length(I)))`.

For additional documentation and an expert driver, see `SparseArrays.spzeros!`.

!!! compat "Julia 1.10"
    This methods requires Julia version 1.10 or later.
"""
spzeros(I::AbstractVector, J::AbstractVector) = spzeros(Float64, I, J)
spzeros(I::AbstractVector, J::AbstractVector, m::Integer, n::Integer) = spzeros(Float64, I, J, m, n)
spzeros(::Type{Tv}, I::AbstractVector, J::AbstractVector) where {Tv} = spzeros(Tv, I, J, dimlub(I), dimlub(J))
function spzeros(::Type{Tv}, I::AbstractVector, J::AbstractVector, m::Integer, n::Integer) where {Tv}
    return spzeros(Tv, AbstractVector{Int}(I), AbstractVector{Int}(J), m, n)
end
function spzeros(::Type{Tv}, I::AbstractVector{Ti}, J::AbstractVector{Ti}, m::Integer, n::Integer) where {Tv, Ti<:Integer}
    if length(I) != length(J)
        throw(ArgumentError("length(I) = $(length(I)) does not match length(J) = $(length(J))"))
    end
    klasttouch = Vector{Ti}(undef, n)
    csrrowptr = Vector{Ti}(undef, m+1)
    csrcolval = Vector{Ti}(undef, length(I))
    return spzeros!(Tv, I, J, m, n, klasttouch, csrrowptr, csrcolval)
end

"""
    spzeros!(::Type{Tv}, I::AbstractVector{Ti}, J::AbstractVector{Ti}, m::Integer, n::Integer,
             klasttouch::Vector{Ti}, csrrowptr::Vector{Ti}, csrcolval::Vector{Ti},
             [csccolptr::Vector{Ti}], [cscrowval::Vector{Ti}, cscnzval::Vector{Tv}]) where {Tv,Ti<:Integer}

Parent of and expert driver for `spzeros(I, J)` allowing user to provide preallocated
storage for intermediate objects. This method is to `spzeros` what `SparseArrays.sparse!` is
to `sparse`. See documentation for `SparseArrays.sparse!` for details and required buffer
lengths.

!!! compat "Julia 1.10"
    This methods requires Julia version 1.10 or later.
"""
function spzeros!(::Type{Tv}, I::AbstractVector{Ti}, J::AbstractVector{Ti}, m::Integer, n::Integer,
        klasttouch::Vector{Ti}, csrrowptr::Vector{Ti}, csrcolval::Vector{Ti},
        csccolptr::Vector{Ti}=Ti[], cscrowval::Vector{Ti}=Ti[], cscnzval::Vector{Tv}=Tv[]
    ) where {Tv, Ti<:Integer}
    # We can pass V = csrnzval = cscnzval since V and csrnzval are unused in sparse! if used
    # to only build the sparsity pattern (which is indicated by passing combine=nothing).
    return sparse!(I, J, cscnzval, m, n, nothing, klasttouch,
                   csrrowptr, csrcolval, cscnzval, csccolptr, cscrowval, cscnzval)
end

"""
    SparseArrays.spzeros!(::Type{Tv}, I, J, [m, n]) -> SparseMatrixCSC{Tv}

Variant of `spzeros!` that re-uses the input vectors `I` and `J` for the final matrix
storage. After construction the input vectors will alias the matrix buffers; `S.colptr ===
I` and `S.rowval === J` holds, and they will be `resize!`d as necessary.

Note that some work buffers will still be allocated. Specifically, this method is a
convenience wrapper around `spzeros!(Tv, I, J, m, n, klasttouch, csrrowptr, csrcolval,
csccolptr, cscrowval)` where this method allocates `klasttouch`, `csrrowptr`, and
`csrcolval` of appropriate size, but reuses `I` and `J` for `csccolptr` and `cscrowval`.

Arguments `m` and `n` defaults to `maximum(I)` and `maximum(J)`.

!!! compat "Julia 1.10"
    This method requires Julia version 1.10 or later.
"""
function spzeros!(::Type{Tv}, I::AbstractVector{Ti}, J::AbstractVector{Ti},
                  m::Integer=dimlub(I), n::Integer=dimlub(J)) where {Tv, Ti <: Integer}
    klasttouch = Vector{Ti}(undef, n)
    csrrowptr  = Vector{Ti}(undef, m + 1)
    csrcolval  = Vector{Ti}(undef, length(I))
    return spzeros!(Tv, I, J, Int(m), Int(n), klasttouch, csrrowptr, csrcolval, I, J)
end

import Base._one
function Base._one(unit::T, S::AbstractSparseMatrixCSC) where T
    size(S, 1) == size(S, 2) || throw(DimensionMismatch("multiplicative identity only defined for square matrices"))
    return SparseMatrixCSC{T}(I, size(S, 1), size(S, 2))
end

## SparseMatrixCSC construction from UniformScaling
SparseMatrixCSC{Tv,Ti}(s::UniformScaling, m::Integer, n::Integer) where {Tv,Ti} = SparseMatrixCSC{Tv,Ti}(s, Dims((m, n)))
SparseMatrixCSC{Tv}(s::UniformScaling, m::Integer, n::Integer) where {Tv} = SparseMatrixCSC{Tv}(s, Dims((m, n)))
SparseMatrixCSC(s::UniformScaling, m::Integer, n::Integer) = SparseMatrixCSC(s, Dims((m, n)))
SparseMatrixCSC{Tv}(s::UniformScaling, dims::Dims{2}) where {Tv} = SparseMatrixCSC{Tv,Int}(s, dims)
SparseMatrixCSC(s::UniformScaling, dims::Dims{2}) = SparseMatrixCSC{eltype(s)}(s, dims)
function SparseMatrixCSC{Tv,Ti}(s::UniformScaling, dims::Dims{2}) where {Tv,Ti}
    @boundscheck first(dims) < 0 && throw(ArgumentError("first dimension invalid ($(first(dims)) < 0)"))
    @boundscheck last(dims) < 0 && throw(ArgumentError("second dimension invalid ($(last(dims)) < 0)"))
    iszero(s.λ) && return spzeros(Tv, Ti, dims...)
    m, n, k = dims..., min(dims...)
    nzval = fill!(Vector{Tv}(undef, k), Tv(s.λ))
    rowval = copyto!(Vector{Ti}(undef, k), 1:k)
    colptr = copyto!(Vector{Ti}(undef, n + 1), 1:(k + 1))
    for i in (k + 2):(n + 1) colptr[i] = (k + 1) end
    SparseMatrixCSC{Tv,Ti}(dims..., colptr, rowval, nzval)
end

Base.iszero(A::AbstractSparseMatrixCSC) = iszero(nzvalview(A))

function Base.isone(A::AbstractSparseMatrixCSC)
    m, n = size(A)
    m == n && getcolptr(A)[n+1] >= n+1 || return false
    for j in axes(A,2), k in getcolptr(A)[j]:(getcolptr(A)[j+1] - 1)
        i, x = rowvals(A)[k], nonzeros(A)[k]
        ifelse(i == j, isone(x), iszero(x)) || return false
    end
    return true
end

sparse(s::UniformScaling, dims::Dims{2}) = SparseMatrixCSC(s, dims)
sparse(s::UniformScaling, m::Integer, n::Integer) = sparse(s, Dims((m, n)))
sparse(::Type{Tv}, s::UniformScaling, m::Integer, n::Integer) where {Tv} = SparseMatrixCSC{Tv}(s, Dims((m, n)))
sparse(::Type{Tv}, ::Type{Ti}, s::UniformScaling, m::Integer, n::Integer) where {Tv, Ti} = SparseMatrixCSC{Tv, Ti}(s, Dims((m, n)))

# TODO: More appropriate location?
function conj!(A::AbstractSparseMatrixCSC)
    map!(conj, nzvalview(A), nzvalview(A))
    return A
end
function (-)(A::AbstractSparseMatrixCSC)
    nzval = similar(nonzeros(A), typeof(-zero(eltype(A))))
    map!(-, view(nzval, 1:nnz(A)), nzvalview(A))
    return SparseMatrixCSC(size(A, 1), size(A, 2), copy(getcolptr(A)), copy(rowvals(A)), nzval)
end

# the rest of real, conj, imag are handled correctly via AbstractArray methods
function conj(A::AbstractSparseMatrixCSC{<:Complex})
    nzval = similar(nonzeros(A))
    map!(conj, view(nzval, 1:nnz(A)), nzvalview(A))
    return SparseMatrixCSC(size(A, 1), size(A, 2), copy(getcolptr(A)), copy(rowvals(A)), nzval)
end
imag(A::SparseMatrixCSCUnion{Tv,Ti}) where {Tv<:Real,Ti} = spzeros(Tv, Ti, size(A, 1), size(A, 2))

## Binary arithmetic and boolean operators
(+)(A::SparseMatrixCSCUnion, B::SparseMatrixCSCUnion) = map(+, A, B)
(-)(A::SparseMatrixCSCUnion, B::SparseMatrixCSCUnion) = map(-, A, B)

function (+)(A::SparseMatrixCSCUnion, B::Array)
    Base.promote_shape(axes(A), axes(B))
    C = Ref(zero(eltype(A))) .+ B
    rowinds, nzvals = rowvals(A), nonzeros(A)
    for j in axes(A,2)
        for i in nzrange(A, j)
            rowidx = rowinds[i]
            C[rowidx,j] = nzvals[i] + B[rowidx,j]
        end
    end
    return C
end
function (+)(A::Array, B::SparseMatrixCSCUnion)
    Base.promote_shape(axes(A), axes(B))
    C = A .+ Ref(zero(eltype(B)))
    rowinds, nzvals = rowvals(B), nonzeros(B)
    for j in axes(B,2)
        for i in nzrange(B, j)
            rowidx = rowinds[i]
            C[rowidx,j] = A[rowidx,j] + nzvals[i]
        end
    end
    return C
end
function (-)(A::SparseMatrixCSCUnion, B::Array)
    Base.promote_shape(axes(A), axes(B))
    C = Ref(zero(eltype(A))) .- B
    rowinds, nzvals = rowvals(A), nonzeros(A)
    for j in axes(A,2)
        for i in nzrange(A, j)
            rowidx = rowinds[i]
            C[rowidx,j] = nzvals[i] - B[rowidx,j]
        end
    end
    return C
end
function (-)(A::Array, B::SparseMatrixCSCUnion)
    Base.promote_shape(axes(A), axes(B))
    C = A .- Ref(zero(eltype(B)))
    rowinds, nzvals = rowvals(B), nonzeros(B)
    for j in axes(B,2)
        for i in nzrange(B, j)
            rowidx = rowinds[i]
            C[rowidx,j] = A[rowidx,j] - nzvals[i]
        end
    end
    return C
end

## full equality
function ==(A1::AbstractSparseMatrixCSC, A2::AbstractSparseMatrixCSC)
    size(A1) != size(A2) && return false
    @inbounds for i in axes(A1, 2)
        nz1, nz2 = nzrange(A1,i), nzrange(A2,i)
        j1, j2 = first(nz1), first(nz2)
        # step through the rows of both matrices at once:
        while j1 <= last(nz1) && j2 <= last(nz2)
            r1, r2 = rowvals(A1)[j1], rowvals(A2)[j2]
            if r1 == r2
                nonzeros(A1)[j1] != nonzeros(A2)[j2] && return false
                j1 += 1
                j2 += 1
            elseif r1 < r2
                !iszero(nonzeros(A1)[j1]) && return false
                j1 += 1
            else # r1 > r2
                !iszero(nonzeros(A2)[j2]) && return false
                j2 += 1
            end
        end
        # finish off any left-overs:
        for j = j1:last(nz1)
            !iszero(nonzeros(A1)[j]) && return false
        end
        for j = j2:last(nz2)
            !iszero(nonzeros(A2)[j]) && return false
        end
    end
    return true
end

## Explicit efficient comparisons with transposed arrays

# Check whether all nonzero elements of A are equal to the respective elements in B
function nzeq(A::AbstractSparseMatrixCSC, B::AbstractSparseMatrixCSCInclAdjointAndTranspose)
    @inbounds for j in axes(A,2)
        for k in nzrange(A, j)
            i = rowvals(A)[k]
            val = nonzeros(A)[k]
            val ≠ B[i,j] && return false
        end
    end
    return true
end
# Peel off `Adjoint` and `Transpose` from first argument
nzeq(A::Adjoint{<:Any,<:AbstractSparseMatrixCSCInclAdjointAndTranspose},
     B::AbstractSparseMatrixCSCInclAdjointAndTranspose) =
    nzeq(A', B')
nzeq(A::Transpose{<:Any,<:AbstractSparseMatrixCSCInclAdjointAndTranspose},
     B::AbstractSparseMatrixCSCInclAdjointAndTranspose) =
    nzeq(transpose(A), transpose(B))

# Compare by walking both matrices
# (We could further optimize the case `AbstractSparseMatrixCSC ==
# Adjoint(Transpose(AbstractSparseMatrixCSC))` more efficiently, i.e.
# the case where the RHS is both adjoint and transposed, i.e. where it
# is in CSC format again.)
function ==(A::AbstractSparseMatrixCSC,
            B::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSCInclAdjointAndTranspose})
    # Different sizes are always different
    size(A) ≠ size(B) && return false
    # Compare nonzero elements
    return nzeq(A, B) && nzeq(B, A)
end
# Peel off `Adjoint` and `Transpose` from first argument
==(A::Adjoint{<:Any,<:AbstractSparseMatrixCSCInclAdjointAndTranspose}, B::AbstractSparseMatrixCSCInclAdjointAndTranspose) =
    A' == B'
==(A::Transpose{<:Any,<:AbstractSparseMatrixCSCInclAdjointAndTranspose}, B::AbstractSparseMatrixCSCInclAdjointAndTranspose) =
    transpose(A) == transpose(B)

## Reductions

# In general, output of sparse matrix reductions will not be sparse,
# and computing reductions along columns into SparseMatrixCSC is
# non-trivial, so use Arrays for output. Array element type is given by `R`.
function Base.reducedim_initarray(A::AbstractSparseMatrixCSC, region, v0, ::Type{R}) where {R}
    fill!(Array{R}(undef, Base.to_shape(Base.reduced_indices(A, region))), v0)
end

# General mapreduce
function _mapreducezeros(f, op, ::Type{T}, nzeros::Integer, v0) where T
    nzeros == 0 && return v0

    # Reduce over first zero
    zeroval = f(zero(T))
    v = op(v0, zeroval)
    isequal(v, v0) && return v

    # Reduce over remaining zeros
    for i = 2:nzeros
        lastv = v
        v = op(v, zeroval)
        # Bail out early if we reach a fixed point
        isequal(v, lastv) && break
    end

    v
end

function Base._mapreduce(f, op, ::Base.IndexCartesian, A::AbstractSparseMatrixCSC{T}) where T
    z = nnz(A)
    n = widelength(A)
    if z == 0
        if n == 0
            Base.mapreduce_empty(f, op, T)
        else
            _mapreducezeros(f, op, T, n-z-1, f(zero(T)))
        end
    else
        _mapreducezeros(f, op, T, n-z, Base._mapreduce(f, op, nzvalview(A)))
    end
end

# Specialized mapreduce for +/*/min/max/_extrema_rf
_mapreducezeros(f, op::Union{typeof(Base.add_sum),typeof(+)}, ::Type{T}, nzeros::Integer, v0) where {T} =
    nzeros == 0 ? op(zero(v0), v0) : op(f(zero(T))*nzeros, v0)
_mapreducezeros(f, op::Union{typeof(Base.mul_prod),typeof(*)},::Type{T}, nzeros::Integer, v0) where {T} =
    nzeros == 0 ? op(one(v0), v0) : op(f(zero(T))^nzeros, v0)
_mapreducezeros(f, op::Union{typeof(min),typeof(max)}, ::Type{T}, nzeros::Integer, v0) where {T} =
    nzeros == 0 ? v0 : op(v0, f(zero(T)))
_mapreducezeros(f::Base.ExtremaMap, op::typeof(Base._extrema_rf), ::Type{T}, nzeros::Integer, v0) where {T} =
    nzeros == 0 ? v0 : op(v0, f(zero(T)))

# Specialized mapreduce for any and all
Base._any(f, A::AbstractSparseMatrixCSC, ::Colon) =
    iszero(widelength(A)) ? false : Base._mapreduce(f, |, IndexCartesian(), A)
Base._all(f, A::AbstractSparseMatrixCSC, ::Colon) =
    iszero(widelength(A)) ? true  : Base._mapreduce(f, &, IndexCartesian(), A)

function Base._mapreduce(f, op::Union{typeof(Base.mul_prod),typeof(*)}, ::Base.IndexCartesian, A::AbstractSparseMatrixCSC{T}) where T
    nnzA = nnz(A)
    nzeros = widelength(A) - nnzA
    if nzeros == 0
        # No zeros, so don't compute f(0) since it might throw
        Base._mapreduce(f, op, nzvalview(A))
    else
        v = f(zero(T))^(nzeros)
        # Bail out early if initial reduction value is zero or if there are no stored elements
        (_iszero(v) || nnzA == 0) ? v : v*Base._mapreduce(f, op, nzvalview(A))
    end
end

# General mapreducedim
function _mapreducerows!(f, op, R::AbstractArray, A::AbstractSparseMatrixCSC{T}) where T
    require_one_based_indexing(A, R)
    colptr = getcolptr(A)
    rowval = rowvals(A)
    nzval = nonzeros(A)
    m, n = size(A)
    @inbounds for col in axes(A,2)
        r = R[1, col]
        @simd for j = colptr[col]:colptr[col+1]-1
            r = op(r, f(nzval[j]))
        end
        R[1, col] = _mapreducezeros(f, op, T, m-(colptr[col+1]-colptr[col]), r)
    end
    R
end

function _mapreducecols!(f, op, R::AbstractArray, A::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}
    require_one_based_indexing(A, R)
    colptr = getcolptr(A)
    rowval = rowvals(A)
    nzval = nonzeros(A)
    m, n = size(A)
    rownz = fill(convert(Ti, n), m)
    @inbounds for col in axes(A,2)
        @simd for j = colptr[col]:colptr[col+1]-1
            row = rowval[j]
            R[row, 1] = op(R[row, 1], f(nzval[j]))
            rownz[row] -= 1
        end
    end
    @inbounds for i = 1:m
        R[i, 1] = _mapreducezeros(f, op, Tv, Int(rownz[i]), R[i, 1])
    end
    R
end

function Base._mapreducedim!(f, op, R::AbstractArray, A::AbstractSparseMatrixCSC{T}) where T
    require_one_based_indexing(A, R)
    lsiz = Base.check_reducedims(R,A)
    isempty(A) && return R

    if size(R, 1) == size(R, 2) == 1
        # Reduction along both columns and rows
        R[1, 1] = op(R[1, 1], mapreduce(f, op, A))
    elseif size(R, 1) == 1
        # Reduction along rows
        _mapreducerows!(f, op, R, A)
    elseif size(R, 2) == 1
        # Reduction along columns
        _mapreducecols!(f, op, R, A)
    else
        # Reduction along a dimension > 2
        # Compute op(R, f(A))
        m, n = size(A)
        nzval = nonzeros(A)
        if length(nzval) == m*n
            # No zeros, so don't compute f(0) since it might throw
            for col in axes(A,2)
                @simd for row in axes(A,1)
                    @inbounds R[row, col] = op(R[row, col], f(nzval[(col-1)*m+row]))
                end
            end
        else
            colptr = getcolptr(A)
            rowval = rowvals(A)
            zeroval = f(zero(T))
            @inbounds for col in axes(A,2)
                lastrow = 0
                for j = colptr[col]:colptr[col+1]-1
                    row = rowval[j]
                    @simd for i = lastrow+1:row-1 # Zeros before this nonzero
                        R[i, col] = op(R[i, col], zeroval)
                    end
                    R[row, col] = op(R[row, col], f(nzval[j]))
                    lastrow = row
                end
                @simd for i = lastrow+1:m         # Zeros at end
                    R[i, col] = op(R[i, col], zeroval)
                end
            end
        end
    end
    R
end

# Specialized mapreducedim for + cols to avoid allocating a
# temporary array when f(0) == 0
function _mapreducecols!(f, op::typeof(+), R::AbstractArray, A::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}
    require_one_based_indexing(A, R)
    nzval = nonzeros(A)
    m, n = size(A)
    if length(nzval) == m*n
        # No zeros, so don't compute f(0) since it might throw
        for col in axes(A,2)
            @simd for row in axes(A,1)
                @inbounds R[row, 1] = op(R[row, 1], f(nzval[(col-1)*m+row]))
            end
        end
    else
        colptr = getcolptr(A)
        rowval = rowvals(A)
        zeroval = f(zero(Tv))
        if isequal(zeroval, zero(Tv))
            # Case where f(0) == 0
            @inbounds for col in axes(A,2)
                @simd for j = colptr[col]:colptr[col+1]-1
                    R[rowval[j], 1] += f(nzval[j])
                end
            end
        else
            # Case where f(0) != 0
            rownz = fill(convert(Ti, n), m)
            @inbounds for col in axes(A,2)
                @simd for j = colptr[col]:colptr[col+1]-1
                    row = rowval[j]
                    R[row, 1] += f(nzval[j])
                    rownz[row] -= 1
                end
            end
            for i = 1:m
                R[i, 1] += rownz[i]*zeroval
            end
        end
    end
    R
end

# any(pred, A, dims = 1) => mapreduce(pred, |, A, dims = 1)
# final argument `post` is to allow post-mapping each columnar mapreduce
function _mapreducerows!(pred::P, ::typeof(|), R::AbstractMatrix{Bool}, A::AbstractSparseMatrixCSC{Tv},
                         post::F = identity) where {P, F, Tv}
    nzval = nonzeros(A)
    colptr = getcolptr(A)
    m, n = size(A)
    @inbounds for ii in axes(A,2)
        bi, ei = colptr[ii], colptr[ii+1]
        len = ei - bi
        # An empty column is trivial
        if len == 0
            R[1, ii] = post(pred(zero(Tv)))
            continue
        end
        # If predicate on zero is true, then sparse column can be short-circuited
        if pred(zero(Tv)) && len < m
            R[1, ii] = post(true)
            continue
        end
        # Otherwise reduce over the stored values
        r = false
        for jj in bi:(ei - 1)
            r = pred(nzval[jj])
            r && break
        end
        R[1, ii] = post(r)
    end
    return R
end
# all(pred, A, dims = 1) => mapreduce(pred, &, A, dims = 1) == .!mapreduce(!pred, |, A, dims = 1)
_mapreducerows!(pred::P, ::typeof(&), R::AbstractMatrix{Bool},
                A::AbstractSparseMatrixCSC) where {P} = _mapreducerows!(!pred, |, R, A, !)

# findmax/min and argmax/min methods
# find first zero value in sparse matrix - return linear index in full matrix
# non-structural zeros are identified by `iszero` in line with the sparse constructors.
function _findz(A::AbstractSparseMatrixCSC{Tv,Ti}, rows=axes(A,1), cols=axes(A,2)) where {Tv,Ti}
    colptr = getcolptr(A); rowval = rowvals(A); nzval = nonzeros(A)
    row = 0
    rowmin = rows[1]; rowmax = rows[end]
    allrows = (rows == axes(A,1))
    @inbounds for col in cols
        r1::Int = colptr[col]
        r2::Int = colptr[col+1] - 1
        if !allrows && (r1 <= r2)
            r1 += searchsortedfirst(view(rowval, r1:r2), rowmin) - 1
            (r1 <= r2 ) && (r2 = searchsortedlast(view(rowval, r1:r2), rowmax) + r1 - 1)
        end
        row = rowmin
        while (r1 <= r2) && (row == rowval[r1]) && _isnotzero(nzval[r1])
            r1 += 1
            row += 1
        end
        (row <= rowmax) && (return CartesianIndex(row, col))
    end
    return CartesianIndex(0, 0)
end

function _findr(op, A::AbstractSparseMatrixCSC{Tv}, region) where {Tv}
    require_one_based_indexing(A)
    Ti = eltype(keys(A))
    i1 = first(keys(A))
    N = nnz(A)
    L = widelength(A)
    if L == 0
        if prod(map(length, Base.reduced_indices(A, region))) != 0
            throw(ArgumentError("array slices must be non-empty"))
        else
            ri = Base.reduced_indices0(A, region)
            return (zeros(Tv, ri), zeros(Ti, ri))
        end
    end

    colptr = getcolptr(A); rowval = rowvals(A); nzval = nonzeros(A); m = size(A, 1); n = size(A, 2)
    zval = zero(Tv)
    szA = size(A)

    if region == 1 || region == (1,)
        (N == 0) && (return (fill(zval,1,n), fill(i1,1,n)))
        S = Vector{Tv}(undef, n); I = Vector{Ti}(undef, n)
        @inbounds for i = 1 : n
            Sc = zval; Ic = _findz(A, 1:m, i:i)
            if Ic == CartesianIndex(0, 0)
                j = colptr[i]
                Ic = CartesianIndex(rowval[j], i)
                Sc = nzval[j]
            end
            for j = colptr[i] : colptr[i+1]-1
                if op(nzval[j], Sc)
                    Sc = nzval[j]
                    Ic = CartesianIndex(rowval[j], i)
                end
            end
            S[i] = Sc; I[i] = Ic
        end
        return(reshape(S,1,n), reshape(I,1,n))
    elseif region == 2 || region == (2,)
        (N == 0) && (return (fill(zval,m,1), fill(i1,m,1)))
        S = Vector{Tv}(undef, m)
        I = Vector{Ti}(undef, m)
        @inbounds for row in 1:m
            S[row] = zval; I[row] = _findz(A, row:row, 1:n)
            if I[row] == CartesianIndex(0, 0)
                I[row] = CartesianIndex(row, 1)
                S[row] = A[row,1]
            end
        end
        @inbounds for i = 1 : n, j = colptr[i] : colptr[i+1]-1
            row = rowval[j]
            if op(nzval[j], S[row])
                S[row] = nzval[j]
                I[row] = CartesianIndex(row, i)
            end
        end
        return (reshape(S,m,1), reshape(I,m,1))
    elseif region == (1,2)
        (N == 0) && (return (fill(zval,1,1), fill(i1,1,1)))
        hasz = nnz(A) != widelength(A)
        Sv = hasz ? zval : nzval[1]
        Iv::(Ti) = hasz ? _findz(A) : i1
        @inbounds for i = 1 : size(A, 2), j = colptr[i] : (colptr[i+1]-1)
            if op(nzval[j], Sv)
                Sv = nzval[j]
                Iv = CartesianIndex(rowval[j], i)
            end
        end
        return (fill(Sv,1,1), fill(Iv,1,1))
    else
        throw(ArgumentError("invalid value for region; must be 1, 2, or (1,2)"))
    end
end

_isless_fm(a, b)    =  b == b && ( a != a || isless(a, b) )
_isgreater_fm(a, b) =  b == b && ( a != a || isless(b, a) )

findmin(A::AbstractSparseMatrixCSC{Tv}, region::Union{Integer,Tuple{Integer},NTuple{2,Integer}}) where {Tv} =
    _findr(_isless_fm, A, region)
findmax(A::AbstractSparseMatrixCSC{Tv}, region::Union{Integer,Tuple{Integer},NTuple{2,Integer}}) where {Tv} =
    _findr(_isgreater_fm, A, region)
findmin(A::AbstractSparseMatrixCSC; dims::Union{Nothing,Integer,Tuple{Integer},NTuple{2,Integer}} = nothing) =
    isnothing(dims) ? (r = findmin(A, (1,2)); (r[1][1], r[2][1])) : findmin(A, dims)
findmax(A::AbstractSparseMatrixCSC; dims::Union{Nothing,Integer,Tuple{Integer},NTuple{2,Integer}} = nothing) =
    isnothing(dims) ? (r = findmax(A, (1,2)); (r[1][1], r[2][1])) : findmax(A, dims)

argmin(A::AbstractSparseMatrixCSC) = findmin(A)[2]
argmax(A::AbstractSparseMatrixCSC) = findmax(A)[2]

## getindex
function rangesearch(haystack::AbstractRange, needle)
    (i,rem) = divrem(needle - first(haystack), step(haystack))
    (rem==0 && 1<=i+1<=length(haystack)) ? i+1 : 0
end

@RCI @propagate_inbounds getindex(A::AbstractSparseMatrixCSC, I::Tuple{Integer,Integer}) = getindex(A, I[1], I[2])

@RCI @propagate_inbounds function getindex(A::AbstractSparseMatrixCSC{T}, i0::Integer, i1::Integer) where T
    @boundscheck checkbounds(A, i0, i1)
    r1 = Int(@inbounds getcolptr(A)[i1])
    r2 = Int(@inbounds getcolptr(A)[i1+1]-1)
    (r1 > r2) && return zero(T)
    r1 = searchsortedfirst(view(rowvals(A), r1:r2), i0) + r1 - 1
    ((r1 > r2) || (rowvals(A)[r1] != i0)) ? zero(T) : nonzeros(A)[r1]
end

# Colon translation
getindex(A::AbstractSparseMatrixCSC, ::Colon, ::Colon) = copy(A)
getindex(A::AbstractSparseMatrixCSC, i, ::Colon)       = getindex(A, i, axes(A,2))
getindex(A::AbstractSparseMatrixCSC, ::Colon, i)       = getindex(A, axes(A,1), i)

function getindex_cols(A::AbstractSparseMatrixCSC{Tv,Ti}, J::AbstractVector) where {Tv,Ti}
    require_one_based_indexing(A, J)
    # for indexing whole columns
    (m, n) = size(A)
    nJ = length(J)

    colptrA = getcolptr(A); rowvalA = rowvals(A); nzvalA = nonzeros(A)

    colptrS = Vector{Ti}(undef, nJ+1)
    colptrS[1] = 1
    nnzS = 0

    @inbounds for j = 1:nJ
        col = J[j]
        1 <= col <= n || throw(BoundsError())
        nnzS += colptrA[col+1] - colptrA[col]
        colptrS[j+1] = nnzS + 1
    end

    rowvalS = Vector{Ti}(undef, nnzS)
    nzvalS  = Vector{Tv}(undef, nnzS)
    ptrS = 0

    @inbounds for j = 1:nJ
        col = J[j]
        for k = colptrA[col]:colptrA[col+1]-1
            ptrS += 1
            rowvalS[ptrS] = rowvalA[k]
            nzvalS[ptrS] = nzvalA[k]
        end
    end
    return @if_move_fixed A SparseMatrixCSC(m, nJ, colptrS, rowvalS, nzvalS)
end

getindex_traverse_col(::AbstractUnitRange, lo::Integer, hi::Integer) = lo:hi
getindex_traverse_col(I::StepRange, lo::Integer, hi::Integer) = step(I) > 0 ? (lo:1:hi) : (hi:-1:lo)

function getindex(A::AbstractSparseMatrixCSC{Tv,Ti}, I::AbstractRange, J::AbstractVector) where {Tv,Ti<:Integer}
    require_one_based_indexing(A, I, J)
    # Ranges for indexing rows
    (m, n) = size(A)
    # whole columns:
    if I == 1:m
        return getindex_cols(A, J)
    end

    nI = length(I)
    nI == 0 || (minimum(I) >= 1 && maximum(I) <= m) || throw(BoundsError())
    nJ = length(J)
    colptrA = getcolptr(A); rowvalA = rowvals(A); nzvalA = nonzeros(A)
    colptrS = Vector{Ti}(undef, nJ+1)
    colptrS[1] = 1
    nnzS = 0

    # Form the structure of the result and compute space
    @inbounds for j = 1:nJ
        col = J[j]
        1 <= col <= n || throw(BoundsError())
        @simd for k in colptrA[col]:colptrA[col+1]-1
            nnzS += rowvalA[k] in I # `in` is fast for ranges
        end
        colptrS[j+1] = nnzS+1
    end

    # Populate the values in the result
    rowvalS = Vector{Ti}(undef, nnzS)
    nzvalS  = Vector{Tv}(undef, nnzS)
    ptrS    = 1

    @inbounds for j = 1:nJ
        col = J[j]
        for k = getindex_traverse_col(I, colptrA[col], colptrA[col+1]-1)
            rowA = rowvalA[k]
            i = rangesearch(I, rowA)
            if i > 0
                rowvalS[ptrS] = i
                nzvalS[ptrS] = nzvalA[k]
                ptrS += 1
            end
        end
    end

    return @if_move_fixed A SparseMatrixCSC(nI, nJ, colptrS, rowvalS, nzvalS)
end

function getindex_I_sorted(A::AbstractSparseMatrixCSC{Tv,Ti}, I::AbstractVector, J::AbstractVector) where {Tv,Ti}
    require_one_based_indexing(A, I, J)
    # Sorted vectors for indexing rows.
    # Similar to getindex_general but without the transpose trick.
    (m, n) = size(A)

    nI   = length(I)
    nzA  = nnz(A)
    avgM = div(nzA,n)
    # Heuristics based on experiments discussed in:
    # https://github.com/JuliaLang/julia/issues/12860
    # https://github.com/JuliaLang/julia/pull/12934
    alg = ((m > nzA) && (m > nI)) ? 0 :
          ((nI - avgM) > 2^8) ? 1 :
          ((avgM - nI) > 2^10) ? 0 : 2

    (alg == 0) ? getindex_I_sorted_bsearch_A(A, I, J) :
    (alg == 1) ? getindex_I_sorted_bsearch_I(A, I, J) :
    return getindex_I_sorted_linear(A, I, J)
end

function getindex_I_sorted_bsearch_A(A::AbstractSparseMatrixCSC{Tv,Ti}, I::AbstractVector, J::AbstractVector) where {Tv,Ti}
    require_one_based_indexing(A, I, J)
    nI = length(I)
    nJ = length(J)

    colptrA = getcolptr(A); rowvalA = rowvals(A); nzvalA = nonzeros(A)
    colptrS = Vector{Ti}(undef, nJ+1)
    colptrS[1] = 1

    ptrS = 1
    # determine result size
    @inbounds for j = 1:nJ
        col = J[j]
        ptrI::Int = 1 # runs through I
        ptrA::Int = colptrA[col]
        stopA::Int = colptrA[col+1]-1
        if ptrA <= stopA
            while ptrI <= nI
                rowI = I[ptrI]
                ptrI += 1
                (rowvalA[ptrA] > rowI) && continue
                ptrA += searchsortedfirst(view(rowvalA, ptrA:stopA), rowI) - 1
                (ptrA <= stopA) || break
                if rowvalA[ptrA] == rowI
                    ptrS += 1
                end
            end
        end
        colptrS[j+1] = ptrS
    end

    rowvalS = Vector{Ti}(undef, ptrS-1)
    nzvalS  = Vector{Tv}(undef, ptrS-1)

    # fill the values
    ptrS = 1
    @inbounds for j = 1:nJ
        col = J[j]
        ptrI::Int = 1 # runs through I
        ptrA::Int = colptrA[col]
        stopA::Int = colptrA[col+1]-1
        if ptrA <= stopA
            while ptrI <= nI
                rowI = I[ptrI]
                if rowvalA[ptrA] <= rowI
                    ptrA += searchsortedfirst(view(rowvalA, ptrA:stopA), rowI) - 1
                    (ptrA <= stopA) || break
                    if rowvalA[ptrA] == rowI
                        rowvalS[ptrS] = ptrI
                        nzvalS[ptrS] = nzvalA[ptrA]
                        ptrS += 1
                    end
                end
                ptrI += 1
            end
        end
    end
    return @if_move_fixed A SparseMatrixCSC(nI, nJ, colptrS, rowvalS, nzvalS)
end

function getindex_I_sorted_linear(A::AbstractSparseMatrixCSC{Tv,Ti}, I::AbstractVector, J::AbstractVector) where {Tv,Ti}
    require_one_based_indexing(A, I, J)
    nI = length(I)
    nJ = length(J)

    colptrA = getcolptr(A); rowvalA = rowvals(A); nzvalA = nonzeros(A)
    colptrS = Vector{Ti}(undef, nJ+1)
    colptrS[1] = 1
    cacheI = zeros(Int, size(A, 1))

    ptrS   = 1
    # build the cache and determine result size
    @inbounds for j = 1:nJ
        col = J[j]
        ptrI::Int = 1 # runs through I
        ptrA::Int = colptrA[col]
        stopA::Int = colptrA[col+1]
        while ptrI <= nI && ptrA < stopA
            rowA = rowvalA[ptrA]
            rowI = I[ptrI]

            if rowI > rowA
                ptrA += 1
            elseif rowI < rowA
                ptrI += 1
            else
                (cacheI[rowA] == 0) && (cacheI[rowA] = ptrI)
                ptrS += 1
                ptrI += 1
            end
        end
        colptrS[j+1] = ptrS
    end

    rowvalS = Vector{Ti}(undef, ptrS-1)
    nzvalS  = Vector{Tv}(undef, ptrS-1)

    # fill the values
    ptrS = 1
    @inbounds for j = 1:nJ
        col = J[j]
        ptrA::Int = colptrA[col]
        stopA::Int = colptrA[col+1]
        while ptrA < stopA
            rowA = rowvalA[ptrA]
            ptrI = cacheI[rowA]
            if ptrI > 0
                while ptrI <= nI && I[ptrI] == rowA
                    rowvalS[ptrS] = ptrI
                    nzvalS[ptrS] = nzvalA[ptrA]
                    ptrS += 1
                    ptrI += 1
                end
            end
            ptrA += 1
        end
    end
    return @if_move_fixed A SparseMatrixCSC(nI, nJ, colptrS, rowvalS, nzvalS)
end

function getindex_I_sorted_bsearch_I(A::AbstractSparseMatrixCSC{Tv,Ti}, I::AbstractVector, J::AbstractVector) where {Tv,Ti}
    require_one_based_indexing(A, I, J)
    nI = length(I)
    nJ = length(J)

    colptrA = getcolptr(A); rowvalA = rowvals(A); nzvalA = nonzeros(A)
    colptrS = Vector{Ti}(undef, nJ+1)
    colptrS[1] = 1

    m = size(A, 1)

    # cacheI is used first to store num occurrences of each row in columns of interest
    # and later to store position of first occurrence of each row in I
    cacheI = zeros(Int, m)

    # count rows
    @inbounds for j = 1:nJ
        col = J[j]
        for ptrA in colptrA[col]:(colptrA[col+1]-1)
            cacheI[rowvalA[ptrA]] += 1
        end
    end

    # fill cache and count nnz
    ptrS::Int = 0
    ptrI::Int = 1
    @inbounds for j = 1:m
        cval = cacheI[j]
        (cval == 0) && continue
        ptrI += searchsortedfirst(view(I, ptrI:nI), j) - 1
        cacheI[j] = ptrI
        while ptrI <= nI && I[ptrI] == j
            ptrS += cval
            ptrI += 1
        end
        if ptrI > nI
            @simd for i=(j+1):m; @inbounds cacheI[i]=ptrI; end
            break
        end
    end
    rowvalS = Vector{Ti}(undef, ptrS)
    nzvalS  = Vector{Tv}(undef, ptrS)
    colptrS[nJ+1] = ptrS+1

    # fill the values
    ptrS = 1
    @inbounds for j = 1:nJ
        col = J[j]
        ptrA::Int = colptrA[col]
        stopA::Int = colptrA[col+1]
        while ptrA < stopA
            rowA = rowvalA[ptrA]
            ptrI = cacheI[rowA]
            (ptrI > nI) && break
            if ptrI > 0
                while I[ptrI] == rowA
                    rowvalS[ptrS] = ptrI
                    nzvalS[ptrS] = nzvalA[ptrA]
                    ptrS += 1
                    ptrI += 1
                    (ptrI > nI) && break
                end
            end
            ptrA += 1
        end
        colptrS[j+1] = ptrS
    end
    return @if_move_fixed A SparseMatrixCSC(nI, nJ, colptrS, rowvalS, nzvalS)
end

function permute_rows!(S::AbstractSparseMatrixCSC{Tv,Ti}, pI::Vector{Int}) where {Tv,Ti}
    (m, n) = size(S)
    colptrS = getcolptr(S); rowvalS = rowvals(S); nzvalS = nonzeros(S)
    # preallocate temporary sort space
    nr = min(nnz(S), m)

    rowperm = Vector{Int}(undef, nr)
    rowval_temp = Vector{Ti}(undef, nr)
    rnzval_temp = Vector{Tv}(undef, nr)
    perm = Base.Perm(Base.ord(isless, identity, false, Base.Order.Forward), rowval_temp)

    @inbounds for j in axes(S,2)
        rowrange = nzrange(S, j)
        nr = length(rowrange)
        resize!(rowperm, nr)
        resize!(rowval_temp, nr)
        (nr > 0) || continue
        k = 1
        for i in rowrange
            rowA = rowvalS[i]
            rowval_temp[k] = pI[rowA]
            rnzval_temp[k] = nzvalS[i]
            k += 1
        end

        if nr <= 16
            alg = Base.Sort.InsertionSort
        else
            alg = Base.Sort.QuickSort
        end

        # Reset permutation
        rowperm .= 1:nr
        sort!(rowperm, alg, perm)

        k = 1
        for i in rowrange
            kperm = rowperm[k]
            rowvalS[i] = rowval_temp[kperm]
            nzvalS[i] = rnzval_temp[kperm]
            k += 1
        end
    end
    return _checkbuffers(S)
end

function getindex_general(A::AbstractSparseMatrixCSC, I::AbstractVector, J::AbstractVector)
    require_one_based_indexing(A, I, J)
    pI = sortperm(I)
    @inbounds Is = I[pI]
    return permute_rows!(getindex_I_sorted(A, Is, J), pI)
end

# the general case:
function getindex(A::AbstractSparseMatrixCSC{Tv,Ti}, I::AbstractVector, J::AbstractVector) where {Tv,Ti}
    require_one_based_indexing(A, I, J)
    (m, n) = size(A)

    if !isempty(J)
        minj, maxj = extrema(J)
        ((minj < 1) || (maxj > n)) && throw(BoundsError())
    end

    if !isempty(I)
        mini, maxi = extrema(I)
        ((mini < 1) || (maxi > m)) && throw(BoundsError())
    end

    if isempty(I) || isempty(J) || (0 == nnz(A))
        return spzeros(Tv, Ti, length(I), length(J))
    end

    if issorted(I)
        return getindex_I_sorted(A, I, J)
    else
        return getindex_general(A, I, J)
    end
end

function getindex(A::AbstractSparseMatrixCSC{Tv,Ti}, I::AbstractArray) where {Tv,Ti}
    require_one_based_indexing(A, I)
    szA = size(A)
    nA = szA[1]*szA[2]
    colptrA = getcolptr(A)
    rowvalA = rowvals(A)
    nzvalA = nonzeros(A)

    n = length(I)
    outm = size(I,1)
    outn = size(I,2)
    szB = (outm, outn)
    colptrB = zeros(Ti, outn+1)
    rowvalB = Vector{Ti}(undef, n)
    nzvalB = Vector{Tv}(undef, n)

    colB = 1
    rowB = 1
    colptrB[colB] = 1
    idxB = 1

    CartIndsA = CartesianIndices(szA)
    CartIndsB = CartesianIndices(szB)

    for i in 1:n
        @boundscheck checkbounds(A, I[i])
        row,col = Tuple(CartIndsA[I[i]])
        for r in colptrA[col]:(colptrA[col+1]-1)
            @inbounds if rowvalA[r] == row
                rowB,colB = Tuple(CartIndsB[i])
                colptrB[colB+1] += 1
                rowvalB[idxB] = rowB
                nzvalB[idxB] = nzvalA[r]
                idxB += 1
                break
            end
        end
    end
    cumsum!(colptrB,colptrB)
    if n > (idxB-1)
        deleteat!(nzvalB, idxB:n)
        deleteat!(rowvalB, idxB:n)
    end
    @if_move_fixed A SparseMatrixCSC(outm, outn, colptrB, rowvalB, nzvalB)
end

# logical getindex
getindex(A::AbstractSparseMatrixCSC{<:Any,<:Integer}, I::AbstractRange{Bool}, J::AbstractVector{Bool}) = error("Cannot index with AbstractRange{Bool}")
getindex(A::AbstractSparseMatrixCSC{<:Any,<:Integer}, I::AbstractRange{Bool}, J::AbstractVector{<:Integer}) = error("Cannot index with AbstractRange{Bool}")

getindex(A::AbstractSparseMatrixCSC, I::AbstractRange{<:Integer}, J::AbstractVector{Bool}) = A[I,findall(J)]
getindex(A::AbstractSparseMatrixCSC, I::Integer, J::AbstractVector{Bool}) = A[I,findall(J)]
getindex(A::AbstractSparseMatrixCSC, I::AbstractVector{Bool}, J::Integer) = A[findall(I),J]
getindex(A::AbstractSparseMatrixCSC, I::AbstractVector{Bool}, J::AbstractVector{Bool}) = A[findall(I),findall(J)]
getindex(A::AbstractSparseMatrixCSC, I::AbstractVector{<:Integer}, J::AbstractVector{Bool}) = A[I,findall(J)]
getindex(A::AbstractSparseMatrixCSC, I::AbstractVector{Bool}, J::AbstractVector{<:Integer}) = A[findall(I),J]

## setindex!

# dispatch helper for #29034
@RCI setindex!(A::AbstractSparseMatrixCSC, _v, _i::Integer, _j::Integer) = _setindex_scalar!(A, _v, _i, _j)

function _setindex_scalar!(A::AbstractSparseMatrixCSC{Tv,Ti}, _v, _i::Integer, _j::Integer) where {Tv,Ti<:Integer}
    v = convert(Tv, _v)
    i = convert(Ti, _i)
    j = convert(Ti, _j)
    if !((1 <= i <= size(A, 1)) & (1 <= j <= size(A, 2)))
        throw(BoundsError(A, (i,j)))
    end
    coljfirstk = Int(getcolptr(A)[j])
    coljlastk = Int(getcolptr(A)[j+1] - 1)
    searchk = searchsortedfirst(view(rowvals(A), coljfirstk:coljlastk), i) + coljfirstk - 1
    if searchk <= coljlastk && rowvals(A)[searchk] == i
        # Column j contains entry A[i,j]. Update and return
        nonzeros(A)[searchk] = v
        return A
    end
    # Column j does not contain entry A[i,j]. If v is nonzero, insert entry A[i,j] = v
    # and return. If to the contrary v is zero, then simply return.
    if v isa AbstractArray || v !== zero(eltype(A)) # stricter than iszero to support A[i] = -0.0
        nz = getcolptr(A)[size(A, 2)+1]
        # throw exception before state is partially modified
        !isbitstype(Ti) || nz < typemax(Ti) ||
            throw(ArgumentError("nnz(A) going to exceed typemax(Ti) = $(typemax(Ti))"))

        # if nnz(A) < length(rowval/nzval): no need to grow rowval and preserve values
        _insert!(rowvals(A), searchk, i, nz)
        _insert!(nonzeros(A), searchk, v, nz)
        @simd for m in (j + 1):(size(A, 2) + 1)
            @inbounds getcolptr(A)[m] += Ti(1)
        end
    end
    return A
end

# insert item at position pos, shifting only from pos+1 to nz
function _insert!(v::Vector, pos::Integer, item, nz::Integer)
    if nz > length(v)
        insert!(v, pos, item)
    else # nz < length(v)
        Base.unsafe_copyto!(v, pos+1, v, pos, nz - pos)
        v[pos] = item
        v
    end
end

function Base.fill!(V::SubArray{Tv, <:Any, <:AbstractSparseMatrixCSC{Tv}, <:Tuple{Vararg{Union{Integer, AbstractVector{<:Integer}},2}}}, x) where Tv
    A = V.parent
    I, J = V.indices
    if isempty(I) || isempty(J); return A; end
    # lt=≤ to check for strict sorting
    if !issorted(I, lt=≤); I = sort!(unique(I)); end
    if !issorted(J, lt=≤); J = sort!(unique(J)); end
    if (I[1] < 1 || I[end] > size(A, 1)) || (J[1] < 1 || J[end] > size(A, 2))
        throw(BoundsError(A, (I, J)))
    end
    if _iszero(x)
        _spsetz_setindex!(A, I, J)
    else
        _spsetnz_setindex!(A, convert(Tv, x), I, J)
    end
    _checkbuffers(A)
    V
end
"""
Helper method for immediately preceding fill! method. For all (i,j) such that i in I and
j in J, assigns zero to A[i,j] if A[i,j] is a presently-stored entry, and otherwise does nothing.
"""
function _spsetz_setindex!(A::AbstractSparseMatrixCSC,
        I::Union{Integer, AbstractVector{<:Integer}}, J::Union{Integer, AbstractVector{<:Integer}})
    require_one_based_indexing(A, I, J)
    lengthI = length(I)
    for j in J
        coljAfirstk = getcolptr(A)[j]
        coljAlastk = getcolptr(A)[j+1] - 1
        coljAfirstk > coljAlastk && continue
        kA = coljAfirstk
        kI = 1
        entrykArow = rowvals(A)[kA]
        entrykIrow = I[kI]
        while true
            if entrykArow < entrykIrow
                kA += 1
                kA > coljAlastk && break
                entrykArow = rowvals(A)[kA]
            elseif entrykArow > entrykIrow
                kI += 1
                kI > lengthI && break
                entrykIrow = I[kI]
            else # entrykArow == entrykIrow
                nonzeros(A)[kA] = zero(eltype(A))
                kA += 1
                kI += 1
                (kA > coljAlastk || kI > lengthI) && break
                entrykArow = rowvals(A)[kA]
                entrykIrow = I[kI]
            end
        end
    end
end
"""
Helper method for immediately preceding fill! method. For all (i,j) such that i in I
and j in J, assigns x to A[i,j] if A[i,j] is a presently-stored entry, and allocates and
assigns x to A[i,j] if A[i,j] is not presently stored.
"""
function _spsetnz_setindex!(A::AbstractSparseMatrixCSC{Tv}, x::Tv,
        I::Union{Integer, AbstractVector{<:Integer}}, J::Union{Integer, AbstractVector{<:Integer}}) where Tv
    require_one_based_indexing(A, I, J)
    m, n = size(A)
    lenI = length(I)

    nnzA = nnz(A) + lenI * length(J)

    rowvalA = rowval = rowvals(A)
    nzvalA = nzval = nonzeros(A)

    rowidx = 1
    nadd = 0
    @inbounds for col in axes(A,2)
        rrange = nzrange(A, col)
        if nadd > 0
            getcolptr(A)[col] = getcolptr(A)[col] + nadd
        end

        if col in J
            if isempty(rrange) # set new vals only
                nincl = lenI
                if nadd == 0
                    rowval = copy(rowvalA)
                    nzval = copy(nzvalA)
                    resize!(rowvalA, nnzA)
                    resize!(nzvalA, nnzA)
                end
                r = rowidx:(rowidx+nincl-1)
                rowvalA[r] .= I
                for rr in r
                    nzvalA[rr] = x
                end
                rowidx += nincl
                nadd += nincl
            else # set old + new vals
                old_ptr = rrange[1]
                old_stop = rrange[end]
                new_ptr = 1
                new_stop = lenI

                while true
                    old_row = rowval[old_ptr]
                    new_row = I[new_ptr]
                    if old_row < new_row
                        rowvalA[rowidx] = old_row
                        nzvalA[rowidx] = nzval[old_ptr]
                        rowidx += 1
                        old_ptr += 1
                    else
                        if old_row == new_row
                            old_ptr += 1
                        else
                            if nadd == 0
                                rowval = copy(rowvalA)
                                nzval = copy(nzvalA)
                                resize!(rowvalA, nnzA)
                                resize!(nzvalA, nnzA)
                            end
                            nadd += 1
                        end
                        rowvalA[rowidx] = new_row
                        nzvalA[rowidx] = x
                        rowidx += 1
                        new_ptr += 1
                    end

                    if old_ptr > old_stop
                        if new_ptr <= new_stop
                            if nadd == 0
                                rowval = copy(rowvalA)
                                nzval = copy(nzvalA)
                                resize!(rowvalA, nnzA)
                                resize!(nzvalA, nnzA)
                            end
                            r = rowidx:(rowidx+(new_stop-new_ptr))
                            rowvalA[r] .= I isa Number ? I : I[new_ptr:new_stop]
                            for rr in r
                                nzvalA[rr] = x
                            end
                            rowidx += length(r)
                            nadd += length(r)
                        end
                        break
                    end

                    if new_ptr > new_stop
                        nincl = old_stop-old_ptr+1
                        copyto!(rowvalA, rowidx, rowval, old_ptr, nincl)
                        copyto!(nzvalA, rowidx, nzval, old_ptr, nincl)
                        rowidx += nincl
                        break
                    end
                end
            end
        elseif !isempty(rrange) # set old vals only
            nincl = length(rrange)
            copyto!(rowvalA, rowidx, rowval, rrange[1], nincl)
            copyto!(nzvalA, rowidx, nzval, rrange[1], nincl)
            rowidx += nincl
        end
    end

    if nadd > 0
        getcolptr(A)[n+1] = rowidx
        deleteat!(rowvalA, rowidx:nnzA)
        deleteat!(nzvalA, rowidx:nnzA)
    end
    return A
end

# Nonscalar A[I,J] = B: Convert B to a SparseMatrixCSC of the appropriate shape first
_to_same_csc(::AbstractSparseMatrixCSC{Tv, Ti}, V::AbstractMatrix, I...) where {Tv,Ti} = convert(SparseMatrixCSC{Tv,Ti}, V)
_to_same_csc(::AbstractSparseMatrixCSC{Tv, Ti}, V::AbstractMatrix, i::Integer, J) where {Tv,Ti} = convert(SparseMatrixCSC{Tv,Ti}, reshape(V, (1, length(J))))
_to_same_csc(::AbstractSparseMatrixCSC{Tv, Ti}, V::AbstractVector, I...) where {Tv,Ti} = convert(SparseMatrixCSC{Tv,Ti}, reshape(V, map(length, I)))

setindex!(A::AbstractSparseMatrixCSC{Tv}, B::AbstractVecOrMat, I::Integer, J::Integer) where {Tv} = _setindex_scalar!(A, B, I, J)

function setindex!(A::AbstractSparseMatrixCSC{Tv,Ti}, V::AbstractVecOrMat, Ix::Union{Integer, AbstractVector{<:Integer}, Colon}, Jx::Union{Integer, AbstractVector{<:Integer}, Colon}) where {Tv,Ti<:Integer}
    require_one_based_indexing(A, V, Ix, Jx)
    (I, J) = Base.ensure_indexable(to_indices(A, (Ix, Jx)))
    checkbounds(A, I, J)
    nJ = length(J)
    Base.setindex_shape_check(V, length(I), nJ)
    B = _to_same_csc(A, V, I, J)

    m, n = size(A)
    if (!isempty(I) && (I[1] < 1 || I[end] > m)) || (!isempty(J) && (J[1] < 1 || J[end] > n))
        throw(BoundsError(A, (I, J)))
    end
    if isempty(I) || isempty(J)
        return A
    end

    issortedI = issorted(I)
    issortedJ = issorted(J)
    if !issortedI && !issortedJ
        pI = sortperm(I); @inbounds I = I[pI]
        pJ = sortperm(J); @inbounds J = J[pJ]
        B = B[pI, pJ]
    elseif !issortedI
        pI = sortperm(I); @inbounds I = I[pI]
        B = B[pI,:]
    elseif !issortedJ
        pJ = sortperm(J); @inbounds J = J[pJ]
        B = B[:, pJ]
    end

    colptrA = getcolptr(A); rowvalA = rowvals(A); nzvalA = nonzeros(A)
    colptrB = getcolptr(B); rowvalB = rowvals(B); nzvalB = nonzeros(B)

    nnzS = nnz(A) + nnz(B)

    colptrS = copy(getcolptr(A))
    rowvalS = copy(rowvals(A))
    nzvalS = copy(nonzeros(A))

    resize!(rowvalA, nnzS)
    resize!(nzvalA, nnzS)

    colB = 1

    I_asgn = falses(m)
    fill!(view(I_asgn, I), true)

    ptrS = 1

    @inbounds for col in axes(A,2)

        # Copy column of A if it is not being assigned into
        if colB > nJ || col != J[colB]
            colptrA[col+1] = colptrA[col] + (colptrS[col+1]-colptrS[col])

            for k = colptrS[col]:colptrS[col+1]-1
                rowvalA[ptrS] = rowvalS[k]
                nzvalA[ptrS] = nzvalS[k]
                ptrS += 1
            end
            continue
        end

        ptrA::Int  = colptrS[col]
        stopA::Int = colptrS[col+1]
        ptrB::Int  = colptrB[colB]
        stopB::Int = colptrB[colB+1]

        while ptrA < stopA && ptrB < stopB
            rowA = rowvalS[ptrA]
            rowB = I[rowvalB[ptrB]]
            if rowA < rowB
                rowvalA[ptrS] = rowA
                nzvalA[ptrS] = I_asgn[rowA] ? zero(Tv) : nzvalS[ptrA]
                ptrS += 1
                ptrA += 1
            elseif rowB < rowA
                if nzvalB[ptrB] != zero(Tv)
                    rowvalA[ptrS] = rowB
                    nzvalA[ptrS] = nzvalB[ptrB]
                    ptrS += 1
                end
                ptrB += 1
            else
                rowvalA[ptrS] = rowB
                nzvalA[ptrS] = nzvalB[ptrB]
                ptrS += 1
                ptrB += 1
                ptrA += 1
            end
        end

        while ptrA < stopA
            rowA = rowvalS[ptrA]
            rowvalA[ptrS] = rowA
            nzvalA[ptrS] = I_asgn[rowA] ? zero(Tv) : nzvalS[ptrA]
            ptrS += 1
            ptrA += 1
        end

        while ptrB < stopB
            rowB = I[rowvalB[ptrB]]
            if nzvalB[ptrB] != zero(Tv)
                rowvalA[ptrS] = rowB
                nzvalA[ptrS] = nzvalB[ptrB]
                ptrS += 1
            end
            ptrB += 1
        end

        colptrA[col+1] = ptrS
        colB += 1
    end

    deleteat!(rowvalA, colptrA[end]:length(rowvalA))
    deleteat!(nzvalA, colptrA[end]:length(nzvalA))

    return _checkbuffers(A)
end

# Logical setindex!

setindex!(A::Matrix, x::AbstractSparseMatrixCSC, I::Integer, J::AbstractVector{Bool}) = setindex!(A, Array(x), I, findall(J))
setindex!(A::Matrix, x::AbstractSparseMatrixCSC, I::AbstractVector{Bool}, J::Integer) = setindex!(A, Array(x), findall(I), J)
setindex!(A::Matrix, x::AbstractSparseMatrixCSC, I::AbstractVector{Bool}, J::AbstractVector{Bool}) = setindex!(A, Array(x), findall(I), findall(J))
setindex!(A::Matrix, x::AbstractSparseMatrixCSC, I::AbstractVector{<:Integer}, J::AbstractVector{Bool}) = setindex!(A, Array(x), I, findall(J))
setindex!(A::Matrix, x::AbstractSparseMatrixCSC, I::AbstractVector{Bool}, J::AbstractVector{<:Integer}) = setindex!(A, Array(x), findall(I), J)

function setindex!(A::AbstractSparseMatrixCSC, x::AbstractArray, I::AbstractMatrix{Bool})
    require_one_based_indexing(A, x, I)
    checkbounds(A, I)
    n = sum(I)
    (n == 0) && (return A)

    colptrA = getcolptr(A); rowvalA = rowvals(A); nzvalA = nonzeros(A)
    colptrB = colptrA; rowvalB = rowvalA; nzvalB = nzvalA
    nadd = 0
    bidx = xidx = 1
    r1 = r2 = 0

    @inbounds for col in axes(A,2)
        r1 = Int(colptrA[col])
        r2 = Int(colptrA[col+1]-1)

        for row in axes(A,1)
            if I[row, col]
                v = x[xidx]
                xidx += 1

                if r1 <= r2
                    copylen = searchsortedfirst(view(rowvalA, r1:r2), row) - 1
                    if (copylen > 0)
                        if (nadd > 0)
                            copyto!(rowvalB, bidx, rowvalA, r1, copylen)
                            copyto!(nzvalB, bidx, nzvalA, r1, copylen)
                        end
                        bidx += copylen
                        r1 += copylen
                    end
                end

                # 0: no change, 1: update, 2: add new
                mode = ((r1 <= r2) && (rowvalA[r1] == row)) ? 1 : ((v == 0) ? 0 : 2)

                if (mode > 1) && (nadd == 0)
                    # copy storage to take changes
                    colptrA = copy(colptrB)
                    memreq = (x == 0) ? 0 : n
                    # this x == 0 check and approach doesn't jive with use of v above
                    # and may not make sense generally, as scalar x == 0 probably
                    # means this section should never be called. also may not be generic.
                    # TODO: clean this up, maybe separate scalar and array X cases
                    rowvalA = copy(rowvalB)
                    nzvalA = copy(nzvalB)
                    resize!(rowvalB, length(rowvalA)+memreq)
                    resize!(nzvalB, length(rowvalA)+memreq)
                end
                if mode == 1
                    rowvalB[bidx] = row
                    nzvalB[bidx] = v
                    bidx += 1
                    r1 += 1
                elseif mode == 2
                    rowvalB[bidx] = row
                    nzvalB[bidx] = v
                    bidx += 1
                    nadd += 1
                end
                (xidx > n) && break
            end # if I[row, col]
        end # for row in axes(A,1)

        if (nadd != 0)
            l = r2-r1+1
            if l > 0
                copyto!(rowvalB, bidx, rowvalA, r1, l)
                copyto!(nzvalB, bidx, nzvalA, r1, l)
                bidx += l
            end
            colptrB[col+1] = bidx

            if (xidx > n) && (length(colptrB) > (col+1))
                diff = nadd
                colptrB[(col+2):end] = colptrA[(col+2):end] .+ diff
                r1 = colptrA[col+1]
                r2 = colptrA[end]-1
                l = r2-r1+1
                if l > 0
                    copyto!(rowvalB, bidx, rowvalA, r1, l)
                    copyto!(nzvalB, bidx, nzvalA, r1, l)
                    bidx += l
                end
            end
        else
            bidx = colptrA[col+1]
        end
        (xidx > n) && break
    end # for col in axes(A,2)

    if (nadd != 0)
        n = length(nzvalB)
        if n > (bidx-1)
            deleteat!(nzvalB, bidx:n)
            deleteat!(rowvalB, bidx:n)
        end
    end
    return _checkbuffers(A)
end

function setindex!(A::AbstractSparseMatrixCSC, x::AbstractArray, Ix::AbstractVector{<:Integer})
    require_one_based_indexing(A, x, Ix)
    (I,) = Base.ensure_indexable(to_indices(A, (Ix,)))
    # We check bounds after sorting I
    n = length(I)
    (n == 0) && (return A)

    colptrA = getcolptr(A); rowvalA = rowvals(A); nzvalA = nonzeros(A); szA = size(A)
    colptrB = colptrA; rowvalB = rowvalA; nzvalB = nzvalA
    nadd = 0
    bidx = aidx = 1

    S = issorted(I) ? (1:n) : sortperm(I)
    sxidx = r1 = r2 = 0

    if (!isempty(I) && (I[S[1]] < 1 || I[S[end]] > widelength(A)))
        throw(BoundsError(A, I))
    end

    isa(x, AbstractArray) && setindex_shape_check(x, length(I))

    CartIndsA = CartesianIndices(szA)

    lastcol = 0
    (nrowA, ncolA) = szA
    @inbounds for xidx in 1:n
        sxidx = S[xidx]
        (sxidx < n) && (I[sxidx] == I[sxidx+1]) && continue

        row,col = Tuple(CartIndsA[I[sxidx]])
        v = x[sxidx]

        if col > lastcol
            r1 = Int(colptrA[col])
            r2 = Int(colptrA[col+1] - 1)

            # copy from last position till current column
            if (nadd > 0)
                colptrB[(lastcol+1):col] = colptrA[(lastcol+1):col] .+ nadd
                copylen = r1 - aidx
                if copylen > 0
                    copyto!(rowvalB, bidx, rowvalA, aidx, copylen)
                    copyto!(nzvalB, bidx, nzvalA, aidx, copylen)
                    aidx += copylen
                    bidx += copylen
                end
            else
                aidx = bidx = r1
            end
            lastcol = col
        end

        if r1 <= r2
            copylen = searchsortedfirst(view(rowvalA, r1:r2), row) - 1
            if (copylen > 0)
                if (nadd > 0)
                    copyto!(rowvalB, bidx, rowvalA, r1, copylen)
                    copyto!(nzvalB, bidx, nzvalA, r1, copylen)
                end
                bidx += copylen
                r1 += copylen
                aidx += copylen
            end
        end

        # 0: no change, 1: update, 2: add new
        mode = ((r1 <= r2) && (rowvalA[r1] == row)) ? 1 : ((v == 0) ? 0 : 2)

        if (mode > 1) && (nadd == 0)
            # copy storage to take changes
            colptrA = copy(colptrB)
            memreq = (x == 0) ? 0 : n
            # see comment/TODO for same statement in preceding logical setindex! method
            rowvalA = copy(rowvalB)
            nzvalA = copy(nzvalB)
            resize!(rowvalB, length(rowvalA)+memreq)
            resize!(nzvalB, length(rowvalA)+memreq)
        end
        if mode == 1
            rowvalB[bidx] = row
            nzvalB[bidx] = v
            bidx += 1
            aidx += 1
            r1 += 1
        elseif mode == 2
            rowvalB[bidx] = row
            nzvalB[bidx] = v
            bidx += 1
            nadd += 1
        end
    end

    # copy the rest
    @inbounds if (nadd > 0)
        colptrB[(lastcol+1):end] = colptrA[(lastcol+1):end] .+ nadd
        r1 = colptrA[end]-1
        copylen = r1 - aidx + 1
        if copylen > 0
            copyto!(rowvalB, bidx, rowvalA, aidx, copylen)
            copyto!(nzvalB, bidx, nzvalA, aidx, copylen)
            aidx += copylen
            bidx += copylen
        end

        n = length(nzvalB)
        if n > (bidx-1)
            deleteat!(nzvalB, bidx:n)
            deleteat!(rowvalB, bidx:n)
        end
    end
    return _checkbuffers(A)
end

## dropstored! methods
"""
    dropstored!(A::AbstractSparseMatrixCSC, i::Integer, j::Integer)

Drop entry `A[i,j]` from `A` if `A[i,j]` is stored, and otherwise do nothing.

```jldoctest
julia> A = sparse([1 2; 0 0])
2×2 SparseMatrixCSC{Int64, Int64} with 2 stored entries:
 1  2
 ⋅  ⋅

julia> SparseArrays.dropstored!(A, 1, 2); A
2×2 SparseMatrixCSC{Int64, Int64} with 1 stored entry:
 1  ⋅
 ⋅  ⋅
```
"""
function dropstored!(A::AbstractSparseMatrixCSC, i::Integer, j::Integer)
    if !((1 <= i <= size(A, 1)) & (1 <= j <= size(A, 2)))
        throw(BoundsError(A, (i,j)))
    end
    coljfirstk = Int(getcolptr(A)[j])
    coljlastk = Int(getcolptr(A)[j+1] - 1)
    searchk = searchsortedfirst(view(rowvals(A), coljfirstk:coljlastk), i) + coljfirstk - 1
    if searchk <= coljlastk && rowvals(A)[searchk] == i
        # Entry A[i,j] is stored. Drop and return.
        deleteat!(rowvals(A), searchk)
        deleteat!(nonzeros(A), searchk)
        @simd for m in (j+1):(size(A, 2) + 1)
            @inbounds getcolptr(A)[m] -= 1
        end
    end
    return _checkbuffers(A)
end
"""
    dropstored!(A::AbstractSparseMatrixCSC, I::AbstractVector{<:Integer}, J::AbstractVector{<:Integer})

For each `(i,j)` where `i in I` and `j in J`, drop entry `A[i,j]` from `A` if `A[i,j]` is
stored and otherwise do nothing. Derivative forms:

    dropstored!(A::AbstractSparseMatrixCSC, i::Integer, J::AbstractVector{<:Integer})
    dropstored!(A::AbstractSparseMatrixCSC, I::AbstractVector{<:Integer}, j::Integer)

# Examples
```jldoctest
julia> A = sparse(Diagonal([1, 2, 3, 4]))
4×4 SparseMatrixCSC{Int64, Int64} with 4 stored entries:
 1  ⋅  ⋅  ⋅
 ⋅  2  ⋅  ⋅
 ⋅  ⋅  3  ⋅
 ⋅  ⋅  ⋅  4

julia> SparseArrays.dropstored!(A, [1, 2], [1, 1])
4×4 SparseMatrixCSC{Int64, Int64} with 3 stored entries:
 ⋅  ⋅  ⋅  ⋅
 ⋅  2  ⋅  ⋅
 ⋅  ⋅  3  ⋅
 ⋅  ⋅  ⋅  4
```
"""
function dropstored!(A::AbstractSparseMatrixCSC,
        I::AbstractVector{<:Integer}, J::AbstractVector{<:Integer})
    require_one_based_indexing(A, I, J)
    m, n = size(A)
    nnzA = nnz(A)
    (nnzA == 0) && (return A)

    !issorted(I) && (I = sort(I))
    !issorted(J) && (J = sort(J))

    if (!isempty(I) && (I[1] < 1 || I[end] > m)) || (!isempty(J) && (J[1] < 1 || J[end] > n))
        throw(BoundsError(A, (I, J)))
    end

    if isempty(I) || isempty(J)
        return A
    end

    rowval = rowvalA = rowvals(A)
    nzval = nzvalA = nonzeros(A)
    rowidx = 1
    ndel = 0
    @inbounds for col in axes(A,2)
        rrange = nzrange(A, col)
        if ndel > 0
            getcolptr(A)[col] = getcolptr(A)[col] - ndel
        end

        if isempty(rrange) || !(col in J)
            nincl = length(rrange)
            if(ndel > 0) && !isempty(rrange)
                copyto!(rowvalA, rowidx, rowval, rrange[1], nincl)
                copyto!(nzvalA, rowidx, nzval, rrange[1], nincl)
            end
            rowidx += nincl
        else
            for ridx in rrange
                if rowval[ridx] in I
                    if ndel == 0
                        rowval = copy(rowvalA)
                        nzval = copy(nzvalA)
                    end
                    ndel += 1
                else
                    if ndel > 0
                        rowvalA[rowidx] = rowval[ridx]
                        nzvalA[rowidx] = nzval[ridx]
                    end
                    rowidx += 1
                end
            end
        end
    end

    if ndel > 0
        getcolptr(A)[n+1] = rowidx
        deleteat!(rowvalA, rowidx:nnzA)
        deleteat!(nzvalA, rowidx:nnzA)
    end
    return _checkbuffers(A)
end
dropstored!(A::AbstractSparseMatrixCSC, i::Integer, J::AbstractVector{<:Integer}) = dropstored!(A, [i], J)
dropstored!(A::AbstractSparseMatrixCSC, I::AbstractVector{<:Integer}, j::Integer) = dropstored!(A, I, [j])
dropstored!(A::AbstractSparseMatrixCSC, ::Colon, j::Union{Integer,AbstractVector}) = dropstored!(A, axes(A,1), j)
dropstored!(A::AbstractSparseMatrixCSC, i::Union{Integer,AbstractVector}, ::Colon) = dropstored!(A, i, axes(A,2))
dropstored!(A::AbstractSparseMatrixCSC, ::Colon, ::Colon) = dropstored!(A, axes(A,1), axes(A,2))
dropstored!(A::AbstractSparseMatrixCSC, ::Colon) = dropstored!(A, :, :)
# TODO: Several of the preceding methods are optimization candidates.
# TODO: Implement linear indexing methods for dropstored! ?
# TODO: Implement logical indexing methods for dropstored! ?

# Sparse concatenation

promote_idxtype(::AbstractSparseMatrixCSC{<:Any, Ti}) where {Ti} = Ti
promote_idxtype(::AbstractSparseMatrixCSC{<:Any, Ti}, X::AbstractSparseMatrixCSC...) where {Ti} =
    promote_type(Ti, promote_idxtype(X...))

function vcat(X::AbstractSparseMatrixCSC...)
    num = length(X)
    mX = Int[ size(x, 1) for x in X ]
    nX = Int[ size(x, 2) for x in X ]
    m = sum(mX)
    n = nX[1]

    for i = 2 : num
        if nX[i] != n
            throw(DimensionMismatch("All inputs to vcat should have the same number of columns"))
        end
    end

    Tv = promote_eltype(X...)
    Ti = promote_idxtype(X...)

    nnzX = Int[ nnz(x) for x in X ]
    nnz_res = sum(nnzX)
    colptr = Vector{Ti}(undef, n+1)
    rowval = Vector{Ti}(undef, nnz_res)
    nzval  = Vector{Tv}(undef, nnz_res)

    colptr[1] = 1
    for c = 1:n
        mX_sofar = 0
        ptr_res = colptr[c]
        for i = 1 : num
            colptrXi = getcolptr(X[i])
            col_length = colptrXi[c + 1] - colptrXi[c]
            ptr_Xi = colptrXi[c]

            ptr_res = stuffcol!(rowval, nzval, ptr_res, rowvals(X[i]), nonzeros(X[i]), ptr_Xi,
                                col_length, mX_sofar)
            mX_sofar += mX[i]
        end
        colptr[c + 1] = ptr_res
    end
    SparseMatrixCSC(m, n, colptr, rowval, nzval)
end

@inline function stuffcol!(rowval, nzval, ptr_res, rowvalXi, nzvalXi, ptr_Xi,
                           col_length, mX_sofar)
    for k=ptr_res:(ptr_res + col_length - 1)
        @inbounds rowval[k] = rowvalXi[ptr_Xi] + mX_sofar
        @inbounds nzval[k]  = nzvalXi[ptr_Xi]
        ptr_Xi += 1
    end
    return ptr_res + col_length
end

function hcat(X::AbstractSparseMatrixCSC...)
    num = length(X)
    mX = Int[ size(x, 1) for x in X ]
    nX = Int[ size(x, 2) for x in X ]
    m = mX[1]
    for i = 2 : num
        if mX[i] != m; throw(DimensionMismatch("")); end
    end
    n = sum(nX)

    Tv = promote_eltype(X...)
    Ti = promote_idxtype(X...)

    colptr = Vector{Ti}(undef, n+1)
    nnzX = Int[ nnz(x) for x in X ]
    nnz_res = sum(nnzX)
    rowval = Vector{Ti}(undef, nnz_res)
    nzval = Vector{Tv}(undef, nnz_res)

    nnz_sofar = 0
    nX_sofar = 0
    @inbounds for i = 1 : num
        XI = X[i]
        colptr[(1 : nX[i] + 1) .+ nX_sofar] = getcolptr(XI) .+ nnz_sofar
        if nnzX[i] == length(rowvals(XI))
            rowval[(1 : nnzX[i]) .+ nnz_sofar] = rowvals(XI)
            nzval[(1 : nnzX[i]) .+ nnz_sofar] = nonzeros(XI)
        else
            rowval[(1 : nnzX[i]) .+ nnz_sofar] = rowvals(XI)[1:nnzX[i]]
            nzval[(1 : nnzX[i]) .+ nnz_sofar] = nonzeros(XI)[1:nnzX[i]]
        end
        nnz_sofar += nnzX[i]
        nX_sofar += nX[i]
    end

    SparseMatrixCSC(m, n, colptr, rowval, nzval)
end


# Efficient repetition of sparse matrices

function Base.repeat(A::AbstractSparseMatrixCSC, m)
    nnz_new = nnz(A) * m
    colptr = similar(getcolptr(A), length(getcolptr(A)))
    rowval = similar(rowvals(A), nnz_new)
    nzval = similar(nonzeros(A), nnz_new)

    colptr[1] = 1
    for c = 1 : size(A, 2)
        ptr_res = colptr[c]
        ptr_source = getcolptr(A)[c]
        col_length = getcolptr(A)[c + 1] - ptr_source
        for index_repetition = 0 : (m - 1)
            row_offset = index_repetition * size(A, 1)
            ptr_res = stuffcol!(rowval, nzval, ptr_res, rowvals(A), nonzeros(A), ptr_source,
                                col_length, row_offset)
        end
        colptr[c + 1] = ptr_res
    end
    @assert colptr[end] == nnz_new + 1

    SparseMatrixCSC(size(A, 1) * m, size(A, 2), colptr, rowval, nzval)
end

function Base.repeat(A::AbstractSparseMatrixCSC, m, n)
    B = repeat(A, m)
    nnz_per_column = diff(getcolptr(B))
    colptr = cumsum(vcat(1, repeat(nnz_per_column, n)))
    rowval = repeat(rowvals(B), n)
    nzval = repeat(nonzeros(B), n)
    SparseMatrixCSC(size(B, 1), size(B, 2) * n, colptr, rowval, nzval)
end


"""
    blockdiag(A...)

Concatenate matrices block-diagonally. Currently only implemented for sparse matrices.

# Examples
```jldoctest
julia> blockdiag(sparse(2I, 3, 3), sparse(4I, 2, 2))
5×5 SparseMatrixCSC{Int64, Int64} with 5 stored entries:
 2  ⋅  ⋅  ⋅  ⋅
 ⋅  2  ⋅  ⋅  ⋅
 ⋅  ⋅  2  ⋅  ⋅
 ⋅  ⋅  ⋅  4  ⋅
 ⋅  ⋅  ⋅  ⋅  4
```
"""
blockdiag() = spzeros(promote_type(), Int, 0, 0)

function blockdiag(X::AbstractSparseMatrixCSC{Tv, Ti}...) where {Tv, Ti <: Integer}
    _blockdiag(Tv, Ti, X...)
end

function blockdiag(X::AbstractSparseMatrixCSC...)
    Tv = promote_type(map(x->eltype(nonzeros(x)), X)...)
    Ti = promote_type(map(x->eltype(rowvals(x)), X)...)
    _blockdiag(Tv, Ti, X...)
end

function _blockdiag(::Type{Tv}, ::Type{Ti}, X::AbstractSparseMatrixCSC...) where {Tv, Ti <: Integer}
    num = length(X)
    mX = Int[ size(x, 1) for x in X ]
    nX = Int[ size(x, 2) for x in X ]
    m = sum(mX)
    n = sum(nX)

    colptr = Vector{Ti}(undef, n+1)
    nnzX = Int[ nnz(x) for x in X ]
    nnz_res = sum(nnzX)
    rowval = Vector{Ti}(undef, nnz_res)
    nzval = Vector{Tv}(undef, nnz_res)

    nnz_sofar = 0
    nX_sofar = 0
    mX_sofar = 0
    for i = 1 : num
        colptr[(1 : nX[i] + 1) .+ nX_sofar] = getcolptr(X[i]) .+ nnz_sofar
        rowval[(1 : nnzX[i]) .+ nnz_sofar] = rowvals(X[i]) .+ mX_sofar
        nzval[(1 : nnzX[i]) .+ nnz_sofar] = nonzeros(X[i])
        nnz_sofar += nnzX[i]
        nX_sofar += nX[i]
        mX_sofar += mX[i]
    end
    colptr[n+1] = nnz_sofar + 1

    SparseMatrixCSC(m, n, colptr, rowval, nzval)
end

## Structure query functions
issymmetric(A::AbstractSparseMatrixCSC) = is_hermsym(A, transpose)

ishermitian(A::AbstractSparseMatrixCSC) = is_hermsym(A, adjoint)

function is_hermsym(A::AbstractSparseMatrixCSC, check::Function)
    m, n = size(A)
    if m != n; return false; end

    colptr = getcolptr(A)
    rowval = rowvals(A)
    nzval = nonzeros(A)
    tracker = copy(getcolptr(A))
    for col in axes(A,2)
        # `tracker` is updated such that, for symmetric matrices,
        # the loop below starts from an element at or below the
        # diagonal element of column `col`"
        for p = tracker[col]:colptr[col+1]-1
            val = nzval[p]
            row = rowval[p]

            # Ignore stored zeros
            if iszero(val)
                continue
            end

            # If the matrix was symmetric we should have updated
            # the tracker to start at the diagonal or below. Here
            # we are above the diagonal so the matrix can't be symmetric.
            if row < col
                return false
            end

            # Diagonal element
            if row == col
                if val != check(val)
                    return false
                end
            else
                # if nzrange(A, row) is empty, then A[:, row] is all zeros.
                # Specifically, A[col, row] is zero.
                # However, we know at this point that A[row, col] is not zero
                # This means that the matrix is not symmetric
                isempty(nzrange(A, row)) && return false

                offset = tracker[row]

                # If the matrix is unsymmetric, there might not exist
                # a rowval[offset]
                if offset > length(rowval)
                    return false
                end

                row2 = rowval[offset]

                # row2 can be less than col if the tracker didn't
                # get updated due to stored zeros in previous elements.
                # We therefore "catch up" here while making sure that
                # the elements are actually zero.
                while row2 < col
                    if _isnotzero(nzval[offset])
                        return false
                    end
                    offset += 1
                    row2 = rowval[offset]
                    tracker[row] += 1
                end

                # Non zero A[i,j] exists but A[j,i] does not exist
                if row2 > col
                    return false
                end

                # A[i,j] and A[j,i] exists
                if row2 == col
                    if val != check(nzval[offset])
                        return false
                    end
                    tracker[row] += 1
                end
            end
        end
    end
    return true
end

function istriu(A::AbstractSparseMatrixCSC, k::Integer=0)
    m, n = size(A)
    colptr = getcolptr(A)
    rowval = rowvals(A)
    nzval  = nonzeros(A)

    for col = 1:min(n, m-1)
        l1 = colptr[col+1]-1
        for i = 0 : (l1 - colptr[col])
            if rowval[l1-i] <= col - k
                # rows preceeding the index would also lie above the band
                break
            end
            if _isnotzero(nzval[l1-i])
                return false
            end
        end
    end
    return true
end

function istril(A::AbstractSparseMatrixCSC, k::Integer=0)
    m, n = size(A)
    colptr = getcolptr(A)
    rowval = rowvals(A)
    nzval  = nonzeros(A)

    for col = 2:n
        for i = colptr[col] : (colptr[col+1]-1)
            if rowval[i] >= col - k
                # subsequent rows would also lie below the band
                break
            end
            if _isnotzero(nzval[i])
                return false
            end
        end
    end
    return true
end

_nnz(v::AbstractSparseVector) = nnz(v)
_nnz(v::AbstractVector) = length(v)

function _indices(v::AbstractSparseVector, row, col)
    ix = nonzeroinds(v)
    return (row .+ ix, col .+ ix)
end
function _indices(v::AbstractVector, row, col)
    veclen = length(v)
    return (row+1:row+veclen, col+1:col+veclen)
end

_nzvals(v::AbstractSparseVector) = nonzeros(v)
_nzvals(v::AbstractVector) = v

function spdiagm_internal(kv::Pair{<:Integer,<:AbstractVector}...)
    ncoeffs = 0
    for p in kv
        ncoeffs += _nnz(p.second)
    end
    I = Vector{Int}(undef, ncoeffs)
    J = Vector{Int}(undef, ncoeffs)
    V = Vector{promote_type(map(x -> eltype(x.second), kv)...)}(undef, ncoeffs)
    i = 0
    m = 0
    n = 0
    for p in kv
        k = p.first
        v = p.second
        if k < 0
            row = -k
            col = 0
        elseif k > 0
            row = 0
            col = k
        else
            row = 0
            col = 0
        end
        numel = _nnz(v)
        r = 1+i:numel+i
        I[r], J[r] = _indices(v, row, col)
        copyto!(view(V, r), _nzvals(v))
        veclen = length(v)
        m = max(m, row + veclen)
        n = max(n, col + veclen)
        i += numel
    end
    return I, J, V, m, n
end

"""
    spdiagm(kv::Pair{<:Integer,<:AbstractVector}...)
    spdiagm(m::Integer, n::Integer, kv::Pair{<:Integer,<:AbstractVector}...)

Construct a sparse diagonal matrix from `Pair`s of vectors and diagonals.
Each vector `kv.second` will be placed on the `kv.first` diagonal.  By
default, the matrix is square and its size is inferred
from `kv`, but a non-square size `m`×`n` (padded with zeros as needed)
can be specified by passing `m,n` as the first arguments.

# Examples
```jldoctest
julia> spdiagm(-1 => [1,2,3,4], 1 => [4,3,2,1])
5×5 SparseMatrixCSC{Int64, Int64} with 8 stored entries:
 ⋅  4  ⋅  ⋅  ⋅
 1  ⋅  3  ⋅  ⋅
 ⋅  2  ⋅  2  ⋅
 ⋅  ⋅  3  ⋅  1
 ⋅  ⋅  ⋅  4  ⋅
```
"""
spdiagm(kv::Pair{<:Integer,<:AbstractVector}...) = _spdiagm(nothing, kv...)
spdiagm(m::Integer, n::Integer, kv::Pair{<:Integer,<:AbstractVector}...) = _spdiagm((Int(m),Int(n)), kv...)

"""
    spdiagm(v::AbstractVector)
    spdiagm(m::Integer, n::Integer, v::AbstractVector)

Construct a sparse matrix with elements of the vector as diagonal elements.
By default (no given `m` and `n`), the matrix is square and its size is given
by `length(v)`, but a non-square size `m`×`n` can be specified by passing `m`
and `n` as the first arguments.

!!! compat "Julia 1.6"
    These functions require at least Julia 1.6.

# Examples
```jldoctest
julia> spdiagm([1,2,3])
3×3 SparseMatrixCSC{Int64, Int64} with 3 stored entries:
 1  ⋅  ⋅
 ⋅  2  ⋅
 ⋅  ⋅  3

julia> spdiagm(sparse([1,0,3]))
3×3 SparseMatrixCSC{Int64, Int64} with 2 stored entries:
 1  ⋅  ⋅
 ⋅  ⋅  ⋅
 ⋅  ⋅  3
```
"""
spdiagm(v::AbstractVector) = _spdiagm(nothing, 0 => v)
spdiagm(m::Integer, n::Integer, v::AbstractVector) = _spdiagm((Int(m), Int(n)), 0 => v)

function _spdiagm(size, kv::Pair{<:Integer,<:AbstractVector}...)
    I, J, V, mmax, nmax = spdiagm_internal(kv...)
    mnmax = max(mmax, nmax)
    m, n = something(size, (mnmax,mnmax))
    (m ≥ mmax && n ≥ nmax) || throw(DimensionMismatch("invalid size=$size"))
    return sparse(I, J, V, m, n)
end

## expand a colptr or rowptr into a dense index vector
function expandptr(V::Vector{<:Integer})
    if V[1] != 1 throw(ArgumentError("first index must be one")) end
    res = similar(V, (Int64(V[end]-1),))
    for i in 1:(length(V)-1), j in V[i]:(V[i+1] - 1); res[j] = i end
    res
end


function diag(A::AbstractSparseMatrixCSC{Tv,Ti}, d::Integer=0) where {Tv,Ti}
    m, n = size(A)
    k = Int(d)
    l = k < 0 ? min(m+k,n) : min(n-k,m)
    r, c = k <= 0 ? (-k, 0) : (0, k) # start row/col -1
    ind = Vector{Ti}()
    val = Vector{Tv}()
    for i in 1:l
        r += 1; c += 1
        r1 = Int(getcolptr(A)[c])
        r2 = Int(getcolptr(A)[c+1]-1)
        r1 > r2 && continue
        r1 += searchsortedfirst(view(rowvals(A), r1:r2), r) - 1
        ((r1 > r2) || (rowvals(A)[r1] != r)) && continue
        push!(ind, i)
        push!(val, nonzeros(A)[r1])
    end
    return SparseVector{Tv,Ti}(l, ind, val)
end

function tr(A::AbstractSparseMatrixCSC{Tv}) where Tv
    n = checksquare(A)
    s = zero(Tv)
    for i in 1:n
        s += A[i,i]
    end
    return s
end

## rotations

function rot180(A::AbstractSparseMatrixCSC)
    I,J,V = findnz(A)
    m,n = size(A)
    for i=1:length(I)
        I[i] = m - I[i] + 1
        J[i] = n - J[i] + 1
    end
    return sparse(I,J,V,m,n)
end

function rotr90(A::AbstractSparseMatrixCSC)
    I,J,V = findnz(A)
    m,n = size(A)
    #old col inds are new row inds
    for i=1:length(I)
        I[i] = m - I[i] + 1
    end
    return sparse(J, I, V, n, m)
end

function rotl90(A::AbstractSparseMatrixCSC)
    I,J,V = findnz(A)
    m,n = size(A)
    #old row inds are new col inds
    for i=1:length(J)
        J[i] = n - J[i] + 1
    end
    return sparse(J, I, V, n, m)
end

## Uniform matrix arithmetic

(+)(A::AbstractSparseMatrixCSC{Tv, Ti}, J::UniformScaling{T}) where {T<:Number, Tv, Ti} =
    A + sparse(T, Ti, J, size(A)...)
(+)(J::UniformScaling{T}, A::AbstractSparseMatrixCSC{Tv, Ti}) where {T<:Number, Tv, Ti} =
    sparse(T, Ti, J, size(A)...) + A
(-)(A::AbstractSparseMatrixCSC{Tv, Ti}, J::UniformScaling{T}) where {T<:Number, Tv, Ti} =
    A - sparse(T, Ti, J, size(A)...)
(-)(J::UniformScaling{T}, A::AbstractSparseMatrixCSC{Tv, Ti}) where {T<:Number, Tv, Ti} =
    sparse(T, Ti, J, size(A)...) - A



## circular shift

function circshift!(O::AbstractSparseMatrixCSC, X::AbstractSparseMatrixCSC, (r,c)::Base.DimsInteger{2})
    nnz = length(nonzeros(X))

    iszero(nnz) && return copy!(O, X)

    ##### column shift
    c = mod(c, size(X, 2))
    if iszero(c)
        copy!(O, X)
    else
        ##### readjust output
        resize!(getcolptr(O), size(X, 2) + 1)
        resize!(rowvals(O), nnz)
        resize!(nonzeros(O), nnz)
        getcolptr(O)[size(X, 2) + 1] = nnz + 1

        # exchange left and right blocks
        nleft = getcolptr(X)[size(X, 2) - c + 1] - 1
        nright = nnz - nleft
        @inbounds for i=c+1:size(X, 2)
            getcolptr(O)[i] = getcolptr(X)[i-c] + nright
        end
        @inbounds for i=1:c
            getcolptr(O)[i] = getcolptr(X)[size(X, 2) - c + i] - nleft
        end
        # rotate rowval and nzval by the right number of elements
        circshift!(rowvals(O), rowvals(X), (nright,))
        circshift!(nonzeros(O), nonzeros(X), (nright,))
    end
    ##### row shift
    r = mod(r, size(X, 1))
    iszero(r) && return O
    @inbounds for i in axes(O, 2)
        subvector_shifter!(rowvals(O), nonzeros(O), getcolptr(O)[i], getcolptr(O)[i+1]-1, size(O, 1), r)
    end
    return _checkbuffers(O)
end

circshift!(O::AbstractSparseMatrixCSC, X::AbstractSparseMatrixCSC, (r,)::Base.DimsInteger{1}) = circshift!(O, X, (r,0))
circshift!(O::AbstractSparseMatrixCSC, X::AbstractSparseMatrixCSC, r::Real) = circshift!(O, X, (Integer(r),0))

## swaprows! / swapcols!
macro swap(a, b)
    esc(:(($a, $b) = ($b, $a)))
end

function Base.swapcols!(A::AbstractSparseMatrixCSC, i, j)
    i == j && return

    # For simplicity, let i denote the smaller of the two columns
    j < i && @swap(i, j)

    colptr = getcolptr(A)
    irow = colptr[i]:(colptr[i+1]-1)
    jrow = colptr[j]:(colptr[j+1]-1)

    function rangeexchange!(arr, irow, jrow)
        if length(irow) == length(jrow)
            for (a, b) in zip(irow, jrow)
                @inbounds @swap(arr[a], arr[b])
            end
            return
        end
        # This is similar to the triple-reverse tricks for
        # circshift!, except that we have three ranges here,
        # so it ends up being 4 reverse calls (but still
        # 2 overall reversals for the memory range). Like
        # circshift!, there's also a cycle chasing algorithm
        # with optimal memory complexity, but the performance
        # tradeoffs against this implementation are non-trivial,
        # so let's just do this simple thing for now.
        # See https://github.com/JuliaLang/julia/pull/42676 for
        # discussion of circshift!-like algorithms.
        reverse!(@view arr[irow])
        reverse!(@view arr[jrow])
        reverse!(@view arr[(last(irow)+1):(first(jrow)-1)])
        reverse!(@view arr[first(irow):last(jrow)])
    end
    rangeexchange!(rowvals(A), irow, jrow)
    rangeexchange!(nonzeros(A), irow, jrow)

    if length(irow) != length(jrow)
        @inbounds colptr[i+1:j] .+= length(jrow) - length(irow)
    end
    return nothing
end

function Base.swaprows!(A::AbstractSparseMatrixCSC, i, j)
    # For simplicity, let i denote the smaller of the two rows
    j < i && @swap(i, j)

    rows = rowvals(A)
    vals = nonzeros(A)
    for col in axes(A,2)
        rr = nzrange(A, col)
        iidx = searchsortedfirst(@view(rows[rr]), i)
        has_i = iidx <= length(rr) && rows[rr[iidx]] == i

        jrange = has_i ? (iidx:last(rr)) : rr
        jidx = searchsortedlast(@view(rows[jrange]), j)
        has_j = jidx != 0 && rows[jrange[jidx]] == j

        if !has_j && !has_i
            # Has neither row - nothing to do
            continue
        elseif has_i && has_j
            # This column had both i and j rows - swap them
            @swap(vals[rr[iidx]], vals[jrange[jidx]])
        elseif has_i
            # Update the rowval and then rotate both nonzeros
            # and the remaining rowvals into the correct place
            rows[rr[iidx]] = j
            jidx == 0 && continue
            rotate_range = rr[iidx]:jrange[jidx]
            circshift!(@view(vals[rotate_range]), 1)
            circshift!(@view(rows[rotate_range]), 1)
        else
            # Same as i, but in the opposite direction
            @assert has_j
            rows[jrange[jidx]] = i
            iidx > length(rr) && continue
            rotate_range = rr[iidx]:jrange[jidx]
            circshift!(@view(vals[rotate_range]), -1)
            circshift!(@view(rows[rotate_range]), -1)
        end
    end
    return nothing
end

reverse(A::AbstractSparseMatrixCSC; dims=:) = _reverse(A, dims)
function _reverse(A::AbstractSparseMatrixCSC, ::Colon)
    rowinds, colinds, nzval = findnz(A)
    rowinds .= (size(A,1) + 1) .- rowinds
    colinds .= (size(A,2) + 1) .- colinds
    sparse!(rowinds, colinds, nzval, size(A)...)
end
function _reverse(A::AbstractSparseMatrixCSC, dims::Integer)
    dims ∈ (1,2) || throw(ArgumentError("invalid dimension $dims in reverse"))
    rowinds, colinds, nzval = findnz(A)
    if dims == 1
        rowinds .= (size(A,1) + 1) .- rowinds
    else # dims == 2
        colinds .= (size(A,2) + 1) .- colinds
    end
    sparse!(rowinds, colinds, nzval, size(A)...)
end
function _reverse(A::AbstractSparseMatrixCSC, dims::Tuple{Integer,Integer})
    dims == (1,2) || dims == (2,1) || throw(ArgumentError("invalid dimension $dims in reverse"))
    _reverse(A, :)
end

reverse(S::SparseMatrixCSC; dims...) = reverse!(copy(S); dims...)
reverse!(S::SparseMatrixCSC; dims=:) = _reverse!(S, dims)
function _reverse!(S::SparseMatrixCSC, ::Colon)
    rowinds, nzval = rowvals(S), nonzeros(S)
    colptr = getcolptr(S)
    rowinds .= (size(S,1) + 1) .- rowinds
    reverse!(rowinds)
    colptr .= (nnz(S) + 2) .- colptr
    reverse!(colptr)
    reverse!(nzval)
    return S
end
function _reverse!(S::SparseMatrixCSC, dims::Integer)
    dims ∈ (1,2) || throw(ArgumentError("invalid dimension $dims in reverse"))
    rowinds, nzval = rowvals(S), nonzeros(S)
    colptr = getcolptr(S)
    nzrs = nzrange.(Ref(S), axes(S,2))
    if dims == 1
        for col in axes(S,2)
            nzr = nzrs[col]
            reverse!(@views nzval[nzr])
            rowinds_col = @view rowinds[nzr]
            rowinds_col .= (size(S,1) + 1) .- rowinds_col
            reverse!(rowinds_col)
        end
    else # dims == 2
        colptr .= (nnz(S) + 2) .- colptr
        reverse!(colptr)
        for col in axes(S,2)
            nzr = nzrs[col]
            reverse!(@views nzval[nzr])
            reverse!(@views rowinds[nzr])
        end
        reverse!(nzval)
        reverse!(rowinds)
    end
    return S
end
function _reverse!(A::SparseMatrixCSC, dims::Tuple{Integer,Integer})
    dims == (1,2) || dims == (2,1) || throw(ArgumentError("invalid dimension $dims in reverse"))
    _reverse!(A, :)
end

function copytrito!(M::AbstractMatrix, S::AbstractSparseMatrixCSC, uplo::Char)
    Base.require_one_based_indexing(M, S)
    if !(uplo == 'U' || uplo == 'L')
        throw(ArgumentError(lazy"uplo argument must be 'U' (upper) or 'L' (lower), got '$uplo'"))
    end
    m,n = size(S)
    m1,n1 = size(M)
    (m1 < m || n1 < n) && throw(DimensionMismatch("dest of size ($m1,$n1) should have at least the same number of rows and columns than src of size ($m,$n)"))

    rv = rowvals(S)
    nz = nonzeros(S)
    for col in axes(S,2)
        trirange = uplo == 'U' ? (1:min(col, size(S,1))) : (col:size(S,1))
        fill!(view(M, trirange, col), zero(eltype(S)))
        for i in nzrange(S, col)
            row = rv[i]
            (uplo == 'U' && row <= col) || (uplo == 'L' && row >= col) || continue
            M[row, col] = nz[i]
        end
    end
    return M
end
