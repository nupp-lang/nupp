Module.nuppSetSideStackPointer = (value) => {
  wasmImports.__stack_pointer = new WebAssembly.Global(
    { value: "i32", mutable: true },
    value
  );
};
