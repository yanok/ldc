
/* Compiler implementation of the D programming language
 * Copyright (C) 1999-2022 by The D Language Foundation, All Rights Reserved
 * written by Walter Bright
 * https://www.digitalmars.com
 * Distributed under the Boost Software License, Version 1.0.
 * https://www.boost.org/LICENSE_1_0.txt
 * https://github.com/dlang/dmd/blob/master/src/dmd/aggregate.h
 */

#pragma once

#include "dsymbol.h"
#include "objc.h"

class AliasThis;
class Identifier;
class Type;
class TypeFunction;
class Expression;
class FuncDeclaration;
class CtorDeclaration;
class DtorDeclaration;
class InterfaceDeclaration;
class TypeInfoClassDeclaration;
class VarDeclaration;

enum class Sizeok : uint8_t
{
    none,         // size of aggregate is not yet able to compute
    fwd,          // size of aggregate is ready to compute
    inProcess,    // in the midst of computing the size
    done          // size of aggregate is set correctly
};

enum class Baseok : uint8_t
{
    none,         // base classes not computed yet
    in,           // in process of resolving base classes
    done,         // all base classes are resolved
    semanticdone  // all base classes semantic done
};

enum class ThreeState : uint8_t
{
    none,         // value not yet computed
    no,           // value is false
    yes,          // value is true
};

FuncDeclaration *search_toString(StructDeclaration *sd);

enum class ClassKind : uint8_t
{
  /// the aggregate is a d(efault) struct/class/interface
  d,
  /// the aggregate is a C++ struct/class/interface
  cpp,
  /// the aggregate is an Objective-C class/interface
  objc,
  /// the aggregate is a C struct
  c,
};

struct MangleOverride
{
    Dsymbol *agg;
    Identifier *id;
};

class AggregateDeclaration : public ScopeDsymbol
{
public:
    Type *type;
    StorageClass storage_class;
    unsigned structsize;        // size of struct
    unsigned alignsize;         // size of struct for alignment purposes
    VarDeclarations fields;     // VarDeclaration fields
    Dsymbol *deferred;          // any deferred semantic2() or semantic3() symbol

    ClassKind classKind;        // specifies the linkage type
    CPPMANGLE cppmangle;

    // overridden symbol with pragma(mangle, "...")
    MangleOverride *mangleOverride;
    /* !=NULL if is nested
     * pointing to the dsymbol that directly enclosing it.
     * 1. The function that enclosing it (nested struct and class)
     * 2. The class that enclosing it (nested class only)
     * 3. If enclosing aggregate is template, its enclosing dsymbol.
     * See AggregateDeclaraton::makeNested for the details.
     */
    Dsymbol *enclosing;
    VarDeclaration *vthis;      // 'this' parameter if this aggregate is nested
    VarDeclaration *vthis2;     // 'this' parameter if this aggregate is a template and is nested
    // Special member functions
    FuncDeclarations invs;              // Array of invariants
    FuncDeclaration *inv;               // invariant

    Dsymbol *ctor;                      // CtorDeclaration or TemplateDeclaration

    // default constructor - should have no arguments, because
    // it would be stored in TypeInfo_Class.defaultConstructor
    CtorDeclaration *defaultCtor;

    AliasThis *aliasthis;       // forward unresolved lookups to aliasthis

    DtorDeclarations userDtors; // user-defined destructors (`~this()`) - mixins can yield multiple ones
    DtorDeclaration *aggrDtor;  // aggregate destructor calling userDtors and fieldDtor (and base class aggregate dtor for C++ classes)
    DtorDeclaration *dtor;      // the aggregate destructor exposed as `__xdtor` alias
                                // (same as aggrDtor, except for C++ classes with virtual dtor on Windows)
    DtorDeclaration *tidtor;    // aggregate destructor used in TypeInfo (must have extern(D) ABI)
    DtorDeclaration *fieldDtor; // function destructing (non-inherited) fields

    Expression *getRTInfo;      // pointer to GC info generated by object.RTInfo(this)

    Visibility visibility;
    bool noDefaultCtor;         // no default construction
    bool disableNew;            // disallow allocations using `new`
    Sizeok sizeok;              // set when structsize contains valid data

