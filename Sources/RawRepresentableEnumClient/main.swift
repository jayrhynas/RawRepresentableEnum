import RawRepresentableEnum

@RawRepresentable<String>
enum Foo {
    case a
    case b
    case unknown(String)
}

print(Foo(rawValue: "a"))
print(Foo(rawValue: "b"))
print(Foo(rawValue: "test"))

print(Foo.a.rawValue)
print(Foo.b.rawValue)
print(Foo.unknown("test").rawValue)
