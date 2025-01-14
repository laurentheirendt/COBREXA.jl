# Generic interface

The reason you should rather use the generic interface is that the generic
interface is supported by all model types in `COBREXA`, while the internal
model structure of each model type varies considerably. For example,
`MATModel`s store the stoichiometric matrix directly, so `mat_model.mat["S"]`
would return the stoichiometric matrix. However, `JSONModel`s do not do this,
so `json_model.m["S"]` would throw an error. The `COBREXA` way of doing this is
to use the generic interface, i.e. `stoichiometry(json_model)` and
`stoichiometry(mat_model)` always return the stoichiometric matrix. 

Note, it is possible that the matrix returned by `stoichiometry` is not exactly
the same __between__ models. The order of the reactions (columns) and
metabolites (rows) may vary from model type to model type, although they are
consistent __within__ each model type. So `stoichiometry(json_model)` will
return a stoichiometric matrix where the columns correspond to the order of
reactions listed in `reactions(json_model)` and the rows corresponds to the
order of metabolites listed in `metabolites(json_model)`. The column/reaction
and row/metabolite order from the `JSONModel` is not *necessarily* consistent
with the stoichiometric matrix returned by `stoichiometry(mat_model)`. This is
a minor note, but could cause confusion. 

# Converting models
You might recall that we mentioned that data loss does not occur when models
are read into the format corresponding to their file type. This is because the
models are read into memory directly in their native formats. So `JSONModel`s
contain the dictionary encoded in the `.json` file, and the same for `.mat` and
`.xml` files (technically `.xml` is parsed by `SBML.jl`).

However, this data loss guarantee does __not__ hold once you convert between
models. The reason for this is that the `convert` function uses the generic
interface to convert between models. In short, only information accessible
through the generic interface will be converted between models. This is most
applicable for data stored using non-standard keywords (`.mat` and to a lesser
extent `.json` models are prone to this type of issue). When in doubt, inspect
your models and refer to `src/base/constants.jl` for the `keynames` used to
access model features if issues occur. However, this should rarely be a
problem.

`COBREXA` also has specialized model types: `StandardModel`, `CoreModel`, and
`CoreCoupledModel`. These model types are implemented to be as efficient as
possible for their purpose. In short, use:
1. `StandardModel` if keeping all the meta-data associated with a model is
   important. This includes information like gene reaction rules, annotations,
   notes, etc. It is a good format to use when you wish to combine many models
   of different types and are not worried about memory limitations. 
2. `CoreModel` if you only care about constraint-based analysis that can be
   performed using only the stoichiometric matrix and flux bounds. This model
   stores all its numeric data structures as sparse matrices/vectors and is
   thus very efficient. It does not store superfluous information, like the
   gene reaction rules of reactions, annotations etc. Since this model is
   compact and its data structures efficient, it is ideal for distributed
   computing.
3. `CoreModelCoupled` if you want to use the functionality of `CoreModel` but
   for communities. It also represents the underlying model in a sparse format,
   but specialized for community models. 

Let's load a `StandardModel` and a `CoreModel` to compare the two.
