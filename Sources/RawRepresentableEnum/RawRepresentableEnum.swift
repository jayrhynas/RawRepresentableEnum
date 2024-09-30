// The Swift Programming Language
// https://docs.swift.org/swift-book

@attached(member, names: named(rawValue), named(init(rawValue:)))
@attached(extension, conformances: RawRepresentable)
public macro RawRepresentable<RawValue>(caseName: String = "unknown") = #externalMacro(module: "RawRepresentableEnumMacros", type: "RawRepresentableMacro")
