// Gearforge — FactoryCore
// Safe arithmetic evaluator for technology unit-count formulas (04_technologies), e.g. "2500*(L-3)",
// "2^(L-6)*1000", "100*(L-6)+900". Grammar (standard precedence, `^` right-associative, binds tighter than unary -):
//   expr   := term (('+' | '-') term)*
//   term   := unary (('*' | '/') unary)*
//   unary  := '-' unary | power
//   power  := atom ('^' unary)?
//   atom   := number | 'L' | '(' expr ')'
// Parsed once into a compact postfix program; evaluation is allocation-free apart from a small stack.
// Owner: Production engineer.

import Foundation

public struct TechFormula: Equatable, Sendable {
    enum Op: Equatable, Sendable {
        case num(Double), level, add, sub, mul, div, pow, neg
    }

    let program: [Op]
    public let source: String

    /// Parses `source`; returns nil on any syntax error (unknown character, unbalanced parentheses...).
    public init?(_ source: String) {
        self.source = source
        var p = Parser(Array(source.utf8))
        guard let prog = p.parse() else { return nil }
        program = prog
    }

    /// Evaluates the formula for level `L`.
    public func evaluate(level L: Double) -> Double {
        var stack: [Double] = []
        stack.reserveCapacity(8)
        for op in program {
            switch op {
            case .num(let v): stack.append(v)
            case .level: stack.append(L)
            case .neg: stack[stack.count - 1] = -stack[stack.count - 1]
            default:
                let b = stack.removeLast(), a = stack.removeLast()
                switch op {
                case .add: stack.append(a + b)
                case .sub: stack.append(a - b)
                case .mul: stack.append(a * b)
                case .div: stack.append(b == 0 ? .infinity : a / b)
                case .pow: stack.append(TechFormula.power(a, b))
                default: break
                }
            }
        }
        return stack.last ?? 0
    }

    /// a^b: exact repeated squaring for integral exponents (deterministic across platforms), libm otherwise.
    static func power(_ a: Double, _ b: Double) -> Double {
        if b == b.rounded(), abs(b) < 4096 {
            var result = 1.0, base = a
            var n = Int(abs(b))
            while n > 0 {
                if n & 1 == 1 { result *= base }
                base *= base
                n >>= 1
            }
            return b < 0 ? 1 / result : result
        }
        return Foundation.pow(a, b)
    }

    private struct Parser {
        let s: [UInt8]
        var i = 0
        var out: [Op] = []
        init(_ s: [UInt8]) { self.s = s }

        mutating func parse() -> [Op]? {
            guard expr(), skipSpaces() == nil else { return nil }
            return out.isEmpty ? nil : out
        }

        /// Skips whitespace; returns the next byte or nil at end.
        @discardableResult mutating func skipSpaces() -> UInt8? {
            while i < s.count, s[i] == 32 || s[i] == 9 { i += 1 }
            return i < s.count ? s[i] : nil
        }

        mutating func expr() -> Bool {
            guard term() else { return false }
            while let c = skipSpaces(), c == UInt8(ascii: "+") || c == UInt8(ascii: "-") {
                i += 1
                guard term() else { return false }
                out.append(c == UInt8(ascii: "+") ? .add : .sub)
            }
            return true
        }

        mutating func term() -> Bool {
            guard unary() else { return false }
            while let c = skipSpaces(), c == UInt8(ascii: "*") || c == UInt8(ascii: "/") {
                i += 1
                guard unary() else { return false }
                out.append(c == UInt8(ascii: "*") ? .mul : .div)
            }
            return true
        }

        mutating func unary() -> Bool {
            if skipSpaces() == UInt8(ascii: "-") {
                i += 1
                guard unary() else { return false }
                out.append(.neg)
                return true
            }
            if skipSpaces() == UInt8(ascii: "+") { i += 1; return unary() }
            return power()
        }

        mutating func power() -> Bool {
            guard atom() else { return false }
            if skipSpaces() == UInt8(ascii: "^") {
                i += 1
                guard unary() else { return false }
                out.append(.pow)
            }
            return true
        }

        mutating func atom() -> Bool {
            guard let c = skipSpaces() else { return false }
            if c == UInt8(ascii: "(") {
                i += 1
                guard expr(), skipSpaces() == UInt8(ascii: ")") else { return false }
                i += 1
                return true
            }
            if c == UInt8(ascii: "L") || c == UInt8(ascii: "l") { i += 1; out.append(.level); return true }
            if (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")) || c == UInt8(ascii: ".") {
                var v = 0.0, frac = 0.0, scale = 1.0, digits = 0
                while i < s.count, s[i] >= UInt8(ascii: "0"), s[i] <= UInt8(ascii: "9") {
                    v = v * 10 + Double(s[i] - UInt8(ascii: "0")); i += 1; digits += 1
                }
                if i < s.count, s[i] == UInt8(ascii: ".") {
                    i += 1
                    while i < s.count, s[i] >= UInt8(ascii: "0"), s[i] <= UInt8(ascii: "9") {
                        scale /= 10; frac += Double(s[i] - UInt8(ascii: "0")) * scale; i += 1; digits += 1
                    }
                }
                guard digits > 0 else { return false }
                out.append(.num(v + frac))
                return true
            }
            return false
        }
    }
}
