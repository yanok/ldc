// RUN: not %ldc -c %s 2>&1 | FileCheck %s

/* TEST_OUTPUT:
---
fail_compilation/ctonly_class.d(26): Error: cannot call @__ctfe function `ctonly_class.C.f` from non-@__ctfe function `D main`
fail_compilation/ctonly_class.d(27): Error: cannot call @__ctfe function `ctonly_class.C.g` from non-@__ctfe function `D main`
fail_compilation/ctonly_class.d(29): Error: cannot call @__ctfe function `ctonly_class.CtOnly.this` from non-@__ctfe function `D main`
---
*/
class C {
    int v;
    this(int v_) { v = v_; }
    int f(int x) const @__ctfe { return x + v; }
    static int g(int x) @__ctfe { return x + 2; }
}

class CtOnly {
    int v;
    this(int v_) @__ctfe { v = v_; }
    int f(int x) const { return x + v; }
    static int g(int x) { return x + 2; }
}

void main() {
    C i = new C(1);
    int a = i.f(3);
    int v = C.g(2);

    auto cl = new CtOnly(5);
}
