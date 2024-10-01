import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct RawRepresentableMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let rawValueType = parseRawValue(for: node)
        
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw DiagnosticsError(.notAnEnum(for: declaration))
        }
        
        let (defaultCase, otherCases) = try parseCases(
            in: enumDecl,
            rawValueType: rawValueType
        )
        
        var errors: [Error] = []
        
        let casesAndValues: [(name: String, value: Syntax)] = otherCases.compactMap { item in
            let name = item.node.name.trimmed.text
            
            if let rawValue = item.rawValue {
                return (name, rawValue)
            } else if rawValueType.name.text == "String" {
                return (name, Syntax("\"\(raw: name)\"" as ExprSyntax))
            } else {
                errors.append(.missingRawValue(for: item, in: enumDecl))
                return nil
            }
        }
        
        if !errors.isEmpty {
            throw DiagnosticsError(diagnostics: errors.map(\.diagnostic))
        }
        
        let initCases = casesAndValues.map {
            "case \($0.value): .\($0.name)"
        }.joined(separator: "\n")
        
        let rawValueCases = casesAndValues.map {
            "case .\($0.name): \($0.value)"
        }.joined(separator: "\n")
        
        return [
            """
            init(rawValue: \(raw: rawValueType.name.text)) {
                self = switch rawValue {
                \(raw: initCases)
                default:
                    .\(raw: defaultCase.name.trimmed)(rawValue)
                }
            }
            """,
            """
            var rawValue: \(raw: rawValueType.name.text) {
                switch self {
                \(raw: rawValueCases)
                case .\(raw: defaultCase.name.trimmed)(let value):
                    value
                }
            }
            """
        ]
    }
    
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        try [ExtensionDeclSyntax("extension \(type.trimmed): RawRepresentable {}")]
    }
    
    private static func parseRawValue(for node: AttributeSyntax) -> IdentifierTypeSyntax {
        let attrGenerics = node.attributeName.cast(IdentifierTypeSyntax.self).genericArgumentClause!.arguments
        return attrGenerics.first!.argument.cast(IdentifierTypeSyntax.self)
    }
    
    typealias CaseInfo = (node: EnumCaseElementSyntax, case: EnumCaseDeclSyntax, rawValue: Syntax?)
    
    private static func parseCases(in enumDecl: EnumDeclSyntax, rawValueType: IdentifierTypeSyntax) throws -> (defaultCase: EnumCaseElementSyntax, otherCases: [CaseInfo]) {
        var defaultCase: EnumCaseElementSyntax?
        var otherCases: [CaseInfo] = []
        
        func isValidDefault(_ element: EnumCaseElementSyntax) -> Bool {
            if let params = element.parameterClause?.parameters,
                      params.count == 1,
                      let associatedValueType = params.first!.type.as(IdentifierTypeSyntax.self),
                      rawValueType.name.text == associatedValueType.name.text
            {
                return true
            } else {
                return false
            }
        }
        
        var errors: [Error] = []
        
        // check each case looking for relevant attributes
        for item in enumDecl.memberBlock.members {
            let caseDecl = item.decl.cast(EnumCaseDeclSyntax.self)
            
            if caseDecl.attribute(named: "DefaultCase") != nil {
                // if there are multiple case names on one line, assume the attribute applies to the first
                let first = caseDecl.elements.first!
                
                if let defaultCase {
                    // diagnose 2nd+ usage of DefaultCase
                    errors.append(.extraDefaultCase(for: first, existing: defaultCase))
                } else {
                    // record first usage of DefaultCase
                    defaultCase = first
                    // diagnose if there's something wrong with it (too few/too many/wrong associated value)
                    if !isValidDefault(first) {
                        errors.append(.wrongAssociatedValue(rawValueType: rawValueType, for: first))
                    }
                }
                
                // diagnose a value having both DefaultCase and RawValue
                if caseDecl.attribute(named: "RawValue") != nil {
                    errors.append(.defaultAndRaw(for: first))
                }
                
                // any other cases on this line are assumed to have no attributes
                for item in caseDecl.elements.dropFirst() {
                    otherCases.append((item, caseDecl, nil))
                }
            } else if let attribute = caseDecl.attribute(named: "RawValue") {
                // if there are multiple case names on one line, assume the attribute applies to the first
                let first = caseDecl.elements.first!
                // raw value should be the single argument
                let rawValue = attribute.arguments!.cast(LabeledExprListSyntax.self).first!.expression
                
                otherCases.append((first, caseDecl, Syntax(rawValue)))
                
                // any other cases on this line are assumed to have no attributes (and therefore no raw value)
                for item in caseDecl.elements.dropFirst() {
                    otherCases.append((item, caseDecl, nil))
                }
            } else {
                // for a case declaration with no attributes, just add all the cases
                otherCases.append(contentsOf: caseDecl.elements.map { ($0, caseDecl, nil) })
            }
        }

        // diagnose duplicate raw values
        var rawValues: [String: Syntax] = [:]
        
        for other in otherCases {
            guard let rawValue = other.rawValue else { continue }
            
            let stringValue = "\(rawValue)"
            if let existing = rawValues[stringValue] {
                errors.append(.duplicateRawValues(for: rawValue, existing: existing))
            } else {
                rawValues[stringValue] = rawValue
            }
        }
        
        // if we don't have a default case, diagnose it along with any gathered errors
        guard let defaultCase else {
            let candidate = otherCases.first(where: { isValidDefault($0.node) })
            errors.append(.missingDefaultCase(
                rawValueType: rawValueType,
                for: enumDecl,
                candidate: candidate?.case
            ))
            throw DiagnosticsError(diagnostics: errors.map(\.diagnostic))
        }
        
        // diagnose any errors we gathered
        if !errors.isEmpty {
            throw DiagnosticsError(diagnostics: errors.map(\.diagnostic))
        }
        
        // otherwise, everything should be ok
        return (defaultCase, otherCases)
    }
    
}

extension EnumCaseDeclSyntax {
    func attribute(named: String) -> AttributeSyntax? {
        self.attributes.lazy.compactMap {
            guard let attr = $0.as(AttributeSyntax.self) else {
                return nil
            }
            return attr.attributeName.cast(IdentifierTypeSyntax.self).name.trimmed.text == named ? attr : nil
        }.first
    }
}

public struct RawValueMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}

public struct DefaultCaseMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}

@main
struct RawRepresentableEnumPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        RawRepresentableMacro.self,
        RawValueMacro.self,
        DefaultCaseMacro.self
    ]
}
