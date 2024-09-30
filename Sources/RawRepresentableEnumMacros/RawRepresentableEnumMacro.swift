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
            throw Error.notAnEnum(for: declaration).diagnostic
        }
        
        let caseName: String
        if let arguments = node.arguments {
            let expr = arguments.cast(LabeledExprListSyntax.self).first!.expression
            guard let name = expr.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
                throw Error.caseNameLiteral(for: expr).diagnostic
            }
            caseName = name
        } else {
            caseName = "unknown"
        }
        
        guard let (defaultCase, otherCases) = parseCases(defaultCase: caseName, in: enumDecl) else {
            throw Error.missingDefaultCase(name: caseName, rawValueType: rawValueType, for: enumDecl).diagnostic
        }
        
        guard let params = defaultCase.parameterClause?.parameters,
              params.count == 1,
              let associatedValueType = params.first?.type.as(IdentifierTypeSyntax.self),
              rawValueType.name.text == associatedValueType.name.text
        else {
            throw Error.wrongAssociatedValue(rawValueType: rawValueType, for: defaultCase).diagnostic
        }

        let casesAndValues: [(name: String, value: ExprSyntax)] = try otherCases.map { item in
            let name = item.name.trimmed.text
            if let rawValue = item.rawValue?.value {
                return (name, rawValue)
            } else if rawValueType.name.text == "String" {
                return (name, "\"\(raw: item.name.text)\"")
            } else {
                throw MacroExpansionErrorMessage("No raw value for case \(name)")
            }
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
                    .\(raw: caseName)(rawValue)
                }
            }
            """,
            """
            var rawValue: \(raw: rawValueType.name.text) {
                switch self {
                \(raw: rawValueCases)
                case .\(raw: caseName)(let value):
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
    
    private static func parseCases(defaultCase defaultCaseName: String, in enumDecl: EnumDeclSyntax) -> (defaultCase: EnumCaseElementSyntax, otherCases: [EnumCaseElementSyntax])? {
        var defaultCase: EnumCaseElementSyntax?
        var otherCases: [EnumCaseElementSyntax] = []
        
        for item in enumDecl.memberBlock.members {
            for caseDecl in item.decl.cast(EnumCaseDeclSyntax.self).elements {
                if caseDecl.name.trimmed.text == defaultCaseName {
                    defaultCase = caseDecl
                } else {
                    otherCases.append(caseDecl)
                }
            }
        }
        
        guard let defaultCase else { return nil }
        
        return (defaultCase, otherCases)
    }
    
    struct Error: Swift.Error, DiagnosticMessage {
        let diagnosticID: MessageID
        let message: String
        let severity: DiagnosticSeverity
        let node: any SyntaxProtocol
        let fixIts: [FixIt]
        
        init(id: String, message: String, severity: DiagnosticSeverity = .error, node: some SyntaxProtocol, fixIts: [FixIt] = []) {
            self.diagnosticID = .init(domain: "com.jayrhynas.defaultcase", id: id)
            self.message = message
            self.severity = severity
            self.node = node
            self.fixIts = fixIts
        }
        
        struct Fix: FixItMessage {
            let message: String
            let fixItID: SwiftDiagnostics.MessageID
            
            init(id: String, message: String) {
                self.message = message
                self.fixItID = .init(domain: "com.jayrhynas.defaultcase", id: id)
            }
            
            static let addDefaultCase = Fix(id: "addDefaultCase", message: "Add default case")
            static let fixAssociatedValue = Fix(id: "fixAssociatedValue", message: "Fix associated value")
        }
        
        var diagnostic: DiagnosticsError {
            DiagnosticsError(diagnostics: [.init(node: node, message: self, fixIts: fixIts)])
        }
        
        static func notAnEnum(for decl: some DeclGroupSyntax) -> Self {
            .init(id: "notAnEnum", message: "@DefaultCase can only be applied to enums", node: decl)
        }
        
        static func caseNameLiteral(for expr: ExprSyntax) -> Self {
            .init(id: "caseNameLiteral", message: "`caseName` must be a string literal", node: expr)
        }

        static func missingDefaultCase(name: String, rawValueType: IdentifierTypeSyntax, for node: EnumDeclSyntax) -> Self {
            var newMembers = node.memberBlock
            newMembers.members.append(
                .init(leadingTrivia: .newline, decl: ("case \(raw: name)(\(rawValueType))" as DeclSyntax).cast(EnumCaseDeclSyntax.self))
            )
            return .init(id: "missingDefaultCase", message: "No `case \(name)(\(rawValueType.name.trimmed))` in enum", node: node.name, fixIts: [
                .replace(message: Fix.addDefaultCase, oldNode: node.memberBlock, newNode: newMembers)
            ])
        }
        
        static func wrongAssociatedValue(rawValueType: IdentifierTypeSyntax, for node: EnumCaseElementSyntax) -> Self {
            var newNode = node
            newNode.parameterClause = .init(parameters: [.init(type: rawValueType)])
            
            return .init(id: "noAssociatedValue", message: "`case \(node.name.trimmed)` must have exactly one associated value of type `\(rawValueType)`", node: node, fixIts: [
                .replace(message: Fix.fixAssociatedValue, oldNode: node, newNode: newNode)
            ])
        }
    }
    
}

@main
struct RawRepresentableEnumPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        RawRepresentableMacro.self,
    ]
}
