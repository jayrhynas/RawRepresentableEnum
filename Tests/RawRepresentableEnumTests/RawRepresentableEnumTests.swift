import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(RawRepresentableEnumMacros)
import RawRepresentableEnumMacros

let testMacros: [String: Macro.Type] = [
    "RawRepresentable": RawRepresentableMacro.self,
]
#endif

final class EnumUnknownCaseTests: XCTestCase {
    func testMacro() throws {
        #if canImport(EnumUnknownCaseMacros)
        assertMacroExpansion(
            """
            @RawRepresentable<String>
            enum Foo {
                case a
                case b
                case unknown(String)
            }
            """,
            expandedSource: """
            enum Foo {
                case a
                case b
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
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
