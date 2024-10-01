import RawRepresentableEnum

@RawRepresentable<Int>
enum Foo {
    @RawValue(1)
    case a
    @RawValue(2)
    case b
    @DefaultCase
    case unknown(Int)
}

print(Foo(rawValue: 1))        // a
print(Foo(rawValue: 2))        // b
print(Foo(rawValue: 3))        // unknown(3)

print(Foo.a.rawValue)          // 1
print(Foo.b.rawValue)          // 2
print(Foo.unknown(3).rawValue) // 3

// raw values are automatic for Strings
@RawRepresentable<String>
enum Bar {
    case a
    case b
    @DefaultCase
    case unknown(String)
}

print(Bar(rawValue: "a"))        // a
print(Bar(rawValue: "b"))        // b
print(Bar(rawValue: "c"))        // unknown(c)

print(Bar.a.rawValue)            // a
print(Bar.b.rawValue)            // b
print(Bar.unknown("c").rawValue) // c
