// The snippets the "Example" dropdown offers, in menu order. The first one
// is what the editor opens on.
//
// Each is a standalone program rather than a module: the playground checks
// one buffer with no filesystem behind it (see README.md), so nothing here
// can `require` anything else. Keep them short enough to read without
// scrolling the editor, and end each with a "try breaking it" line — the
// point of a playground is the diagnostic you get for editing it, not the
// clean check you get for leaving it alone.
//
// Nothing here may declare a `struct`, `cdef`, or `cheader`: those need a
// real C ABI, which is the one thing the browser build's `ffi` stub can't
// stand in for.
//
// Nothing here may use syntax newer than bootstrap/nupp.lua either — that
// bundle, not build/, is the compiler this page runs, so `./bin/nupp check`
// will pass a snippet the page cannot parse. Check a new one with
// `luajit bootstrap/nupp.lua check <file>` from the repository root.
import TOUR from "./examples/tour.nupp";
import NARROWING from "./examples/narrowing.nupp";
import GENERICS from "./examples/generics.nupp";
import RECORDS from "./examples/records.nupp";
import UNIONS from "./examples/unions.nupp";
import OWNERSHIP from "./examples/ownership.nupp";
import SYNTAX from "./examples/syntax.nupp";
import OPTIMIZER from "./examples/optimizer.nupp";
import COMPTIME from "./examples/comptime.nupp";
import TYPE_LEVEL_DSL from "./examples/type-level-dsl.nupp";
import PEG from "./examples/peg.nupp";

// Roughly in order of how much of the language each one asks you to already
// know, since a menu is read top to bottom.
export const EXAMPLES = [
  { id: "tour", label: "A quick tour", source: TOUR },
  { id: "narrowing", label: "Narrowing and predicates", source: NARROWING },
  { id: "generics", label: "Generics and bounds", source: GENERICS },
  { id: "records", label: "Records and interfaces", source: RECORDS },
  { id: "unions", label: "Literal and tagged unions", source: UNIONS },
  { id: "ownership", label: "Ownership", source: OWNERSHIP },
  { id: "syntax", label: "LuaJIT 3.0 syntax", source: SYNTAX },
  { id: "optimizer", label: "Optimizing compiler", source: OPTIMIZER },
  { id: "comptime", label: "Compile-time evaluation", source: COMPTIME },
  {
    id: "type-level-dsl",
    label: "Type-level arithmetic DSL",
    source: TYPE_LEVEL_DSL,
  },
  { id: "peg", label: "PEG expressions", source: PEG },
];
