-- Adapter for `tecs.types`, which the Teal router requires for its type
-- aliases only. The original is a 1,900-line declaration file that `tl gen`
-- reduces to the table below; the two namespaces are the ones the router
-- names, and nothing reads a field of either at run time.
return {components = {}, events = {}}
