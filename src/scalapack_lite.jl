
# abstract ScaLapackLite type
abstract type AbstractScaLapackLite end

# ScaLapackLite parameters
mutable struct ScaLapackLiteParams <: AbstractScaLapackLite
    mblocks::ScaInt; nblocks::ScaInt;
    mprocs::ScaInt; nprocs::ScaInt;
    rootproc::ScaInt
    # Constructor
    ScaLapackLiteParams() = new(1, 1, 1, 1, 0)
    ScaLapackLiteParams(mblocks, nblocks, mprocs, nprocs, rootproc) = new(mblocks, nblocks, mprocs, nprocs, rootproc)
end
function Base.:(==)(A::ScaLapackLiteParams, B::ScaLapackLiteParams)
    is_equal_blocks = (A.mblocks == B.mblocks) && (A.nblocks == B.nblocks)
    if !is_equal_blocks
        error("different block sizes: A and B")
    end
    is_equal_procs = (A.mprocs == B.mprocs) && (A.nprocs == B.nprocs)
    if !is_equal_procs
        error("different process grids: A and B")
    end
    is_equal_rootproc = (A.rootproc == B.rootproc)
    if !is_equal_rootproc
        error("different process root: A and B")
    end
    return is_equal_blocks && is_equal_procs && is_equal_rootproc
end

# ScaLapackLiteMatrix type
mutable struct ScaLapackLiteMatrix <: AbstractScaLapackLite
    params::ScaLapackLiteParams
    X::Matrix{<:Number} 
    ScaLapackLiteMatrix() = new(ScaLapackLiteParams())
    ScaLapackLiteMatrix(params) = new(params)
    ScaLapackLiteMatrix(params, X) = new(params, X)
end

#--- operator overloadings ---#