    virtual Scope *newScope(Scope *sc);
    void setScope(Scope *sc) override final;
    size_t nonHiddenFields();
    bool determineSize(const Loc &loc);
    virtual void finalizeSize() = 0;
    uinteger_t size(const Loc &loc) override final;
    bool fill(const Loc &loc, Expressions &elements, bool ctorinit);
    Type *getType() override final;
    bool isDeprecated() const override final; // is aggregate deprecated?
    void setDeprecated();
    bool isNested() const;
    bool isExport() const override final;
    Dsymbol *searchCtor();

    Visibility visible() override final;

    // 'this' type
    Type *handleType() { return type; }

    bool hasInvariant();

    // Back end
    void *sinit;

    AggregateDeclaration *isAggregateDeclaration() override final { return this; }
    void accept(Visitor *v) override { v->visit(this); }
};

struct StructFlags
{
    enum Type
    {
        none = 0x0,
        hasPointers = 0x1  // NB: should use noPointers as in ClassFlags
    };
};

class StructDeclaration : public AggregateDeclaration
{
public:
    FuncDeclarations postblits; // Array of postblit functions
    FuncDeclaration *postblit;  // aggregate postblit

    FuncDeclaration *xeq;       // TypeInfo_Struct.xopEquals
    FuncDeclaration *xcmp;      // TypeInfo_Struct.xopCmp
    FuncDeclaration *xhash;     // TypeInfo_Struct.xtoHash
    static FuncDeclaration *xerreq;      // object.xopEquals
    static FuncDeclaration *xerrcmp;     // object.xopCmp

    // ABI-specific type(s) if the struct can be passed in registers
    TypeTuple *argTypes;

    structalign_t alignment;    // alignment applied outside of the struct
    ThreeState ispod;           // if struct is POD
private:
    uint8_t bitFields;
public:
    static StructDeclaration *create(const Loc &loc, Identifier *id, bool inObject);
    StructDeclaration *syntaxCopy(Dsymbol *s) override;
    Dsymbol *search(const Loc &loc, Identifier *ident, int flags = SearchLocalsOnly) override final;
    const char *kind() const override;
    void finalizeSize() override final;
    bool isPOD();
    bool zeroInit() const;          // !=0 if initialize with 0 fill
    bool zeroInit(bool v);
    bool hasIdentityAssign() const; // true if has identity opAssign
    bool hasIdentityAssign(bool v);
    bool hasBlitAssign() const;     // true if opAssign is a blit
    bool hasBlitAssign(bool v);
    bool hasIdentityEquals() const; // true if has identity opEquals
    bool hasIdentityEquals(bool v);
    bool hasNoFields() const;       // has no fields
    bool hasNoFields(bool v);
    bool hasCopyCtor() const;       // copy constructor
    bool hasCopyCtor(bool v);
    // Even if struct is defined as non-root symbol, some built-in operations
    // (e.g. TypeidExp, NewExp, ArrayLiteralExp, etc) request its TypeInfo.
    // For those, today TypeInfo_Struct is generated in COMDAT.
    bool requestTypeInfo() const;
    bool requestTypeInfo(bool v);

    StructDeclaration *isStructDeclaration() override final { return this; }
    void accept(Visitor *v) override { v->visit(this); }

    unsigned numArgTypes() const;
    Type *argType(unsigned index);
    bool hasRegularCtor(bool checkDisabled = false);
};

class UnionDeclaration final : public StructDeclaration
{
public:
    UnionDeclaration *syntaxCopy(Dsymbol *s) override;
    const char *kind() const override;

    UnionDeclaration *isUnionDeclaration() override { return this; }
    void accept(Visitor *v) override { v->visit(this); }
};

struct BaseClass
{
    Type *type;                         // (before semantic processing)

    ClassDeclaration *sym;
    unsigned offset;                    // 'this' pointer offset
    // for interfaces: Array of FuncDeclaration's
    // making up the vtbl[]
    FuncDeclarations vtbl;

    DArray<BaseClass> baseInterfaces;   // if BaseClass is an interface, these
                                        // are a copy of the InterfaceDeclaration::interfaces

    bool fillVtbl(ClassDeclaration *cd, FuncDeclarations *vtbl, int newinstance);
};

