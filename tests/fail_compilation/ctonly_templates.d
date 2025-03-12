// RUN: not %ldc -c %s 2>&1 | FileCheck %s

/* TEST_OUTPUT:
---
fail_compilation/ctonly_templates.d(23): Error: cannot call @__ctfe function `std.array.array!(MapResult!(f, int[])).array` from non-@__ctfe function `D main`
fail_compilation/ctonly_templates.d(23):        `std.array.array!(MapResult!(f, int[])).array` was inferred to be @__ctfe because it (transitively) calls `ctonly_templates.f`
---
*/
import std.algorithm.iteration;
import std.array;

int f(int x) @__ctfe
{
    return x + 1;
}

enum a = map!f([1, 2, 3]);

import std.stdio;

void main() {
    // That fails, because `f` is called internally.
    writeln(a.array);
}
