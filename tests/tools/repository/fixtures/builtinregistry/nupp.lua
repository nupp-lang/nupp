-- The compiler pack of the builtin registry suite's seeded checkout: it has
-- the seeded builtin's public modules and not its provider.
return {
    build = {
        targets = {
            dist = {
                resources = {
                    {source = "src/seededbuiltin/init.nupp", output = "nupp/compiler/seededbuiltin/init.nupp"},
                    {source = "src/seededbuiltin/reader.nupp", output = "nupp/compiler/seededbuiltin/reader.nupp"},
                },
            },
        },
    },
}
