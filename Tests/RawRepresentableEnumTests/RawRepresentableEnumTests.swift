import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import MacroTesting

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(RawRepresentableEnumMacros)
import RawRepresentableEnumMacros

let testMacros: [String: Macro.Type] = [
    "RawRepresentable": RawRepresentableMacro.self,
    "RawValue": RawValueMacro.self,
    "DefaultCase": DefaultCaseMacro.self
]
#endif

final class EnumUnknownCaseTests: XCTestCase {
    override func invokeTest() {
        withMacroTesting(
            macros: testMacros
        ) {
            super.invokeTest()
        }
    }
    
    func testStringDefaultRawValues() throws {
        #if canImport(RawRepresentableEnumMacros)
        assertMacro {
            """
            @RawRepresentable<String>
            enum Foo {
                case a, b
                @DefaultCase
                case unknown(String)
            }
            """
        } expansion: {
            """
            enum Foo {
                case a, b
                case unknown(String)

                init(rawValue: String) {
                    self = switch rawValue {
                    case "a":
                        .a
                    case "b":
                        .b
                    default:
                        .unknown(rawValue)
                    }
                }

                var rawValue: String {
                    switch self {
                    case .a:
                        "a"
                    case .b:
                        "b"
                    case .unknown(let value):
                        value
                    }
                }
            }

            extension Foo: RawRepresentable {
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testIntManualRawValues() throws {
        #if canImport(RawRepresentableEnumMacros)
        assertMacro {
            """
            @RawRepresentable<Int>
            enum Foo {
                @RawValue(1)
                case a
                @RawValue(2)
                case b
                @DefaultCase
                case unknown(Int)
            }
            """
        } expansion: {
            """
            enum Foo {
                case a
                case b
                case unknown(Int)

                init(rawValue: Int) {
                    self = switch rawValue {
                    case 1:
                        .a
                    case 2:
                        .b
                    default:
                        .unknown(rawValue)
                    }
                }

                var rawValue: Int {
                    switch self {
                    case .a:
                        1
                    case .b:
                        2
                    case .unknown(let value):
                        value
                    }
                }
            }

            extension Foo: RawRepresentable {
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testNotEnum() {
        #if canImport(RawRepresentableEnumMacros)
        assertMacro {
            """
            @RawRepresentable<String>
            struct Foo {
            }
            """
        } diagnostics: {
            """
            @RawRepresentable<String>
            ╰─ 🛑 @RawRepresentable can only be applied to enums
            struct Foo {
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMultipleAttributes() {
        #if canImport(RawRepresentableEnumMacros)
        assertMacro {
            """
            @RawRepresentable<String>
            enum Foo {
            @RawValue("test")
            @DefaultCase
            case unknown(String)
            }
            """
        } diagnostics: {
            """
            @RawRepresentable<String>
            enum Foo {
            @RawValue("test")
            @DefaultCase
            case unknown(String)
                 ┬──────────────
                 ╰─ 🛑 Cannot have both @DefaultCase and @RawValue on an enum case
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMultipleDefaults() {
        #if canImport(RawRepresentableEnumMacros)
        assertMacro {
            """
            @RawRepresentable<String>
            enum Foo {
                @DefaultCase
                case unknown(String)
                @DefaultCase
                case custom(String)
            }
            """
        } diagnostics: {
            """
            @RawRepresentable<String>
            enum Foo {
                @DefaultCase
                case unknown(String)
                @DefaultCase
                case custom(String)
                     ┬─────
                     ╰─ 🛑 Multiple uses of @DefaultCase
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testNoDefault() {
        #if canImport(RawRepresentableEnumMacros)
        assertMacro {
            """
            @RawRepresentable<String>
            enum Foo {
                case a
            }
            """
        } diagnostics: {
            """
            @RawRepresentable<String>
            enum Foo {
                 ┬──
                 ╰─ 🛑 No case in enum is marked with @DefaultCase
                    ✏️ Add default case
                case a
            }
            """
        } fixes: {
            """
            @RawRepresentable<String>
            enum Foo {
                case a
            @DefaultCase
            case unknown(String)
            }
            """
        } expansion: {
            """
            enum Foo {
                case a
            case unknown(String)

                init(rawValue: String) {
                    self = switch rawValue {
                    case "a":
                        .a
                    default:
                        .unknown(rawValue)
                    }
                }

                var rawValue: String {
                    switch self {
                    case .a:
                        "a"
                    case .unknown(let value):
                        value
                    }
                }
            }

            extension Foo: RawRepresentable {
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testNoDefaultWithCandidate() {
        #if canImport(RawRepresentableEnumMacros)
        assertMacro {
            """
            @RawRepresentable<String>
            enum Foo {
                case custom(String)
            }
            """
        } diagnostics: {
            """
            @RawRepresentable<String>
            enum Foo {
                case custom(String)
                     ┬─────
                     ╰─ 🛑 No case in enum is marked with @DefaultCase
                        ✏️ Add default case
            }
            """
        } fixes: {
            """
            @RawRepresentable<String>
            enum Foo {
            @DefaultCase
                case custom(String)
            }
            """
        } expansion: {
            """
            enum Foo {
                case custom(String)

                init(rawValue: String) {
                    self = switch rawValue {

                    default:
                        .custom(rawValue)
                    }
                }

                var rawValue: String {
                    switch self {

                    case .custom(let value):
                        value
                    }
                }
            }

            extension Foo: RawRepresentable {
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testNoAssociatedValue() {
        #if canImport(RawRepresentableEnumMacros)
        assertMacro {
            """
            @RawRepresentable<String>
            enum Foo {
                @DefaultCase
                case unknown
            }
            """
        } diagnostics: {
            """
            @RawRepresentable<String>
            enum Foo {
                @DefaultCase
                case unknown
                     ┬──────
                     ╰─ 🛑 case 'unknown' must have exactly one associated value of type `String`
                        ✏️ Fix associated value
            }
            """
        } fixes: {
            """
            @RawRepresentable<String>
            enum Foo {
                @DefaultCase
                case unknown(String)
            }
            """
        } expansion: {
            """
            enum Foo {
                case unknown(String)

                init(rawValue: String) {
                    self = switch rawValue {

                    default:
                        .unknown(rawValue)
                    }
                }

                var rawValue: String {
                    switch self {

                    case .unknown(let value):
                        value
                    }
                }
            }

            extension Foo: RawRepresentable {
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testWrongAssociatedValue() {
        #if canImport(RawRepresentableEnumMacros)
        assertMacro {
            """
            @RawRepresentable<String>
            enum Foo {
                @DefaultCase
                case unknown(Int)
            }
            """
        } diagnostics: {
            """
            @RawRepresentable<String>
            enum Foo {
                @DefaultCase
                case unknown(Int)
                     ┬───────────
                     ╰─ 🛑 case 'unknown' must have exactly one associated value of type `String`
                        ✏️ Fix associated value
            }
            """
        } fixes: {
            """
            @RawRepresentable<String>
            enum Foo {
                @DefaultCase
                case unknown(String)
            }
            """
        } expansion: {
            """
            enum Foo {
                case unknown(String)

                init(rawValue: String) {
                    self = switch rawValue {

                    default:
                        .unknown(rawValue)
                    }
                }

                var rawValue: String {
                    switch self {

                    case .unknown(let value):
                        value
                    }
                }
            }

            extension Foo: RawRepresentable {
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testTooManyAssociatedValue() {
        #if canImport(RawRepresentableEnumMacros)
        assertMacro {
            """
            @RawRepresentable<String>
            enum Foo {
                @DefaultCase
                case unknown(String, Int)
            }
            """
        } diagnostics: {
            """
            @RawRepresentable<String>
            enum Foo {
                @DefaultCase
                case unknown(String, Int)
                     ┬───────────────────
                     ╰─ 🛑 case 'unknown' must have exactly one associated value of type `String`
                        ✏️ Fix associated value
            }
            """
        } fixes: {
            """
            @RawRepresentable<String>
            enum Foo {
                @DefaultCase
                case unknown(String)
            }
            """
        } expansion: {
            """
            enum Foo {
                case unknown(String)

                init(rawValue: String) {
                    self = switch rawValue {

                    default:
                        .unknown(rawValue)
                    }
                }

                var rawValue: String {
                    switch self {

                    case .unknown(let value):
                        value
                    }
                }
            }

            extension Foo: RawRepresentable {
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMissingRawValue() {
        #if canImport(RawRepresentableEnumMacros)
        assertMacro {
            """
            @RawRepresentable<Int>
            enum Foo {
                case a
                @DefaultCase
                case unknown(Int)
            }
            """
        } diagnostics: {
            """
            @RawRepresentable<Int>
            enum Foo {
                case a
                     ┬
                     ╰─ 🛑 case 'a' must specify a raw value
                        ✏️ Add raw value
                @DefaultCase
                case unknown(Int)
            }
            """
        } fixes: {
            """
            @RawRepresentable<Int>
            enum Foo {
                case a
                @DefaultCase
                case unknown(Int)
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testDuplicateRawValue() {
        #if canImport(RawRepresentableEnumMacros)
        assertMacro {
            """
            @RawRepresentable<Int>
            enum Foo {
                @RawValue(1)
                case a
                @RawValue(1)
                case b
                @DefaultCase
                case unknown(Int)
            }
            """
        } diagnostics: {
            """
            @RawRepresentable<Int>
            enum Foo {
                @RawValue(1)
                case a
                @RawValue(1)
                          ┬
                          ╰─ 🛑 Raw value for enum case is not unique
                case b
                @DefaultCase
                case unknown(Int)
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
