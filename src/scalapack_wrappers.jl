
#--- input
#   nprow : [global] : num of rows in the process grid
#   npcol : [global] : num of cols in the process grid
#--- output
#   ctxt  : [global] : BLACS context
function sl_init(nprow::ScaInt, npcol::ScaInt)
    ctxt = zeros(ScaInt,1)
    ccall((:sl_init_, libscalapack), Nothing,
        (Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}),
        ctxt, Ref(nprow), Ref(npcol))
    return ctxt[1]
end

#--- input
#   n        : [global] : num of rows/cols
#   nb       : [global] : num of rows/cols in its block
#   iproc    : [global] : num of process rows and cols in the current process id
#   isrcproc : [global] : head grid address of its process grid
#   nprocs   : [global] : num of process grid
#--- output
#              [global] : num of process rows and cols in the current process id
function numroc(n::ScaInt, nb::ScaInt, iproc::ScaInt, isrcproc::ScaInt, nprocs::ScaInt)
    return ccall((:numroc_, libscalapack), ScaInt,
                (Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}),
                Ref(n), Ref(nb), Ref(iproc), Ref(isrcproc), Ref(nprocs))
end

#--- input
#   m/n         : [global] : num of rows/cols
#   mb/nb       : [global] : num of rows/cols in its block
#   irsrc/icsrc : [global] : head of row/col grid address of its process grid
#   ictxt       : [global] : BLACS context
#   lld         : [global] : local leading dimension
#--- output
#   desc        : [global] : array descriptor of the local matrix
function descinit(m::ScaInt, n::ScaInt, mb::ScaInt, nb::ScaInt, irsrc::ScaInt, icsrc::ScaInt, ictxt::ScaInt, lld::ScaInt)
    desc = zeros(ScaInt, 9)
    info = zeros(ScaInt, 1)
    ccall((:descinit_, libscalapack), Nothing,
            (Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
            Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
            Ptr{ScaInt}, Ptr{ScaInt}),
            desc, Ref(m), Ref(n), Ref(mb),
            Ref(nb), Ref(irsrc), Ref(icsrc), Ref(ictxt),
            Ref(lld), info)
    if info[1] < 0
        error("input argument $(info[1]) has illegal value")
    end
    return desc
end

#--- input 
#   A     : [global] : ( will be updated ! ) input matrix
#   ia/ja : [global] : first row/col index in the global matrix A
#   desca : [global] : descriptor of the local matrix A
#   α     : [global] : scalar value to substitute into the A
#--- output
#                      nothing
for (fname, elty) in ((:pselset_, :Float32),
                      (:pdelset_, :Float64),
                      (:pcelset_, :ComplexF32),
                      (:pzelset_, :ComplexF64))
    @eval begin
        function pXelset!(A::Matrix{$elty}, ia::ScaInt, ja::ScaInt, desca::Vector{ScaInt}, α::$elty)
            ccall(($(string(fname)), libscalapack), Nothing,
                (Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{$elty}),
                A, Ref(ia), Ref(ja), desca, Ref(α))
        end
    end
end

#--- input
#   scope : [global] : BLACS scope in which alpha is returned
#   top   : [global] : topology to be used if broadcast is needed
#   A     : [local]  : local matrix
#   ia/ja : [global] : first row/col index in the global matrix A
#   desca : [global] : descriptor of the local matrix A
#--- output
#   α     : [local]  : scalar value which will be returned from the A
for (fname, elty) in ((:pselget_, :Float32),
                      (:pdelget_, :Float64),
                      (:pcelget_, :ComplexF32),
                      (:pzelget_, :ComplexF64))
    @eval begin
        function pXelget(scope::Char, top::Char, A::Matrix{$elty}, ia::ScaInt, ja::ScaInt, desca::Vector{ScaInt})
            α = zeros($elty,1)
            ccall(($(string(fname)), libscalapack), Nothing,
                  (Ptr{Char}, Ptr{Char}, Ptr{$elty}, Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}),
                  f_pchar(scope), f_pchar(top), α, A, Ref(ia), Ref(ja), desca)
            return α[1]
        end
    end
end

