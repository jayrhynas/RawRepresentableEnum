// The Swift Programming Language
// https://docs.swift.org/swift-book

@attached(member, names: named(rawValue), named(init(rawValue:)))
@attached(extension, conformances: RawRepresentable)
public macro RawRepresentable<RawValue>() = #externalMacro(module: "RawRepresentableEnumMacros", type: "RawRepresentableMacro")

@attached(peer)
public macro RawValue<RawValue>(_ value: RawValue) = #externalMacro(module: "RawRepresentableEnumMacros", type: "RawValueMacro")

@attached(peer)
public macro DefaultCase() = #externalMacro(module: "RawRepresentableEnumMacros", type: "DefaultCaseMacro")
