"""
    struct SBMLModel

Thin wrapper around the model from SBML.jl library. Allows easy conversion from
SBML to any other model format.
"""
struct SBMLModel <: MetabolicModel
    m::SBML.Model
end

reactions(a::SBMLModel)::Vector{String} = [k for k in keys(a.m.reactions)]
metabolites(a::SBMLModel)::Vector{String} = [k for k in keys(a.m.species)]
n_reactions(a::SBMLModel)::Int = length(a.m.reactions)
n_metabolites(a::SBMLModel)::Int = length(a.m.species)

"""
    stoichiometry(a::SBMLModel)::SparseMat

Recreate the stoichiometry matrix from the SBML model.
"""
function stoichiometry(a::SBMLModel)::SparseMat
    _, _, S = SBML.getS(a.m)
    return S
end

"""
    bounds(a::SBMLModel)::Tuple{SparseVec,SparseVec}

Get the lower and upper flux bounds of a `SBMLModel`. Throws `DomainError` in
case if the SBML contains mismatching units.
"""
function bounds(a::SBMLModel)::Tuple{SparseVec,SparseVec}
    lbu = SBML.getLBs(a.m)
    ubu = SBML.getUBs(a.m)

    unit = lbu[1][2]
    getvalue = (val, _)::Tuple -> val
    getunit = (_, unit)::Tuple -> unit

    allunits = unique([getunit.(lbu) getunit.(ubu)])
    length(allunits) == 1 || throw(
        DomainError(
            allunits,
            "The SBML file uses multiple units; loading needs conversion",
        ),
    )

    return sparse.((getvalue.(lbu), getvalue.(ubu)))
end

balance(a::SBMLModel)::SparseVec = spzeros(n_metabolites(a))
objective(a::SBMLModel)::SparseVec = SBML.getOCs(a.m)

genes(a::SBMLModel)::Vector{String} = [k for k in a.m.gene_products]

function reaction_gene_association(a::SBMLModel, rid::String)::Maybe{GeneAssociation}
    grr = a.m.reactions[rid].grr
    maybemap(_parse_grr, grr)
end

metabolite_chemistry(a::SBMLModel, mid::String)::Maybe{MetaboliteChemistry} = mapmaybe(
    m.species[mid].formula,
    (fs) -> (_formula_to_dict(fs), default(0, m.species[mid].charge)),
)