#
for (fname, elty) in ((:pslacpy_, :Float32),
                      (:pdlacpy_, :Float64),
                      (:pclacpy_, :ComplexF32),
                      (:pzlacpy_, :ComplexF64))
    @eval begin
        function pXlacpy!(uplo::Char, m::ScaInt, n::ScaInt,
                          A::Matrix{$elty}, ia::ScaInt, ja::ScaInt, desca::Vector{ScaInt},
                          B::Matrix{$elty}, ib::ScaInt, jb::ScaInt, descb::Vector{ScaInt})
            ccall(($(string(fname)), libscalapack), Nothing,
                    (Ptr{Char}, Ptr{ScaInt}, Ptr{ScaInt},
                    Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                    Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}),
                    f_pchar(uplo), Ref(m), Ref(n),
                    A, Ref(ia), Ref(ja), desca,
                    B, Ref(ib), Ref(jb), descb)
        end
    end
end

# input : num of rows/cols
#         local matrix A
#         head grid address of its process grid
#         array descriptor
#         ( will be updated ! ) matrix B
#         BLACS context
# output: Nothing
for (fname, elty) in ((:psgemr2d_, :Float32),
                      (:pdgemr2d_, :Float64),
                      (:pcgemr2d_, :ComplexF32),
                      (:pzgemr2d_, :ComplexF64))
    @eval begin
        function pXgemr2d!(m::ScaInt, n::ScaInt,
                           A::Matrix{$elty}, ia::ScaInt, ja::ScaInt, desca::Vector{ScaInt},
                           B::Matrix{$elty}, ib::ScaInt, jb::ScaInt, descb::Vector{ScaInt},
                           ictxt::ScaInt)
            ccall(($(string(fname)), libscalapack), Nothing,
                 (Ptr{ScaInt}, Ptr{ScaInt}, Ptr{$elty}, Ptr{ScaInt},
                  Ptr{ScaInt}, Ptr{ScaInt}, Ptr{$elty}, Ptr{ScaInt},
                  Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}),
                  Ref(m), Ref(n),
                  A, Ref(ia), Ref(ja), desca,
                  B, Ref(ib), Ref(jb), descb,
                  Ref(ictxt))
        end
    end
end

# input : BLACS scope to operate; op(X) = X or X' or X*'
#         grid indices of the inputted global matrices
#         coefficients
#         local matrices, grid indices of the local matrices
#         array descriptors for the distributed matrices
# output: nothing
# === detail ===
# op(X) = X or X' or X*'
# sub(A) = A[ia:ia+m-1,ja:ja+k-1]
# sub(B) = B[ib:ib+k-1,jb:jb+n-1]
# sub(C) = C[ic:ic+m-1,jc:jc+n-1]
#        = α*op(sub(A))*op(sub(B))+β*sub(C)
# op(sub(A)) denotes A[ia:ia+m-1,ja:ja+k-1]   if transa = 'n',
#                    A[ia:ia+k-1,ja:ja+m-1]'  if transa = 't',
#                    A[ia:ia+k-1,ja:ja+m-1]*' if transa = 'c',
# op(sub(B)) denotes B[ib:ib+k-1,jb:jb+n-1]   if transb = 'n',
#                    B[ib:ib+n-1,jb:jb+k-1]'  if transb = 't',
#                    B[ib:ib+n-1,jb:jb+k-1]*' if transb = 'c',
for (fname, elty) in ((:psgemm_, :Float32),
                      (:pdgemm_, :Float64),
                      (:pcgemm_, :ComplexF32),
                      (:pzgemm_, :ComplexF64))
    @eval begin
        function pXgemm!(transa::Char, transb::Char,
                         m::ScaInt, n::ScaInt, k::ScaInt,
                         α::$elty,
                         A::Matrix{$elty}, ia::ScaInt, ja::ScaInt, desca::Vector{ScaInt},
                         B::Matrix{$elty}, ib::ScaInt, jb::ScaInt, descb::Vector{ScaInt},
                         β::$elty,
                         C::Matrix{$elty}, ic::ScaInt, jc::ScaInt, descc::Vector{ScaInt})

            ccall(($(string(fname)), libscalapack), Nothing,
                (Ptr{Char}, Ptr{Char},
                 Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                 Ptr{$elty},
                 Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                 Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                 Ptr{$elty},
                 Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}),
                 f_pchar(transa), f_pchar(transb),
                 Ref(m), Ref(n), Ref(k),
                 Ref(α),
                 A, Ref(ia), Ref(ja), desca, 
                 B, Ref(ib), Ref(jb), descb,
                 Ref(β),
                 C, Ref(ic), Ref(jc), descc)
        end
    end
