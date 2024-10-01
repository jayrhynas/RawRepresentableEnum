import SwiftDiagnostics
import SwiftSyntax

private let domain = "com.jayrhynas.defaultcase"

extension RawRepresentableMacro {
    struct Error: Swift.Error, DiagnosticMessage {
        let diagnosticID: MessageID
        let message: String
        let severity: DiagnosticSeverity
        
        let node: any SyntaxProtocol
        let notes: [SwiftDiagnostics.Note]
        let fixIts: [FixIt]
        
        init(id: String, message: String, severity: DiagnosticSeverity = .error, node: some SyntaxProtocol, notes: [SwiftDiagnostics.Note] = [], fixIts: [FixIt] = []) {
            self.diagnosticID = .init(domain: domain, id: id)
            self.message = message
            self.severity = severity
            self.node = node
            self.notes = notes
            self.fixIts = fixIts
        }
        
        var diagnostic: Diagnostic {
            .init(node: node, message: self, notes: notes, fixIts: fixIts)
        }
    }
    
    struct Note: NoteMessage {
        let message: String
        let noteID: MessageID
        
        init(id: String, message: String) {
            self.message = message
            self.noteID = .init(domain: domain, id: id)
        }
    }
    
    struct Fix: FixItMessage {
        let message: String
        let fixItID: MessageID
        
        init(id: String, message: String) {
            self.message = message
            self.fixItID = .init(domain: domain, id: id)
        }
    }
}

extension RawRepresentableMacro.Error {
    typealias Note = RawRepresentableMacro.Note
    typealias Fix = RawRepresentableMacro.Note
    
    static func notAnEnum(for decl: some DeclGroupSyntax) -> Self {
        .init(id: "notAnEnum",
              message: "@RawRepresentable can only be applied to enums",
              node: decl)
    }
    
    static func defaultAndRaw(for node: EnumCaseElementSyntax) -> Self {
        .init(id: "defaultAndRaw",
              message: "Cannot have both @DefaultCase and @RawValue on an enum case",
              node: node)
    }
    
    static func extraDefaultCase(for node: EnumCaseElementSyntax, existing: EnumCaseElementSyntax) -> Self {
        .init(id: "extraDefaultCase",
              message: "Multiple uses of @DefaultCase",
              node: node.name,
              notes: [
                .multipleDefault(existing: existing)
              ])
    }
    
    static func missingDefaultCase(rawValueType: some TypeSyntaxProtocol, for enumDecl: EnumDeclSyntax, candidate: EnumCaseDeclSyntax?) -> Self {
        .init(id: "missingDefaultCase",
              message: "No case in enum is marked with @DefaultCase",
              node: candidate?.elements.first?.name ?? enumDecl.name,
              fixIts: [
                .addDefaultCase(to: enumDecl, type: rawValueType, candidate: candidate)
              ])
    }
    
    static func wrongAssociatedValue(rawValueType: some TypeSyntaxProtocol, for caseElement: EnumCaseElementSyntax) -> Self {
        .init(id: "noAssociatedValue",
              message: "case '\(caseElement.name.trimmed)' must have exactly one associated value of type `\(rawValueType)`",
              node: caseElement,
              fixIts: [
                .fixAssociatedValue(for: caseElement, type: rawValueType)
              ])
    }
    
    static func missingRawValue(for info: RawRepresentableMacro.CaseInfo, in enumDecl: EnumDeclSyntax) -> Self {
        .init(id: "missingRawValue",
              message: "case '\(info.node.name.trimmed)' must specify a raw value",
              node: info.node,
              fixIts: [
                .addRawValue(to: info.node, case: info.case, enum: enumDecl)
              ])
    }
    
    static func duplicateRawValues(for node: Syntax, existing: Syntax) -> Self {
        .init(id: "duplicateRawValues", message: "Raw value for enum case is not unique", node: node, notes: [
            .duplicateRawValues(existing: existing)
        ])
    }
}

extension RawRepresentableMacro.Fix {
    static let addDefaultCase = Self(id: "addDefaultCase", message: "Add default case")
    static let fixAssociatedValue = Self(id: "fixAssociatedValue", message: "Fix associated value")
    static let addRawValue = Self(id: "addRawValue", message: "Add raw value")
}

