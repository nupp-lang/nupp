/* Test fixture for nupp import-c: one declaration the C parser will not take,
   among several it will. The shape a real header has when a type it lays a
   struct out from is defined in a header this import filtered away. */

struct partialOpaque;

struct partialHolder {
    struct partialOpaque inner;
};

int partial_add(int a, int b);
double partial_scale(double v);