end

# void 	pcgemv_ (F_CHAR_T TRANS, 
#                  Int *M, Int *N, 
#                  float *ALPHA, float *A, Int *IA, Int *JA, Int *DESCA, 
#                  float *X, Int *IX, Int *JX, Int *DESCX, Int *INCX, 
#                  float *BETA, 
#                  float *Y, Int *IY, Int *JY, Int *DESCY, Int *INCY)

for (fname, elty) in ((:psgemv_, :Float32),
                      (:pdgemv_, :Float64),
                      (:pcgemv_, :ComplexF32),
                      (:pzgemv_, :ComplexF64))
    @eval begin
        function pXgemv!(trans::Char,
                         m::ScaInt, n::ScaInt,
                         α::$elty,
                         A::Matrix{$elty}, ia::ScaInt, ja::ScaInt, desca::Vector{ScaInt},
                         X::Vector{$elty}, ix::ScaInt, jx::ScaInt, descx::Vector{ScaInt}, incx::ScaInt,
                         β::$elty,
                         Y::Vector{$elty}, iy::ScaInt, jy::ScaInt, descy::Vector{ScaInt}, incy::ScaInt)

            ccall(($(string(fname)), libscalapack), Nothing,
                (Ptr{Char},
                 Ptr{ScaInt}, Ptr{ScaInt},
                 Ptr{$elty},
                 Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                 Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                 Ptr{$elty},
                 Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}), 
                 f_pchar(trans),
                 Ref(m), Ref(n),
                 Ref(α),
                 A, Ref(ia), Ref(ja), desca, 
                 X, Ref(ix), Ref(jx), descx, Ref(incx),
                 Ref(β),
                 Y, Ref(iy), Ref(jy), descy, Ref(incy))
        end
    end
end

# SUBROUTINE PvGER( M, N, ALPHA, X, IX, JX, DESCX, INCX, Y, IY, JY, DESCY, INCY, A, IA, JA, DESCA )
for (fname, elty) in ((:psger_, :Float32),
                      (:pdger_, :Float64),
                      (:pcger_, :ComplexF32),
                      (:pzger_, :ComplexF64))
    @eval begin
        function pXger!( m::ScaInt, n::ScaInt,
                         α::$elty,
                         X::Vector{$elty}, ix::ScaInt, jx::ScaInt, descx::Vector{ScaInt}, incx::ScaInt,
                         Y::Vector{$elty}, iy::ScaInt, jy::ScaInt, descy::Vector{ScaInt}, incy::ScaInt,
                         A::Matrix{$elty}, ia::ScaInt, ja::ScaInt, desca::Vector{ScaInt},)
            ccall(($(string(fname)), libscalapack), Nothing,
                (Ptr{ScaInt}, Ptr{ScaInt},
                 Ptr{$elty},
                 Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                 Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                 Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}), 
                 Ref(m), Ref(n),
                 Ref(α),
                 X, Ref(ix), Ref(jx), descx, Ref(incx),
                 Y, Ref(iy), Ref(jy), descy, Ref(incy),
                 A, Ref(ia), Ref(ja), desca)
        end
    end
end




#
for (fname, elty) in ((:pslaset_, :Float32),
                      (:pdlaset_, :Float64),
                      (:pclaset_, :ComplexF32),
                      (:pzlaset_, :ComplexF64))
    @eval begin
        function pXlaset!(uplo::Char, m::ScaInt, n::ScaInt,
                          α::$elty, β::$elty,
                          A::Matrix{$elty}, ia::ScaInt, ja::ScaInt, desca::Vector{ScaInt})
            ccall(($(string(fname)), libscalapack), Nothing,
                    (Ptr{Char}, Ptr{ScaInt}, Ptr{ScaInt},
                    Ptr{$elty}, Ptr{$elty},
                    Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}),
                    f_pchar(uplo), Ref(m), Ref(n),
                    Ref(α), Ref(β),
                    A, Ref(ia), Ref(ja), desca)
        end
    end
end

