"""
    hit_and_run(
        N::Int,
        opt_model;
        keepevery = 100,
        samplesize = 1000,
        random_objective = false,
    )

Perform a basic hit and run sampling for `N` iterations on a constrained JuMP
model in `opt_model`. See "Robert L. Smith Efficient Monte Carlo Procedures for
Generating Points Uniformly Distributed over Bounded Regions. Operations
Research 32 (6) 1296-1308 https://doi.org/10.1287/opre.32.6.1296" for more
details.

The process generates `samplesize` samples, and logs the sample state each
`keepevery` iterations.

Warm up points are generated by minimizing and maximizing reactions as in
[`flux_variability_analysis`](@ref), unless the `random_objective` is `true`,
in which case a randomly weighted objective is used for warmup.

Note that `N` needs to be greater than sample size, and should be greater than
the dimensionality of the sampled space (i.e., at least same as the number of
reactions).

# Example
```
using COBREXA
using JuMP
using Tulip

model = load_model(StandardModel, "e_coli_core.json")
biomass = findfirst(model.reactions, "BIOMASS_Ecoli_core_w_GAM")
glucose = findfirst(model.reactions, "EX_glc__D_e")

opt_model = flux_balance_analysis(model, Tulip.Optimizer; 
    modifications=[change_objective(biomass), 
    modify_constraint(glucose, -12, -12), 
    change_optimizer_attribute("IPM_IterationsLimit", 500)])

biomass_index = model[biomass]
λ = JuMP.value(opt_model[:x][biomass_index])
modify_constraint(biomass, 0.99*λ, λ)(model, opt_model)

samples = hit_and_run(100_000, opt_model; keepevery=10, samplesize=5000)
```
"""
function hit_and_run(
    model,
    optimizer;
    modifications = [],
    N = 1000,
    keepevery = _constants.sampling_keep_iters,
    samplesize = _constants.sampling_size,
    warmup_indices = collect(1:n_reactions(model)),
    workers = [myid()],
    nchains = 1,
)

    # get warmup points in parallel, similar to FVA
    ws, lbs, ubs = warmup(
        model,
        optimizer;
        modifications = modifications,
        workers = workers, # parallel
        warmup_points = warmup_indices
    )

    # load warmup points to workers
    save_at.(workers, :cobrexa_ws, Ref(:($ws)))
    save_at.(workers, :cobrexa_lbs, Ref(:($lbs)))
    save_at.(workers, :cobrexa_ubs, Ref(:($ubs)))

    # do in parallel! 
    samples = dpmap(
        x -> :($COBREXA._serial_hit_and_run(cobrexa_ws, cobrexa_lbs, cobrexa_ubs, $samplesize, $keepevery, $N)),
        CachingPool(workers),
        1:nchains,
    )

    # remove warmup points from workers
    map(fetch, remove_from.(workers, :cobrexa_ws))
    map(fetch, remove_from.(workers, :cobrexa_lbs))
    map(fetch, remove_from.(workers, :cobrexa_ubs))

    # not sure how to do this better - cat/vcat doesn't work, oh well 
    vals = zeros(samplesize, length(lbs), nchains)
    for c = 1:nchains
        vals[:, :, c] = samples[c]'
    end
    chains = Chains(vals, reactions(model))

    return chains
end

function _serial_hit_and_run(ws, lbs, ubs, samplesize, keepevery, N)
    samples = zeros(length(lbs), samplesize) # sample storage
    current_point = zeros(length(lbs))
    current_point .= ws[1, 1] # just use the first warmup point, randomness is introduced later
    direction = zeros(length(lbs))

    sample_num = 0
    samplelength = 0
    use_warmup_points = true
    for n = 1:N

        if use_warmup_points
            i = rand(1:size(ws, 1))
            j = rand(1:size(ws, 2))
            direction .= ws[i, j] - current_point # use warmup points to find direction in warmup phase
        else
            direction .= samples[:, rand(1:(samplelength))] - current_point # after warmup phase, only find directions in sampled space
        end

        λmax = Inf
        λmin = -Inf
        for i in eachindex(lbs)
            δlower = lbs[i] - current_point[i]
            δupper = ubs[i] - current_point[i]
            # only consider the step size bound if the direction of travel is non-negligible
            if direction[i] < -_constants.tolerance
                lower = δupper / direction[i]
                upper = δlower / direction[i]
            elseif direction[i] > _constants.tolerance
                lower = δlower / direction[i]
                upper = δupper / direction[i]
            else
                lower = -Inf
                upper = Inf
            end
            lower > λmin && (λmin = lower) # max min step size that satisfies all bounds
            upper < λmax && (λmax = upper) # min max step size that satisfies all bounds
        end

        if λmax <= λmin || λmin == -Inf || λmax == Inf # this sometimes can happen
            #     @warn "Infeasible direction at iteration $(n)..." # noisy
            continue
        end

        λ = rand() * (λmax - λmin) + λmin # random step size
        current_point .= current_point .+ λ .* direction # will be feasible

        if n % keepevery == 0
            sample_num += 1
            samples[:, sample_num] .= current_point
            if sample_num >= samplesize
                use_warmup_points = false # once the entire memory vector filled, stop using warm up points
                sample_num = 0 # reset, start replacing the older samples
            end
            use_warmup_points && (samplelength += 1) # lags sample_num because the latter is a flag as well
        end

    end

    return samples
end
