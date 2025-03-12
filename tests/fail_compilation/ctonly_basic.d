// RUN: not %ldc -c %s 2>&1 | FileCheck %s

/* TEST_OUTPUT:
---
fail_compilation/ctonly_basic.d(25): Error: cannot call @__ctfe function `ctonly_basic.f` from non-@__ctfe function `D main`
fail_compilation/ctonly_basic.d(25): Error: cannot call @__ctfe function `ctonly_basic.g!2.g` from non-@__ctfe function `D main`
fail_compilation/ctonly_basic.d(25): Error: cannot take address of @__ctfe function `f`
fail_compilation/ctonly_basic.d(25): Error: cannot take address of @__ctfe function `g`
---
*/

int f(int x, int y) @__ctfe {
    return x + y;
}

int g(int x)(int y) @__ctfe {
    return x + y;
}

alias gf = g!2;

import std.stdio;

void main() {
    writeln(f(2, 4), gf(0), &f, &gf);
}