#
for (fname, elty, elty_s) in ((:psgebal_, :Float32, :Float32),
                              (:pdgebal_, :Float64, :Float64))
    @eval begin
        function pXgebal!(job::Char, n::ScaInt,
                          A::Matrix{$elty}, desca::Vector{ScaInt}, ilo::ScaInt, ihi::ScaInt,
                          scale::Vector{$elty_s})

            # inner variable
            info = zeros(ScaInt,1)
            ccall(($(string(fname)), libscalapack), Nothing,
                    (Ptr{Char}, Ptr{ScaInt},
                    Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                    Ptr{$elty_s}, Ptr{ScaInt}),
                    f_pchar(job), Ref(n),
                    A, desca, Ref(ilo), Ref(ihi),
                    scale, info)

            if info[1] < 0
                error("input argument $(info[1]) has illegal value")
            end

        end
    end
end

# ! assuming ! the A is a square matrix of n x n
# input : order of the local matrix A
#         lower/heigher range of the rows/cols in the global A
#         ( will be updated ! ) local matrix A
#         first row/col address of A
#         array descriptor for A
#         ( will be updated ! ) see 'the "τ" meaning'
#         ( will be updated ! ) see 'the "work" meaning'
#         see 'the "lwork" meaning'
# output: nothing
# === detail ===
# the "τ" meaning:
#     dim(τ) = numroc(ja+n-2,numblocks,mycol,csrc_a,npcolcols)
#     τ[ja+ilo-1:ja+ihi-2] = the scalar factors of the elementary reflectors
#     τ[ja:ja+ilo-2] = τ[ja+ihi-1:ja+n-2] = 0
# the "work" meaning:
#     dim(work) = lwork
#     if lwork == 0, work is ignored.
#     else,
#         if lwork != -1, its size is (at least) of length lwork.
#         else, its size is ( at least ) of length 1.
# the "lwork" meaning:
#     if lwork = -1, lwork is global
#     if lwork >= 0, lwork is local that value must be at least
#       lwork >= numblocks^2 + numblocks*max(ihip+1,ihlp+inlq)
#       where:
#           iroffa = (ia-1) % numblocks
#           icoffa = (ja-1) % numblocks
#           ioff = (ia+ilo-2) % numblocks
#           iarow = indxg2p(ia,numblocks,myrow,rsrc_a,npcolrows)
#                 = (rsrc_a+(ia-1)/numblocks) % npcolrows
#           ihip = numroc(ihi+iroffa,numblocks,myrow,iarow,npcolrows)
#           ilrow = indxg2p(ia+ilo-1,numblocks,myrow,rsrc_a,npcolrows)
#                 = (rsrc_a+(ia+ilo-2)/numblocks) % npcolrows
#           ihlp = numroc(ihi-ilo+ioff+1,numblocks,myrow,ilrow,npcolrows)
#           ilcol = indxg2p(ja+ilo-1,numblocks,mycol,csrc_a,npcolocls)
#                 = (csrc_a+(ja+ilo-2)/numblocks) % npcolcols
#           inlq = numroc(n-ilo+ioff+1,numblocks,mycol,ilcol,npcolcols)
for (fname, elty) in ((:psgehrd_, :Float32),
                      (:pdgehrd_, :Float64),
                      (:pcgehrd_, :ComplexF32),
                      (:pzgehrd_, :ComplexF64))
    @eval begin
        function pXgehrd!(n::ScaInt, ilo::ScaInt, ihi::ScaInt,
                          A::Matrix{$elty}, ia::ScaInt, ja::ScaInt, desca::Vector{ScaInt},
                          τ::Vector{$elty})

            # inner variables
            info = zeros(ScaInt,1)
            work = zeros($elty,1); lwork = -1;
            # j = 1 for perform a workspace query
            # j = 2 for perform ccall
            for j = 1:2
                ccall(($(string(fname)), libscalapack), Nothing,
                        (Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                        Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                        Ptr{$elty}, Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}),
                        Ref(n), Ref(ilo), Ref(ihi),
                        A, Ref(ia), Ref(ja), desca, 
                        τ, work, Ref(lwork), info)
                # allocate vector for j = 2
                if j == 1
                    lwork = convert(ScaInt, work[1])
                    work = zeros($elty, lwork)
                end
            end

            if info[1] < 0
                error("input argument $(info[1]) has illegal value")
            end

        end
    end
end