struct ClassFlags
{
    enum Type
    {
        none = 0x0,
        isCOMclass = 0x1,
        noPointers = 0x2,
        hasOffTi = 0x4,
        hasCtor = 0x8,
        hasGetMembers = 0x10,
        hasTypeInfo = 0x20,
        isAbstract = 0x40,
        isCPPclass = 0x80,
        hasDtor = 0x100
    };
};

class ClassDeclaration : public AggregateDeclaration
{
public:
    static ClassDeclaration *object;
    static ClassDeclaration *throwable;
    static ClassDeclaration *exception;
    static ClassDeclaration *errorException;
    static ClassDeclaration *cpp_type_info_ptr;

    ClassDeclaration *baseClass;        // NULL only if this is Object
    FuncDeclaration *staticCtor;
    FuncDeclaration *staticDtor;
    Dsymbols vtbl;                      // Array of FuncDeclaration's making up the vtbl[]
    Dsymbols vtblFinal;                 // More FuncDeclaration's that aren't in vtbl[]

    BaseClasses *baseclasses;           // Array of BaseClass's; first is super,
                                        // rest are Interface's

    DArray<BaseClass*> interfaces;      // interfaces[interfaces_dim] for this class
                                        // (does not include baseClass)

    BaseClasses *vtblInterfaces;        // array of base interfaces that have
                                        // their own vtbl[]

    TypeInfoClassDeclaration *vclassinfo;       // the ClassInfo object for this ClassDeclaration
    bool com;                           // true if this is a COM class (meaning it derives from IUnknown)
    bool stack;                         // true if this is a scope class
    int cppDtorVtblIndex;               // slot reserved for the virtual destructor [extern(C++)]
    bool inuse;                         // to prevent recursive attempts

    ThreeState isabstract;              // if abstract class
    Baseok baseok;                      // set the progress of base classes resolving
    ObjcClassDeclaration objc;          // Data for a class declaration that is needed for the Objective-C integration
    Symbol *cpp_type_info_ptr_sym;      // cached instance of class Id.cpp_type_info_ptr

    static ClassDeclaration *create(const Loc &loc, Identifier *id, BaseClasses *baseclasses, Dsymbols *members, bool inObject);
    const char *toPrettyChars(bool QualifyTypes = false) override;
    ClassDeclaration *syntaxCopy(Dsymbol *s) override;
    Scope *newScope(Scope *sc) override;
    bool isBaseOf2(ClassDeclaration *cd);

    #define OFFSET_RUNTIME 0x76543210
    #define OFFSET_FWDREF 0x76543211
    virtual bool isBaseOf(ClassDeclaration *cd, int *poffset);

    bool isBaseInfoComplete();
    Dsymbol *search(const Loc &loc, Identifier *ident, int flags = SearchLocalsOnly) override final;
    ClassDeclaration *searchBase(Identifier *ident);
    void finalizeSize() override;
    bool hasMonitor();
    bool isFuncHidden(FuncDeclaration *fd);
    FuncDeclaration *findFunc(Identifier *ident, TypeFunction *tf);
    bool isCOMclass() const;
    virtual bool isCOMinterface() const;
    bool isCPPclass() const;
    virtual bool isCPPinterface() const;
    bool isAbstract();
    virtual int vtblOffset() const;
    const char *kind() const override;

    void addLocalClass(ClassDeclarations *) override final;
    void addObjcSymbols(ClassDeclarations *classes, ClassDeclarations *categories) override final;

    // Back end
    Dsymbol *vtblsym;
    Dsymbol *vtblSymbol();

    ClassDeclaration *isClassDeclaration() override final { return (ClassDeclaration *)this; }
    void accept(Visitor *v) override { v->visit(this); }
};

class InterfaceDeclaration final : public ClassDeclaration
{
public:
    InterfaceDeclaration *syntaxCopy(Dsymbol *s) override;
    Scope *newScope(Scope *sc) override;
    bool isBaseOf(ClassDeclaration *cd, int *poffset) override;
    const char *kind() const override;
    int vtblOffset() const override;
    bool isCPPinterface() const override;
    bool isCOMinterface() const override;

    InterfaceDeclaration *isInterfaceDeclaration() override { return this; }
    void accept(Visitor *v) override { v->visit(this); }
};
