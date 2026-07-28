import SwiftUI

/// Lightweight syntax colouring for fenced code blocks.
///
/// This is a tokeniser, not a parser: it recognises comments, strings, numbers,
/// keywords, call sites and type-shaped identifiers. That is enough for the
/// short snippets the console pastes into chat and reply cards, and it keeps
/// the colours the design doc specifies (keyword violet, call teal, type blue,
/// number amber) without pulling in a grammar engine.
enum CodeHighlighter {

    /// Keywords across the languages the studio actually posts: Go, TypeScript,
    /// Swift, Python, shell.
    private static let keywords: Set<String> = [
        // control flow
        "if", "else", "for", "while", "switch", "case", "default", "break",
        "continue", "return", "goto", "do", "try", "catch", "finally", "throw",
        "throws", "defer", "guard", "in", "of", "range", "yield", "match",
        // declaration
        "func", "function", "def", "class", "struct", "enum", "interface",
        "type", "var", "let", "const", "static", "public", "private",
        "protected", "internal", "extension", "protocol", "actor", "package",
        "import", "from", "export", "module", "namespace", "trait", "impl",
        // async
        "async", "await", "go", "chan", "select", "spawn", "then",
        // values
        "true", "false", "nil", "null", "none", "undefined", "self", "this",
        "new", "delete", "typeof", "instanceof", "as", "is", "not", "and", "or",
        // shell
        "echo", "cd", "export", "source", "sudo", "set",
    ]

    static func highlight(_ source: String, language: String?) -> AttributedString {
        var output = AttributedString()
        let isShell = ["bash", "sh", "zsh", "shell", "console"].contains(language ?? "")

        for (lineIndex, line) in source.components(separatedBy: "\n").enumerated() {
            if lineIndex > 0 { output.append(AttributedString("\n")) }
            output.append(highlightLine(line, isShell: isShell, isFirstToken: true))
        }
        return output
    }

    private static func highlightLine(_ line: String, isShell: Bool, isFirstToken: Bool) -> AttributedString {
        var output = AttributedString()
        let characters = Array(line)
        var index = 0
        var seenFirstWord = false

        while index < characters.count {
            let character = characters[index]

            // Comment to end of line.
            if character == "#" || (character == "/" && index + 1 < characters.count && characters[index + 1] == "/") {
                output.append(styled(String(characters[index...]), .comment))
                break
            }

            // String literal.
            if character == "\"" || character == "'" || character == "`" {
                let quote = character
                var end = index + 1
                while end < characters.count {
                    if characters[end] == "\\" { end += 2; continue }
                    if characters[end] == quote { end += 1; break }
                    end += 1
                }
                let upper = min(end, characters.count)
                output.append(styled(String(characters[index..<upper]), .string))
                index = upper
                continue
            }

            // Number.
            if character.isNumber {
                var end = index
                while end < characters.count, characters[end].isNumber || characters[end] == "." || characters[end] == "_" {
                    end += 1
                }
                output.append(styled(String(characters[index..<end]), .number))
                index = end
                continue
            }

            // Identifier.
            if character.isLetter || character == "_" || character == "$" {
                var end = index
                while end < characters.count,
                      characters[end].isLetter || characters[end].isNumber
                        || characters[end] == "_" || characters[end] == "$" || characters[end] == "-" {
                    end += 1
                }
                let word = String(characters[index..<end])
                let followedByCall = end < characters.count && characters[end] == "("

                let role: Role
                if keywords.contains(word.lowercased()) && word == word.lowercased() {
                    role = .keyword
                } else if isShell && !seenFirstWord {
                    // The command itself reads as the "call" in a shell line.
                    role = .call
                } else if followedByCall {
                    role = .call
                } else if let first = word.first, first.isUppercase {
                    role = .type
                } else if isShell && word.hasPrefix("-") {
                    role = .number
                } else {
                    role = .plain
                }
                output.append(styled(word, role))
                seenFirstWord = true
                index = end
                continue
            }

            // Shell flags (`--window`) read as parameters, not punctuation.
            if isShell, character == "-", index + 1 < characters.count,
               characters[index + 1] == "-" || characters[index + 1].isLetter {
                var end = index
                while end < characters.count, !characters[end].isWhitespace { end += 1 }
                output.append(styled(String(characters[index..<end]), .flag))
                index = end
                continue
            }

            output.append(styled(String(character), .plain))
            index += 1
        }

        return output
    }

    private enum Role {
        case keyword, call, type, number, string, comment, flag, plain

        var colour: Color {
            switch self {
            case .keyword: return OC.dyn(light: 0x7B45BE, dark: 0xA99CF0)
            case .call: return OC.taskType
            case .type: return OC.dyn(light: 0x3B62C4, dark: 0x8FABF0)
            case .number: return OC.waiting
            case .string: return OC.dyn(light: 0x2E7D3A, dark: 0x9BD6A0)
            case .comment: return OC.labelQuaternary
            case .flag: return OC.dyn(light: 0x9A6A08, dark: 0xE0B341)
            case .plain: return OC.dyn(light: 0x1C1C1E, dark: 0xE7E8EE)
            }
        }
    }

    private static func styled(_ text: String, _ role: Role) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = role.colour
        return attributed
    }
}