#
for (fname, elty) in ((:psormhr_, :Float32),
                      (:pdormhr_, :Float64),
                      (:pcunmhr_, :ComplexF32),
                      (:pzunmhr_, :ComplexF64))
    @eval begin
        function pXYYmhr!(side::Char, trans::Char,
                          m::ScaInt, n::ScaInt, ilo::ScaInt, ihi::ScaInt,
                          A::Matrix{$elty}, ia::ScaInt, ja::ScaInt, desca::Vector{ScaInt},
                          τ::Vector{$elty},
                          C::Matrix{$elty}, ic::ScaInt, jc::ScaInt, descc::Vector{ScaInt})

            # inner variables
            info = zeros(ScaInt,1)
            work = zeros($elty,1); lwork = -1;
            # j = 1 for perform a workspace query
            # j = 2 for perform ccall
            for j = 1:2
                ccall(($(string(fname)), libscalapack), Nothing,
                    (Ptr{Char}, Ptr{Char},
                    Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                    Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                    Ptr{$elty},
                    Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                    Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}),
                    f_pchar(side), f_pchar(trans),
                    Ref(m), Ref(n), Ref(ilo), Ref(ihi),
                    A, Ref(ia), Ref(ja), desca,
                    τ,
                    C, Ref(ic), Ref(jc), descc,
                    work, Ref(lwork), info)
                # allocate vector for j = 2
                if j == 1
                    lwork = convert(ScaInt, work[1])
                    work = zeros($elty, lwork)
                end
            end

            if info[1] < 0
                error("input argument $(info[1]) has illegal value")
            end

        end
    end
end

# ! assuming ! the A is an upper Hessenberg matrix of n x n
# input : booleans that requirement return form
#         order of the global Hessenberg matrix A
#         lower/heigher range of the rows/cols in the global A
#         ( will be updated ! ) global Hessenberg matrix A
#         array descriptor for A
#         index of the rows of Z that specified; Z[iloz:ihiz]
#         real/imag parts of the computed eigenvalues[ilo:ihi]
#         ( will be updated ! ) the Schur vector matrix Z; update part is [iloz:ihiz, ilo:ihi]
#         array descriptor for Z
#         ( will be updated ! ) see 'the "work" meaning'
#         see 'the "lwork" meaning'
#         temporary integer arrays and that order
# output: nothing
# === detail ===
# the "wantt" requires:
#   true ; the full Schur form
#   false; only eigenvalues
# the "wantz" requires:
#   true ; the matrix of Schur vectors Z
#   false; no Z
# the "work" meaning:
#     dim(work) = lwork
# the "lwork" meaning:
#     lwork >= 3*n + max(2*max(lld_z,lld_a)+2*locc(n),7*ceil(n/hbl)/lcm(npcolrows,npcolcols))
#     where:
#           lld_z = descz[9], lld_a = desca[9], csrc_a = desca[8]
#           locc(n) = numroc(n,numblocks,mycol=npcol,csrc_a,npcolcols)
#           hbl = numblocks ( = mblocks = nblocks )
for (fname, elty) in ((:pslaqr1_, :Float32),
                      (:pdlaqr1_, :Float64))
# for (fname, elty) in ((:pslahqr_, :Float32),
#                       (:pdlahqr_, :Float64))
        @eval begin
        function pXlahqr!(wantt::Bool, wantz::Bool,
                          n::ScaInt, ilo::ScaInt, ihi::ScaInt,
                          A::Matrix{$elty}, desca::Vector{ScaInt},
                          wr::Vector{$elty}, wi::Vector{$elty},
                          iloz::ScaInt, ihiz::ScaInt, Z::Matrix{$elty}, descz::Vector{ScaInt})

            # inner variables
            info = zeros(ScaInt,1)
            work = zeros($elty,1); lwork = convert(ScaInt, -1);
            iwork = zeros(ScaInt,1); ilwork = convert(ScaInt, -1);
            # j = 1 for perform a workspace query
            # j = 2 for perform ccall
            for j = 1:2
                ccall(($(string(fname)), libscalapack), Nothing,
                        (Ptr{Bool}, Ptr{Bool},
                        Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                        Ptr{$elty}, Ptr{ScaInt},
                        Ptr{$elty}, Ptr{$elty},
                        Ptr{ScaInt}, Ptr{ScaInt}, Ptr{$elty}, Ptr{ScaInt},
                        Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                        Ptr{ScaInt}),
                        Ref(wantt), Ref(wantz),
                        Ref(n), Ref(ilo), Ref(ihi),
                        A, desca, wr, wi,
                        Ref(iloz), Ref(ihiz), Z, descz,
                        work, Ref(lwork), iwork, Ref(ilwork),
                        info)
                # allocate vector for j = 2
                if j == 1
                    lwork = convert(ScaInt, work[1])
                    ilwork = convert(ScaInt, iwork[1])
                    # ilwork = convert(ScaInt, 1000)
                    work = zeros($elty, lwork)
                    iwork = zeros(ScaInt, ilwork)
                end
            end

            if info[1] < 0
                error("input argument $(info[1]) has illegal value")
            end

        end
    end
