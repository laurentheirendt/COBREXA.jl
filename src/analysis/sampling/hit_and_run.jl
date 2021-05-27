"""
    TODO

Perform basic hit and run sampling for `N` iterations on `model` using `optimizer` to 
generate the warmup points. Here warmup points are generated by iteratively
minimizing and maximizing each reaction index in `warmup_indices`. Any problem modifications
needs to be specified in `modifications`. The sampler will store every `keepevery` sample. 
The sampler will return `nchains` which is a `Chain` type from `MCMCChains.jl`. This makes
investigating convergence easier. The sampler can also be run in parallel by specifying the
worker process indices. See "Robert L. Smith Efficient Monte Carlo Procedures for
Generating Points Uniformly Distributed over Bounded Regions. Operations
Research 32 (6) 1296-1308 https://doi.org/10.1287/opre.32.6.1296" for more
details about the algorithm.

Note that `N` needs to be much greater than sample size (especially if
`keepever` is not 1), and should be greater than
the dimensionality of the sampled space (i.e., at least same as the number of
reactions).

# Example: serial sampling
```
using COBREXA
using Tulip

model = load_model(StandardModel, model_path)

chains = hit_and_run(
    model,
    Tulip.Optimizer;
    N = 1000_000,
    nchains = 3,
    modifications = [change_constraint("EX_glc__D_e",-8, -8)]
    )
```

# Example: parallel sampling
```
using COBREXA
using Tulip

model = load_model(StandardModel, model_path)

using Distributed
addprocs(3)
@everywhere using COBREXA, Tulip

chains = hit_and_run(
    model,
    Tulip.Optimizer;
    N = 1000_000,
    nchains = 3,
    modifications = [change_constraint("EX_glc__D_e",-8, -8)]
    workerids = workers()
    )
```
"""
function affine_hit_and_run(
    warmup_points::Matrix{Float64},
    lbs::Vector{Float64},
    ubs::Vector{Float64};
    sample_iters = 100 .* (1:5),
    workers = [myid()],
    chains = length(workers),
)

    # distribute starting data to workers
    save_at.(workers, :cobrexa_hit_and_run_data, Ref((warmup_points, lbs, ubs)))

    # sample all chains
    samples = hcat(
        dpmap(
            chain -> :($COBREXA._affine_hit_and_run_chain(
                cobrexa_hit_and_run_data...,
                $sample_iters,
                $chain,
            )),
            CachingPool(workers),
            1:chains,
        )...,
    )

    # remove warmup points from workers
    map(fetch, remove_from.(workers, :cobrexa_hit_and_run_data))

    return samples
end

function _affine_hit_and_run_chain(warmup, lbs, ubs, iters, chain)

    points = copy(warmup)
    d, n_points = size(points)
    result = Matrix{Float64}(undef, size(points, 1), 0)

    iter = 0

    for iter_target in iters

        while iter < iter_target
            iter += 1

            new_points = copy(points)

            for i = 1:n_points

                mix = rand(n_points) .+ _constants.tolerance
                dir = points * (mix ./ sum(mix)) - points[:, i]

                # iteratively collect the maximum and minimum possible multiple
                # of `dir` added to the current point
                λmax = Inf
                λmin = -Inf
                for j = 1:d
                    dl = lbs[j] - points[j, i]
                    du = ubs[j] - points[j, i]
                    idir = 1 / dir[j]
                    if dir[j] < -_constants.tolerance
                        lower = du * idir
                        upper = dl * idir
                    elseif dir[j] > _constants.tolerance
                        lower = dl * idir
                        upper = du * idir
                    else
                        lower = -Inf
                        upper = Inf
                    end
                    λmin = max(λmin, lower)
                    λmax = min(λmax, upper)
                end

                λ = λmin + rand() * (λmax - λmin)
                !isfinite(λ) && continue # avoid divergence
                new_points[:, i] = points[:, i] .+ λ .* dir

                # TODO normally, here we would check if sum(S*new_point) is still
                # lower than the tolerance, but we shall trust the computer
                # instead.
            end

            points = new_points
        end

        result = hcat(result, points)
    end

    result
end