extension FixIt {
    static func addDefaultCase(to enumDecl: EnumDeclSyntax, type rawValueType: some TypeSyntaxProtocol, candidate: EnumCaseDeclSyntax?) -> FixIt {
        let oldNode: any SyntaxProtocol
        let newNode: any SyntaxProtocol
        
        if let candidate {
            var newCandidate = candidate
            newCandidate.attributes.append(.attribute("@DefaultCase").with(\.leadingTrivia, .newline))
            
            oldNode = candidate
            newNode = newCandidate
        } else {
            var newMembers = enumDecl.memberBlock
            newMembers.members.append(
                .init(leadingTrivia: .newline, decl: ("@DefaultCase\ncase unknown(\(rawValueType))" as DeclSyntax).cast(EnumCaseDeclSyntax.self))
            )
            oldNode = enumDecl.memberBlock
            newNode = newMembers
        }
        
        return .replace(message: RawRepresentableMacro.Fix.addDefaultCase, oldNode: oldNode, newNode: newNode)
    }
    
    static func fixAssociatedValue(for caseElement: EnumCaseElementSyntax, type rawValueType: some TypeSyntaxProtocol) -> FixIt {
        var newNode = caseElement
        newNode.parameterClause = .init(parameters: [.init(type: rawValueType)])
        return .replace(message: RawRepresentableMacro.Fix.fixAssociatedValue, oldNode: caseElement, newNode: newNode)
    }
    
    static func addRawValue(to caseElement: EnumCaseElementSyntax, case caseDecl: EnumCaseDeclSyntax, enum enumDecl: EnumDeclSyntax) -> FixIt {
        var newEnum = enumDecl
        
        let caseIdx = newEnum.memberBlock.members.firstIndex {
            $0.decl.cast(EnumCaseDeclSyntax.self) == caseDecl
        }!
        
        var oldCase = newEnum.memberBlock.members[caseIdx].decl.cast(EnumCaseDeclSyntax.self)
        defer {
            newEnum.memberBlock.members[caseIdx].decl = DeclSyntax(oldCase)
        }
        
        let elementIdx = oldCase.elements.firstIndex(of: caseElement)!
        
        if elementIdx == oldCase.elements.startIndex {
            oldCase.attributes.append(
                .attribute("@RawValue(<#value#>)")
                .with(\.leadingTrivia, .newline)
            )
        } else {
            if elementIdx == oldCase.elements.index(before: oldCase.elements.endIndex) {
                let previousIdx = oldCase.elements.index(before: elementIdx)
                oldCase.elements[previousIdx].trailingComma = nil
            }
            oldCase.elements.remove(at: elementIdx)
            
            let newCase = MemberBlockItemSyntax(
                leadingTrivia: .newline,
                decl: """
                    @RawValue(<#value#>)
                    case \(caseElement.name)
                    """ as DeclSyntax
            )
            
            newEnum.memberBlock.members.insert(
                newCase,
                at: newEnum.memberBlock.members.index(after: caseIdx)
            )
        }
        
        return .replace(message: RawRepresentableMacro.Fix.addRawValue, oldNode: enumDecl, newNode: newEnum)
    }
}

extension RawRepresentableMacro.Note {
    static let multipleDefault = Self(id: "multipleDefault", message: "@DefaultCase previously used here")
    static let duplicateRawValues = Self(id: "duplicateRawValues", message: "Raw value previously used here")
}

extension Note {
    static func multipleDefault(existing: some SyntaxProtocol) -> Note {
        .init(node: Syntax(existing), message: RawRepresentableMacro.Note.multipleDefault)
    }
    
    static func duplicateRawValues(existing: some SyntaxProtocol) -> Note {
        .init(node: Syntax(existing), message: RawRepresentableMacro.Note.duplicateRawValues)
    }
}

extension DiagnosticsError {
    init(_ error: RawRepresentableMacro.Error) {
        self.init(diagnostics: [error.diagnostic])
    }
}