# perform A'
function Base.:(adjoint)(A::ScaLapackLiteMatrix)
    return ScaLapackLiteMatrix(A.params, A.X') 
end

# perform A*B
function Base.:(*)(A::ScaLapackLiteMatrix, B::ScaLapackLiteMatrix)
    # check A and B have same params
    if A.params == B.params
        C = multiple(A.X, B.X, A.params)
        return ScaLapackLiteMatrix(A.params, C)
    else
        throw(DimensionMismatch("ScaLapackLiteMatrix A and B have different ScaLapaclLiteParams"))
    end
end

#--- multiple ---#
for (elty) in (:Float32, :Float64, :ComplexF32, :ComplexF64)
    @eval begin
        function multiple(A::Matrix{$elty}, B::Matrix{$elty}, params::ScaLapackLiteParams)

            # MPI parameters
            mblocks = params.mblocks
            nblocks = params.nblocks
            mprocs = params.mprocs
            nprocs = params.nprocs
            rootproc = params.rootproc
            comm = MPI.COMM_WORLD
            rank = MPI.Comm_rank(comm)
            zero = 0; one = 1;

            # copy matrix from master to slave
            A = MPI.bcast(A, rootproc, comm)
            B = MPI.bcast(B, rootproc, comm)
            MPI.Barrier(comm)

            # check both dimensions; cols(A) = rows(B)
            # (mA, nA), (mB, nB) = (mA, nA), (nA, nB)
            if rank == rootproc
                check_multiple(A, B)
            end

            # create context
            ctxt = ScaLapack.sl_init(mprocs, nprocs)
            ctxt0 = ScaLapack.sl_init(mprocs, nprocs)

            # matrix parameters
            mA, nA = size(A)
            mB, nB = size(B)
            mproc, nproc, myrow, mycol = BLACS.gridinfo(ctxt)
            mxlocr_A = ScaLapack.numroc(mA, mblocks, mproc, 0, mprocs)
            mxlocr_B = ScaLapack.numroc(mB, mblocks, mproc, 0, mprocs)
            mxlocc_A = ScaLapack.numroc(nA, nblocks, nproc, 0, nprocs)
            mxlocc_B = ScaLapack.numroc(nB, nblocks, nproc, 0, nprocs)
            mxllda_A = max(1, mxlocr_A)
            mxllda_B = max(1, mxlocr_B)

            if mproc >= 0 && nproc >= 0

                # get array descriptor
                # (mA, nA) x (mB, nB) = (mA, nA) x (nA, nB) = (mA, nB)
                # (mA, nB) --> (mxlocr_A, mxlocc_B) --> mxllda_A
                desc_A = ScaLapack.descinit(mA, nA, mA, nA, zero, zero, ctxt0, mA)
                desc_B = ScaLapack.descinit(mB, nB, mB, nB, zero, zero, ctxt0, mB)
                desc_C = ScaLapack.descinit(mA, nB, mA, nB, zero, zero, ctxt0, mA)
                desc_myA = ScaLapack.descinit(mA, nA, mblocks, nblocks, zero, zero, ctxt, mxllda_A)
                desc_myB = ScaLapack.descinit(mB, nB, mblocks, nblocks, zero, zero, ctxt, mxllda_B)
                desc_myC = ScaLapack.descinit(mA, nB, mblocks, nblocks, zero, zero, ctxt, mxllda_A)

                # generate process matrix
                myA = zeros($elty, mxlocr_A, mxlocc_A)
                myB = zeros($elty, mxlocr_B, mxlocc_B)
                ScaLapack.pXgemr2d!(mA, nA,
                                    A, one, one, desc_A,
                                    myA, one, one, desc_myA,
                                    ctxt)
                ScaLapack.pXgemr2d!(mB, nB,
                                    B, one, one, desc_B,
                                    myB, one, one, desc_myB,
                                    ctxt)

                # perform A*B
                α = 1.0; β = 0.0;
                myC = zeros($elty, mxlocr_A, mxlocc_B)
                transa = 'n'; transb = 'n';
                ScaLapack.pXgemm!(transa, transb,
                                  mA, nB, nA,
                                  α,
                                  myA, one, one, desc_myA,
                                  myB, one, one, desc_myB,
                                  β,
                                  myC, one, one, desc_myC)

                # merge local matrix to global
                C = Matrix{$elty}(undef, mA, nB)
                ScaLapack.pXgemr2d!(mA, nB,
                                    myC, one, one, desc_myC,
                                    C, one, one, desc_C,
                                    ctxt0)

            end
            
            BLACS.barrier(ctxt, 'A')
            BLACS.barrier(ctxt0, 'A')
            BLACS.gridexit(ctxt)
            BLACS.gridexit(ctxt0)

            # free
            if rank != rootproc
                A = Matrix{$elty}(undef, 0, 0)
                B = Matrix{$elty}(undef, 0, 0)
                C = Matrix{$elty}(undef, 0, 0)
            end

            return C

        end     # function

    end         # eval
end             # for


#--- find hessenberg matrix ---#
function hessenberg(sllm_A::ScaLapackLiteMatrix, reduced::Bool = true)

    # assume: ScaLapackLiteParams must be correctly given for all processes
    params = sllm_A.params
    
    # MPI parameters
    mblocks = params.mblocks
    nblocks = params.nblocks
    mprocs = params.mprocs
    nprocs = params.nprocs
    rootproc = params.rootproc
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    zero = 0; one = 1;

    # copy matrix from master to slave
    sllm_A = MPI.bcast(sllm_A, rootproc, comm)

    # decompose
    A = sllm_A.X

    # type of the matrix A
    elty = typeof(A[1,1])

    # check dimensions
    if rank == rootproc
        check_hessenberg(A)
        if mblocks != nblocks
            throw(DimensionMismatch("process grid must be contained from squared blocks"))
        end
    end

    # create context
    ctxt = ScaLapack.sl_init(mprocs, nprocs)
    ctxt0 = ScaLapack.sl_init(mprocs, nprocs)

    # matrix parameters
    m, n = size(A)
    mproc, nproc, myrow, mycol = BLACS.gridinfo(ctxt)
    mxlocr = ScaLapack.numroc(m, mblocks, mproc, 0, mprocs)
    mxlocc = ScaLapack.numroc(n, nblocks, nproc, 0, nprocs)
    mxllda = max(1, mxlocr)

    if mproc >= 0 && nproc >= 0

        # get array descriptor
        desc = ScaLapack.descinit(m, n, m, n, zero, zero, ctxt0, m)
        desc_my = ScaLapack.descinit(m, n, mblocks, nblocks, zero, zero, ctxt, mxllda)

        # generate process matrix
        myA = zeros(elty, mxlocr, mxlocc)
        ScaLapack.pXgemr2d!(m, n,
                            A, one, one, desc,
                            myA, one, one, desc_my,
                            ctxt)

        # MPI params
        numblocks = mblocks
        rsrc_a = zero
        csrc_a = zero

        # prepare for calc lwork
        ia = 1; ja = 1;
        ilo = 1; ihi = m;

        # allocation
        τ = zeros(elty, ScaLapack.numroc(ja+n-2, numblocks, mycol, csrc_a, nprocs))

        # find hessenberg matrix
        ScaLapack.pXgehrd!(m, ilo, ihi,
                           myA, ia, ja, desc_my,
                           τ)

        # merge local matrix to global
        ScaLapack.pXgemr2d!(m, n,
                            myA, one, one, desc_my,
                            A, one, one, desc,
                            ctxt0)

    end
    
    BLACS.barrier(ctxt, 'A')
    BLACS.barrier(ctxt0, 'A')
    BLACS.gridexit(ctxt)
    BLACS.gridexit(ctxt0)

    # free
    if rank != rootproc
        A = Matrix{elty}(undef, 0, 0)
    end

    return ScaLapackLiteMatrix(params, A)

end     # function

#--- find eigenvalues ---#
function eigs(sllm_A::ScaLapackLiteMatrix)

    # assume: ScaLapackLiteParams must be correctly given for all processes
    params = sllm_A.params

    # MPI parameters
    mblocks = params.mblocks
    nblocks = params.nblocks
    mprocs = params.mprocs
    nprocs = params.nprocs
    rootproc = params.rootproc
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    zero = 0; one = 1;

    # copy matrix from master to slave
    sllm_A = MPI.bcast(sllm_A, rootproc, comm)

    # decompose
    A = sllm_A.X
    # type of the matrix A
    elty = typeof(A[1,1])
    elty_s = elty
    if elty == ComplexF32; elty_s = Float32;
    elseif elty == ComplexF64; elty_s = Float64; end

    # check dimensions
    if rank == rootproc
        check_eigs(A)
        if mblocks != nblocks
            throw(DimensionMismatch("process grid must be contained from squared blocks"))
        end
    end

    # create context
    ctxt = ScaLapack.sl_init(mprocs, nprocs)
    ctxt0 = ScaLapack.sl_init(mprocs, nprocs)

    # matrix parameters
    m, n = size(A)
    mproc, nproc, myrow, mycol = BLACS.gridinfo(ctxt)
    mxlocr = ScaLapack.numroc(m, mblocks, mproc, 0, mprocs)
    mxlocc = ScaLapack.numroc(n, nblocks, nproc, 0, nprocs)
    mxllda = max(1, mxlocr)

    if mproc >= 0 && nproc >= 0

        # get array descriptor
        desc = ScaLapack.descinit(m, n, m, n, zero, zero, ctxt0, m)
        desc_my = ScaLapack.descinit(m, n, mblocks, nblocks, zero, zero, ctxt, mxllda)

        # generate process matrix
        myA = zeros(elty, mxlocr, mxlocc)
        ScaLapack.pXgemr2d!(m, n,
                            A, one, one, desc,
                            myA, one, one, desc_my,
                            ctxt)

        # balancing ( now, this is the point of an error occured )
        job = 'B'
        ilo = 1; ihi = m;
        scale = zeros(elty_s, mxllda)
        print("[$rank]: check, pre bal scale = $scale\n")
        ScaLapack.pXgebal!(job, mxllda,
                           myA, desc_my, ilo, ihi,
                           scale)

        print("[$rank]: check local(A) = $myA\n")

        # MPI params
        numblocks = mblocks
        rsrc_a = zero
        csrc_a = zero

        # find hessenberg matrix
        ia = 1; ja = 1;
        τ = zeros(elty, ScaLapack.numroc(ja+n-2, numblocks, mycol, csrc_a, nprocs))
        ScaLapack.pXgehrd!(m, ilo, ihi,
                           myA, ia, ja, desc_my,
                           τ)

        print("[$rank]: check local(H) = $myA\n")
        print("[$rank]: check local(τ) = $τ\n")

        # generate orthogonal Q matrix
        side = 'L'; trans = 'N';
        myQ = zeros(elty, mxlocr, mxlocc)
        ScaLapack.pXYYmhr!(side, trans,
                           m, n, ilo, ihi,
                           myA, ia, ja, desc_my,
                           τ,
                           myQ, one, one, desc_my)

        print("[$rank]: check local(Q) = $myQ\n")

        # remove non-reduced part of the upper Hessenberg matrix
        uplo = 'L'
        α = convert(elty, zero); β = convert(elty, zero);
        ia_ = 3; ja_ = 1;
        # ScaLapack.pXlaset!(uplo, m-2, n-2,
        ScaLapack.pXlaset!(uplo, m, n,
                           α, β,
                           myA, ia_, ja_, desc_my)

        print("[$rank]: check local(H) = $myA\n")
                   
        # find eigenvalues
        wantt = true; wantz = true;
        ilo = 1; ihi = m;
        # for real input
        if elty == Float32 || elty == Float64
            wr = zeros(elty, m); wi = zeros(elty, m)
            ScaLapack.pXlahqr!(wantt, wantz, m,
                               ilo, ihi, myA, desc_my,
                               wr, wi,
                               ilo, ihi, myQ, desc_my)
            w = wr + im*wi
        # for complex input
        elseif elty == ComplexF32 || elty == ComplexF64
            ScaLapack.pXlahqr!(wantt, wantz, m,
                               ilo, ihi, myA, desc_my,
                               w,
                               ilo, ihi, myQ, desc_my)
        end

    end

    BLACS.barrier(ctxt, 'A')
    BLACS.barrier(ctxt0, 'A')
    BLACS.gridexit(ctxt)
    BLACS.gridexit(ctxt0)

    # free
    if rank != rootproc
        A = Matrix{elty}(undef, 0, 0)
        Z = Matrix{elty}(undef, 0, 0)
    end

    return (w, Z)

end

#--- ERROR dumpings ---#
function check_multiple(A::Matrix{<:Number}, B::Matrix{<:Number})
    mA, nA = size(A)
    mB, nB = size(B)
    if nA != mB
        throw(DimensionMismatch("matrix A has dimensions ($mA, $nA), matrix B has dimensions ($mB, $nB)"))
    end
end
function check_hessenberg(A::Matrix{<:Number})
    mA, nA = size(A)
    if mA != nA
        throw(DimensionMismatch("matrix A has no-squared dimensions ($mA, $nA)"))
    end
end
function check_eigs(A::Matrix{<:Number})
    mA, nA = size(A)
    if mA != nA
        throw(DimensionMismatch("matrix A has no-squared dimensions ($mA, $nA)"))
    end
end