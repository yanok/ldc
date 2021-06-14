// Test the different modes of -cov instrumentation code

// RUN: %ldc --cov                                                 --output-ll -of=%t.ll         %s && FileCheck --check-prefix=ALL --check-prefix=DEFAULT %s < %t.ll
// RUN: %ldc --cov --cov-increment=boolean --cov-increment=default --output-ll -of=%t.default.ll %s && FileCheck --check-prefix=ALL --check-prefix=DEFAULT %s < %t.default.ll

// RUN: %ldc --cov --cov-increment=atomic     --output-ll -of=%t.atomic.ll    %s && FileCheck --check-prefix=ALL --check-prefix=ATOMIC    %s < %t.atomic.ll
// RUN: %ldc --cov --cov-increment=non-atomic --output-ll -of=%t.nonatomic.ll %s && FileCheck --check-prefix=ALL --check-prefix=NONATOMIC %s < %t.nonatomic.ll
// RUN: %ldc --cov --cov-increment=boolean    --output-ll -of=%t.boolean.ll   %s && FileCheck --check-prefix=ALL --check-prefix=BOOLEAN   %s < %t.boolean.ll

void f2()
{
}

// ALL-LABEL: define{{.*}} void @{{.*}}f1
void f1()
{
    // DEFAULT: atomicrmw add {{.*}}@_d_cover_data, {{.*}} monotonic
    // ATOMIC: atomicrmw add {{.*}}@_d_cover_data, {{.*}} monotonic
    // NONATOMIC: load {{.*}}@_d_cover_data, {{.*}} !nontemporal
    // NONATOMIC: store {{.*}}@_d_cover_data, {{.*}} !nontemporal
    // BOOLEAN: store {{.*}}@_d_cover_data, {{.*}} !nontemporal
    // ALL-LABEL: call{{.*}} @{{.*}}f2
    f2();
}

void main()
{
    foreach (i; 0..10)
        f1();
}
