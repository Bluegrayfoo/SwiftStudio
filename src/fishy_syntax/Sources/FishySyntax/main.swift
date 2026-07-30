import Foundation
import SwiftDiagnostics
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

struct FishyDiagnostic: Codable {
  let line: Int
  let column: Int
  let message: String
}

struct FishySymbol: Codable {
  let kind: String
  let name: String
  let line: Int
}

struct FishyReport: Codable {
  let ok: Bool
  let diagnostics: [FishyDiagnostic]
  let symbols: [FishySymbol]
  let summary: [String]
}

final class SymbolCollector: SyntaxVisitor {
  private let converter: SourceLocationConverter
  var symbols: [FishySymbol] = []

  init(converter: SourceLocationConverter) {
    self.converter = converter
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    let loc = converter.location(for: node.positionAfterSkippingLeadingTrivia)
    symbols.append(FishySymbol(kind: "struct", name: node.name.text, line: loc.line))
    return .visitChildren
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    let loc = converter.location(for: node.positionAfterSkippingLeadingTrivia)
    symbols.append(FishySymbol(kind: "class", name: node.name.text, line: loc.line))
    return .visitChildren
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    let loc = converter.location(for: node.positionAfterSkippingLeadingTrivia)
    symbols.append(FishySymbol(kind: "function", name: node.name.text, line: loc.line))
    return .visitChildren
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    let loc = converter.location(for: node.positionAfterSkippingLeadingTrivia)
    for binding in node.bindings {
      if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
        symbols.append(FishySymbol(kind: node.bindingSpecifier.text, name: identifier.identifier.text, line: loc.line))
      }
    }
    return .visitChildren
  }

  override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
    let loc = converter.location(for: node.positionAfterSkippingLeadingTrivia)
    symbols.append(FishySymbol(kind: "macro", name: "#\(node.macroName.text)", line: loc.line))
    return .visitChildren
  }
}

let args = CommandLine.arguments.dropFirst()
let source: String
if let first = args.first {
  source = (try? String(contentsOfFile: first, encoding: .utf8)) ?? ""
} else {
  let data = FileHandle.standardInput.readDataToEndOfFile()
  source = String(data: data, encoding: .utf8) ?? ""
}

let tree = Parser.parse(source: source)
let converter = SourceLocationConverter(fileName: "ContentView.swift", tree: tree)
let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: tree).map { diagnostic in
  let loc = diagnostic.location(converter: converter)
  return FishyDiagnostic(line: loc.line, column: loc.column, message: diagnostic.message)
}

let collector = SymbolCollector(converter: converter)
collector.walk(tree)

var summary: [String] = []
if diagnostics.isEmpty {
  summary.append("SwiftSyntax parsed the file without parser diagnostics.")
} else {
  summary.append("SwiftSyntax found \(diagnostics.count) parser issue\(diagnostics.count == 1 ? "" : "s").")
}
let viewNames = Set(collector.symbols.filter { $0.kind == "struct" || $0.kind == "class" }.map(\.name))
if viewNames.contains("ContentView") {
  summary.append("ContentView is declared.")
}
let macros = collector.symbols.filter { $0.kind == "macro" }.map(\.name)
if !macros.isEmpty {
  summary.append("Macros: \(Array(Set(macros)).sorted().joined(separator: ", ")).")
}

let report = FishyReport(ok: diagnostics.isEmpty, diagnostics: diagnostics, symbols: collector.symbols, summary: summary)
let data = try JSONEncoder().encode(report)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
