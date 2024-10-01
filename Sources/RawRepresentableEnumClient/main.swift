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
