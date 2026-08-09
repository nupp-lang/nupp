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
import TOUR from "./examples/tour.nupp";
import RECORDS from "./examples/records.nupp";
import UNIONS from "./examples/unions.nupp";
import OWNERSHIP from "./examples/ownership.nupp";

export const EXAMPLES = [
  { id: "tour", label: "A quick tour", source: TOUR },
  { id: "records", label: "Records and interfaces", source: RECORDS },
  { id: "unions", label: "Literal and tagged unions", source: UNIONS },
  { id: "ownership", label: "Owned resources", source: OWNERSHIP },
];
