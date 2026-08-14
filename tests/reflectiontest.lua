local T = require("nupp.compiler.types")
local generics = require("nupp.compiler.generics")
local reflection = require("nupp.compiler.reflection")
local json = require("cjson").new()

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function recursiveNode(valueType)
   local node = T.nominal("Node", "record")
   node.byname = {value = valueType, next = T.optional(node)}
   node.writeByname = {value = valueType, next = T.optional(node)}
   node.fieldOrder = {"value", "next"}
   return node
end

local M = {}

function M.serializesRecursiveTypesAsAcyclicIndexedGraphs()
   local descriptor = reflection.describe(recursiveNode(T.string), "Node")
   assertEq(descriptor.schema, 3, "reflection schema")
   assertEq(descriptor.root, 1, "root index")
   assertEq(descriptor.fields[1].name, "value", "declaration order begins with value")
   assertEq(descriptor.fields[2].name, "next", "declaration order retains next")
   local encoded = json.encode(descriptor)
   assert(#encoded > 0, "the recursive descriptor is plain JSON data")
   local reachesRoot = false
   for _, entry in ipairs(descriptor.types) do
      for _, member in ipairs(entry.members or {}) do
         if member == descriptor.root then reachesRoot = true end
      end
   end
   assert(reachesRoot, "the recursive edge refers back to the root index")
end

function M.reflectsExplicitTransferOnlyAffinity()
   local descriptor = reflection.describe(T.affine(T.string, nil, true), "OpaqueString")
   local root = descriptor.types[descriptor.root]
   assertEq(root.kind, "affine")
   assertEq(root.transferOnly, true, "reflection erased explicit transfer-only affinity")
end

function M.reflectsFieldDefaultsAndFingerprintsTheirValues()
   local first = recursiveNode(T.string)
   first.fieldDefaults = {value = {value = "first"}}
   local same = recursiveNode(T.string)
   same.fieldDefaults = {value = {value = "first"}}
   local changed = recursiveNode(T.string)
   changed.fieldDefaults = {value = {value = "second"}}
   local absent = recursiveNode(T.string)
   local firstDescriptor = reflection.describe(first, "Node")
   assertEq(firstDescriptor.fields[1].hasDefault, true, "default presence")
   assertEq(firstDescriptor.fields[1].defaultValue, "first", "default value")
   assertEq(reflection.describe(absent, "Node").fields[1].hasDefault, false,
      "missing default")
   assertEq(firstDescriptor.fingerprint, reflection.describe(same, "Node").fingerprint,
      "equal defaults fingerprint equally")
   assert(firstDescriptor.fingerprint ~= reflection.describe(changed, "Node").fingerprint,
      "changing a default changes the fingerprint")
end

function M.omitsPrivateFieldsFromSemanticReflection()
   local node = recursiveNode(T.string)
   node.privateFields = {next = true}
   node.moduleName = "models"
   local descriptor = reflection.describe(node, "Node")
   assertEq(#descriptor.fields, 1, "only the public field is reflected")
   assertEq(descriptor.fields[1].name, "value", "the reflected field is public")
end

function M.fingerprintsSemanticsRatherThanNominalAllocationIdentity()
   local first = reflection.describe(recursiveNode(T.string), "Node")
   local second = reflection.describe(recursiveNode(T.string), "Node")
   local changed = reflection.describe(recursiveNode(T.number), "Node")
   assertEq(first.fingerprint, second.fingerprint,
      "equivalent declarations ignore process-local nominal ids")
   assert(first.fingerprint ~= changed.fingerprint,
      "changing a reflected field changes the semantic fingerprint")
end

function M.fingerprintsResolvedDeclarationAndFieldAnnotations()
   local function annotated(recordName, fieldName)
      local node = recursiveNode(T.string)
      node.annotations = {{name = "json", arguments = {
         {name = "name", kind = "value", value = recordName},
      }}}
      node.fieldDefs = {value = {annotations = {{name = "json", arguments = {
         {name = "name", kind = "value", value = fieldName},
      }}}}}
      return reflection.describe(node, "Node")
   end
   local first = annotated("nodes", "payload")
   local same = annotated("nodes", "payload")
   local changedRecord = annotated("items", "payload")
   local changedField = annotated("nodes", "value")
   assertEq(first.fingerprint, same.fingerprint,
      "equivalent semantic annotations fingerprint identically")
   assert(first.fingerprint ~= changedRecord.fingerprint,
      "record annotation values enter the fingerprint")
   assert(first.fingerprint ~= changedField.fingerprint,
      "field annotation values enter the fingerprint")
   assertEq(first.annotations[1].arguments[1].value, "nodes",
      "record annotations are reflected")
   assertEq(first.fields[1].annotations[1].arguments[1].value, "payload",
      "field annotations are reflected")
end

function M.coversStructuralFunctionsCollectionsAndCapabilities()
   local callback = T.func(
      {T.array(T.union({T.string, T.integer}))},
      {T.shape({
         {name = "readable", read = T.string},
         {name = "writable", write = T.number},
      })},
      false,
      {"borrows"},
      nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, true,
      {"values"}
   )
   local descriptor = reflection.describe(callback, "Callback")
   local kinds = {}
   for _, entry in ipairs(descriptor.types) do kinds[entry.kind] = true end
   for _, kind in ipairs({"func", "array", "union", "shape", "string", "integer", "number"}) do
      assert(kinds[kind], "descriptor includes " .. kind)
   end
   local fn = descriptor.types[descriptor.root]
   assertEq(fn.parameters[1].name, "values", "parameter name")
   assertEq(fn.parameters[1].mode, "borrows", "parameter mode")
   assertEq(fn.noYield, true, "suspension guarantee")
   local result = descriptor.types[fn.returns[1]]
   assertEq(result.fields[1].name, "readable", "shape fields are canonical")
   assertEq(result.fields[1].readable, true, "read capability")
   assertEq(result.fields[1].writable, false, "read-only capability")
   assertEq(result.fields[2].readable, false, "write-only capability")
   assertEq(result.fields[2].writable, true, "write capability")
end

function M.carriesConstBindersAndArrayTermsInTheSharedDescriptorVocabulary()
   local size = T.constvar("Size", "integer", "reflection:const")
   local count = T.constOp("*", {size, T.constLiteral("integer", 2)})
   local alias = T.genericAlias("Buffer", T.carray(T.uint8, nil, count),
      nil, nil, nil, {size}, {"const"})
   local descriptor = reflection.describe(alias, "Buffer")
   local root = descriptor.types[descriptor.root]
   assertEq(root.parameterKinds[1], "const", "generic parameter kind")
   local parameter = descriptor.types[root.constParameters[1]]
   assertEq(parameter.kind, "constVar", "const binder descriptor")
   assertEq(parameter.domain, "integer", "const binder domain")
   local body = descriptor.types[root.body]
   local term = descriptor.types[body.countTerm]
   assertEq(term.kind, "constOp", "C array count term")
   assertEq(term.operation, "*", "C array count operation")
end

function M.carriesNominalPackParametersAndArguments()
   local results = T.packvar("Results", "reflection:results")
   local matcher = T.nominal("Matcher", "interface")
   matcher.packParams = {results}
   matcher.paramKinds = {"pack"}
   local concrete = generics.instantiate(matcher, {
      [results] = T.pack({T.string, T.integer}),
   })

   local declaration = reflection.describe(matcher, "Matcher")
   local declarationRoot = declaration.types[declaration.root]
   assertEq(declarationRoot.parameterKinds[1], "pack", "nominal parameter kind")
   local parameter = declaration.types[declarationRoot.packParameters[1]]
   assertEq(parameter.kind, "packvar", "nominal pack binder")

   local application = reflection.describe(concrete, "Matcher<(string, integer)>")
   local applicationRoot = application.types[application.root]
   local argument = application.types[applicationRoot.packArguments[1]]
   assertEq(argument.kind, "pack", "nominal pack argument")
   assertEq(#argument.head, 2, "nominal pack arity")
end

return M
