# Nupp for VS Code

This extension registers `.nupp` files, supplies a TextMate grammar, and starts
the Nupp language server over stdio. The server provides syntax and type
diagnostics, navigation, hover types and documentation, completion, signature
help, references, project-wide rename, semantic highlighting, document
formatting, and code actions. The extension watches `.nupp` files in each workspace, so changes made
by Git, generators, or another editor invalidate the language server's
incremental graph as well as changes made in an open VS Code document.

## Code actions

Quick fixes come from the checker, so the lightbulb offers exactly what the
diagnostic means, and each way out a message names is its own entry rather than
a choice made on your behalf:

- **NUPP2119** — a declaration with no visibility: mark it `local`, mark it
  `global`, or attach it to the table the file returns.
- **NUPP2120** — a project module used without requiring it: add the require,
  written where the file already keeps them.
- **NUPP2101** — a type name some module exports: spell it through that module,
  adding the require in the same edit when there is none.
- **NUPP2603** — an ownership obligation that cannot be automatically
  discharged: apply one of the diagnostic's explicit terminal fixes.

## Development

From this directory:

    npm install
    npm test

Open the repository in VS Code and run **Run Nupp extension** from the Run
and Debug view. The Extension Development Host opens this repository and uses
`bin/nupp` through the workspace setting in `.vscode/settings.json`.

To install the extension into the normal VS Code profile:

    npm run package
    code --install-extension nupp.vsix --force

For projects outside this checkout, put `nupp` on `PATH` or customize the
language-server process with `nupp.serverPath`, `nupp.serverArgs`,
`nupp.serverCwd`, and `nupp.serverEnvironment`. String values expand
`${workspaceFolder}` and `${env:NAME}`. Arguments are passed directly without
shell interpretation.

For example, a wrapper command can be configured as:

```json
{
  "nupp.serverPath": "nix",
  "nupp.serverArgs": [
    "develop",
    "--command",
    "nupp",
    "lsp",
    "serve",
    "${workspaceFolder}"
  ],
  "nupp.serverCwd": "${workspaceFolder}",
  "nupp.serverEnvironment": {
    "NUPP_LOG": "${workspaceFolder}/.nupp/lsp.log"
  }
}
```

## Highlighting

The TextMate grammar provides immediate lexical highlighting, including
`cdef` declarations and C interop types. A declaration qualified by the table
it attaches to (`record shapes.Point`) highlights that table as a namespace
and the last segment as the type name. Once the language server is ready,
semantic tokens refine contextual keywords, declarations, parameters,
functions, properties, types, and references using checker information.

## Embedded string syntax

`string<"json">`, `string<"glsl">`, `string<"lua">`, `string<"nupp">`, and
`string<"peg">` are transparent string types whose literal argument tells the
editor what a directly initialized local or const long string contains:

```nupp
local config: string<"json"> = dedent [[
   {"enabled": true}
   ]]
```

The annotation is type-erased; the value is an ordinary `string`. Long strings
are required for embedded highlighting so their contents are not obscured by
Lua escape sequences. `dedent` removes the closing delimiter's indentation
from the content, making indented text blocks convenient.
