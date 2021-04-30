"""
    check_duplicate_annotations(met::Metabolite, mets::Vector{Metabolite}; inspect_annotations=...)

Check if a metabolite `met` has overlapping annotations with metabolites in `mets`.
If the annotations overlap, then check if they share a compartment to determine if it a a true duplicate.
The annotations checked are: ["kegg.compound", "bigg.metabolite", "chebi", "inchi_key", "sabiork", "hmdb", 
"seed.compound", "metanetx.chemical", "reactome.compound", "biocyc"].
Return index of the first hit, otherwise `nothing`.

See also: [`check_same_formula`](@ref), [`get_atoms`](@ref)
"""
function check_duplicate_annotations(
    cmet::Metabolite,
    mets::OrderedDict{String,Metabolite};
    inspect_annotations = [
        "kegg.compound",
        "bigg.metabolite",
        "chebi",
        "inchi_key",
        "sabiork",
        "hmdb",
        "seed.compound",
        "metanetx.chemical",
        "reactome.compound",
        "biocyc",
    ],
)::Union{Nothing,String}
    for (k, met) in mets
        if met.compartment == cmet.compartment # check if same compartment
            for anno in inspect_annotations
                if length(
                    intersect(
                        get(met.annotations, anno, ["c1"]),
                        get(cmet.annotations, anno, ["c2"]),
                    ),
                ) != 0
                    return k
                end
            end
        end
    end
    return nothing
end

"""
    get_atoms(met::Metabolite)

Return a dictionary mapping the elements in a metabolite `met` to their stoichiometric coefficients.

See also: [`check_duplicate_annotations`](@ref), [`check_same_formula`](@ref)
"""
function get_atoms(met::Metabolite)
    atoms = Dict{String,Int}()
    isnothing(met.formula) && return nothing
    for m in eachmatch(r"([A-Z]{1})([a-z]?)(\d*)", met.formula)
        element = match(r"([A-Z]{1})([a-z]?)", m.match)
        number = match(r"\d\d*", m.match)
        atoms[string(element.match)] =
            isnothing(number) ? 1 : parse(Int, string(number.match))
    end
    return atoms
end