@testset "Conversion from and to SBML model" begin
    json_model = download_data_file(
        "http://bigg.ucsd.edu/static/models/iJO1366.json",
        joinpath("data", "iJO1366.json"),
        "9376a93f62ad430719f23e612154dd94c67e0d7c9545ed9d17a4d0c347672313",
    )

    jm = read_model(json_model, JSONModel)
    cm = convert(CoreModel, jm) #TODO use a richer intermediate model
    jm2 = convert(JSONModel, cm)

    @test Set(reactions(jm)) == Set(reactions(cm))
end