end
for (fname, elty) in ((:pclahqr_, :ComplexF32),
                      (:pzlahqr_, :ComplexF64))
    @eval begin
        function pXlahqr!(wantt::Bool, wantz::Bool,
                            n::ScaInt, ilo::ScaInt, ihi::ScaInt,
                            A::Matrix{$elty}, desca::Vector{ScaInt},
                            w::Vector{$elty},
                            iloz::ScaInt, ihiz::ScaInt, Z::Matrix{$elty}, descz::Vector{ScaInt})

            # inner variables
            info = zeros(ScaInt,1)
            work = zeros($elty,1); lwork = convert(ScaInt, -1);
            iwork = zeros(ScaInt,1); ilwork = convert(ScaInt, -1);
            # j = 1 for perform a workspace query
            # j = 2 for perform ccall
            for j = 1:2                
                ccall(($(string(fname)), libscalapack), Nothing,
                        (Ptr{Bool}, Ptr{Bool},
                        Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                        Ptr{$elty}, Ptr{ScaInt},
                        Ptr{$elty},
                        Ptr{ScaInt}, Ptr{ScaInt}, Ptr{$elty}, Ptr{ScaInt},
                        Ptr{$elty}, Ptr{ScaInt}, Ptr{ScaInt}, Ptr{ScaInt},
                        Ptr{ScaInt}),
                        Ref(wantt), Ref(wantz),
                        Ref(n), Ref(ilo), Ref(ihi),
                        A, desca, w,
                        Ref(iloz), Ref(ihiz), Z, descz,
                        work, Ref(lwork), iwork, Ref(ilwork),
                        info)
                # allocate vector for j = 2
                if j == 1
                    lwork = convert(ScaInt, work[1])
                    ilwork = convert(ScaInt, iwork[1])
                    work = zeros($elty, lwork)
                    iwork = zeros(ScaInt, ilwork)
                end
            end

            if info[1] < 0
                error("input argument $(info[1]) has illegal value")
            end

        end
    end
end

#
for (fname, elty, elty_r) in ((:pctrevc_, :ComplexF32, :Float32),
                              (:pztrevc_, :ComplexF64, :Float64))
    @eval begin
        function pXtrevc!(side::Char, howmny::Char, select::Vector{Bool},
                           n::ScaInt, T::Matrix{$elty}, desct::Vector{ScaInt},
                           vl::Matrix{$elty}, descvl::Vector{ScaInt}, vr::Matrix{$elty}, descvr::Vector{ScaInt})

            # inner variables
            info = zeros(ScaInt, 1)
            mm = n
            work = zeros($elty, 2*n)
            rwork = zeros($elty_r, n)
            # output variable
            m = zeros(ScaInt, 1)
            ccall(($(string(fname)), libscalapack), Nothing,
                    (Ptr{Char}, Ptr{Char}, Ptr{Bool},
                    Ptr{ScaInt}, Ptr{$elty}, Ptr{ScaInt},
                    Ptr{$elty}, Ptr{ScaInt}, Ptr{$elty}, Ptr{ScaInt},
                    Ptr{ScaInt}, Ptr{ScaInt},
                    Ptr{$elty}, Ptr{$elty_r}, Ptr{ScaInt}),
                    f_pchar(side), f_pchar(howmny), select,
                    Ref(n), T, desct,
                    vl, descvl, vr, descvr,
                    Ref(mm), m,
                    work, rwork, info)

            if info[1] < 0
                error("input argument $(info[1]) has illegal value")
            end

            return m[1]
            
        end
    end
end