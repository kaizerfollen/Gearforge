// SwiftUI stub — Text, LocalizedStringKey, Font, Color, Image.

// MARK: - LocalizedStringKey

public protocol _FormatSpecifiable: Equatable {}
extension Int: _FormatSpecifiable {}
extension Int8: _FormatSpecifiable {}
extension Int16: _FormatSpecifiable {}
extension Int32: _FormatSpecifiable {}
extension Int64: _FormatSpecifiable {}
extension UInt: _FormatSpecifiable {}
extension UInt8: _FormatSpecifiable {}
extension UInt16: _FormatSpecifiable {}
extension UInt32: _FormatSpecifiable {}
extension UInt64: _FormatSpecifiable {}
extension Float: _FormatSpecifiable {}
extension Double: _FormatSpecifiable {}
extension CGFloat: _FormatSpecifiable {}

public struct LocalizedStringKey: Equatable, ExpressibleByStringInterpolation, Sendable {
    public init(_ value: String) { _stub() }
    public init(stringLiteral value: String) { _stub() }
    public init(stringInterpolation: LocalizedStringKey.StringInterpolation) { _stub() }
    public static func == (a: Self, b: Self) -> Bool { _stub() }

    public struct StringInterpolation: StringInterpolationProtocol {
        public init(literalCapacity: Int, interpolationCount: Int) { _stub() }
        public mutating func appendLiteral(_ literal: String) { _stub() }
        public mutating func appendInterpolation(_ string: String) { _stub() }
        public mutating func appendInterpolation<Subject: ReferenceConvertible>(_ subject: Subject, formatter: Formatter? = nil) { _stub() }
        public mutating func appendInterpolation<Subject: NSObject>(_ subject: Subject, formatter: Formatter? = nil) { _stub() }
        public mutating func appendInterpolation<F: FormatStyle>(_ input: F.FormatInput, format: F)
            where F.FormatInput: Equatable, F.FormatOutput == String { _stub() }
        public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T) { _stub() }
        public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T, specifier: String) { _stub() }
        public mutating func appendInterpolation(_ text: Text) { _stub() }
        public mutating func appendInterpolation(_ image: Image) { _stub() }
        public mutating func appendInterpolation(_ attributedString: AttributedString) { _stub() }
        public mutating func appendInterpolation(_ date: Date, style: Text.DateStyle) { _stub() }
    }
}

// MARK: - Text

public struct Text: View, Equatable, Sendable {
    public typealias Body = Never
    public var body: Never { _stub() }
    public static func == (a: Text, b: Text) -> Bool { _stub() }

    public init(verbatim content: String) { _stub() }
    @_disfavoredOverload public init<S: StringProtocol>(_ content: S) { _stub() }
    public init(_ key: LocalizedStringKey, tableName: String? = nil, bundle: Bundle? = nil, comment: StaticString? = nil) { _stub() }
    public init(_ attributedContent: AttributedString) { _stub() }
    public init<Subject: ReferenceConvertible>(_ subject: Subject, formatter: Formatter) { _stub() }
    public init<Subject: NSObject>(_ subject: Subject, formatter: Formatter) { _stub() }
    public init<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatInput: Equatable, F.FormatOutput == String { _stub() }
    public init(_ date: Date, style: Text.DateStyle) { _stub() }
    public init(_ dates: ClosedRange<Date>) { _stub() }
    public init(_ image: Image) { _stub() }

    public struct DateStyle: Sendable {
        public static let time = DateStyle(), date = DateStyle(), relative = DateStyle(), offset = DateStyle(),
                          timer = DateStyle()
    }
    public enum Case: Hashable, Sendable { case uppercase, lowercase }

    public func font(_ font: Font?) -> Text { _stub() }
    public func fontWeight(_ weight: Font.Weight?) -> Text { _stub() }
    public func fontDesign(_ design: Font.Design?) -> Text { _stub() }
    public func fontWidth(_ width: Font.Width?) -> Text { _stub() }
    public func bold() -> Text { _stub() }
    public func bold(_ isActive: Bool) -> Text { _stub() }
    public func italic() -> Text { _stub() }
    public func italic(_ isActive: Bool) -> Text { _stub() }
    public func monospaced(_ isActive: Bool = true) -> Text { _stub() }
    public func monospacedDigit() -> Text { _stub() }
    public func foregroundColor(_ color: Color?) -> Text { _stub() }
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text { _stub() }
    public func strikethrough(_ isActive: Bool = true, color: Color? = nil) -> Text { _stub() }
    public func underline(_ isActive: Bool = true, color: Color? = nil) -> Text { _stub() }
    public func kerning(_ kerning: CGFloat) -> Text { _stub() }
    public func tracking(_ tracking: CGFloat) -> Text { _stub() }
    public func baselineOffset(_ baselineOffset: CGFloat) -> Text { _stub() }
    public func textScale(_ scale: Text.Scale, isEnabled: Bool = true) -> Text { _stub() }
    public struct Scale: Hashable, Sendable { public static let `default` = Scale(), secondary = Scale() }

    public static func + (lhs: Text, rhs: Text) -> Text { _stub() }
}

// MARK: - Font

public struct Font: Hashable, Sendable {
    public static func == (a: Font, b: Font) -> Bool { _stub() }
    public func hash(into hasher: inout Hasher) { _stub() }

    public static let largeTitle = Font(), title = Font(), title2 = Font(), title3 = Font(), headline = Font(),
                      subheadline = Font(), body = Font(), callout = Font(), footnote = Font(), caption = Font(),
                      caption2 = Font()

    public static func system(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font { _stub() }
    public static func system(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> Font { _stub() }
    public static func custom(_ name: String, size: CGFloat) -> Font { _stub() }
    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font { _stub() }
    public static func custom(_ name: String, fixedSize: CGFloat) -> Font { _stub() }
    public init(_ font: UIFont) { _stub() }
    init() {}

    public func italic() -> Font { _stub() }
    public func smallCaps() -> Font { _stub() }
    public func lowercaseSmallCaps() -> Font { _stub() }
    public func uppercaseSmallCaps() -> Font { _stub() }
    public func monospacedDigit() -> Font { _stub() }
    public func monospaced() -> Font { _stub() }
    public func weight(_ weight: Font.Weight) -> Font { _stub() }
    public func width(_ width: Font.Width) -> Font { _stub() }
    public func bold() -> Font { _stub() }
    public func leading(_ leading: Font.Leading) -> Font { _stub() }

    public struct Weight: Hashable, Sendable {
        public static let ultraLight = Weight(), thin = Weight(), light = Weight(), regular = Weight(),
                          medium = Weight(), semibold = Weight(), bold = Weight(), heavy = Weight(), black = Weight()
        public static func == (a: Self, b: Self) -> Bool { _stub() }
        public func hash(into hasher: inout Hasher) { _stub() }
    }
    public struct Width: Hashable, Sendable {
        public var value: CGFloat
        public init(_ value: CGFloat) { self.value = value }
        public static let compressed = Width(-0.3), condensed = Width(-0.2), standard = Width(0), expanded = Width(0.2)
    }
    public enum Design: Hashable, Sendable { case `default`, serif, rounded, monospaced }
    public enum Leading: Hashable, Sendable { case standard, tight, loose }
    public enum TextStyle: CaseIterable, Hashable, Sendable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
    }
}

// MARK: - Color

public struct Color: Hashable, CustomStringConvertible, Sendable {
    public static func == (a: Color, b: Color) -> Bool { _stub() }
    public func hash(into hasher: inout Hasher) { _stub() }
    public var description: String { _stub() }

    public enum RGBColorSpace: Hashable, Sendable { case sRGB, sRGBLinear, displayP3 }

    public init(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) { _stub() }
    public init(_ colorSpace: Color.RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) { _stub() }
    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) { _stub() }
    public init(_ name: String, bundle: Bundle? = nil) { _stub() }
    public init(uiColor: UIColor) { _stub() }
    public init(_ color: UIColor) { _stub() }
    public init(cgColor: CGColor) { _stub() }

    public static let black = Color(white: 0), white = Color(white: 1), gray = Color(white: 0.5), red = Color(white: 0),
                      green = Color(white: 0), blue = Color(white: 0), orange = Color(white: 0), yellow = Color(white: 0),
                      pink = Color(white: 0), purple = Color(white: 0), primary = Color(white: 0),
                      secondary = Color(white: 0), clear = Color(white: 0), mint = Color(white: 0),
                      teal = Color(white: 0), cyan = Color(white: 0), indigo = Color(white: 0), brown = Color(white: 0)
    public static var accentColor: Color { _stub() }

    public func opacity(_ opacity: Double) -> Color { _stub() }
    public var gradient: AnyGradient { _stub() }
    public var cgColor: CGColor? { _stub() }
}

extension UIColor {
    public convenience init(_ color: Color) { _stub() }
}

// MARK: - Image

public struct Image: Equatable, Sendable {
    public static func == (a: Image, b: Image) -> Bool { _stub() }

    public init(_ name: String, bundle: Bundle? = nil) { _stub() }
    public init(_ name: String, bundle: Bundle? = nil, label: Text) { _stub() }
    public init(decorative name: String, bundle: Bundle? = nil) { _stub() }
    public init(systemName: String) { _stub() }
    public init(systemName: String, variableValue: Double?) { _stub() }
    public init(uiImage: UIImage) { _stub() }
    public init(_ cgImage: CGImage, scale: CGFloat, orientation: Image.Orientation = .up, label: Text) { _stub() }
    public init(decorative cgImage: CGImage, scale: CGFloat, orientation: Image.Orientation = .up) { _stub() }

    public enum Orientation: UInt8, CaseIterable, Hashable, Sendable {
        case up, upMirrored, down, downMirrored, left, leftMirrored, right, rightMirrored
    }
    public enum ResizingMode: Hashable, Sendable { case tile, stretch }
    public enum TemplateRenderingMode: Hashable, Sendable { case template, original }
    public enum Interpolation: Hashable, Sendable { case none, low, medium, high }
    public enum Scale: Hashable, Sendable { case small, medium, large }

    public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: Image.ResizingMode = .stretch) -> Image { _stub() }
    public func renderingMode(_ renderingMode: Image.TemplateRenderingMode?) -> Image { _stub() }
    public func interpolation(_ interpolation: Image.Interpolation) -> Image { _stub() }
    public func antialiased(_ isAntialiased: Bool) -> Image { _stub() }
}
extension Image: View {
    public typealias Body = Never
    public var body: Never { _stub() }
}
extension View {
    public func imageScale(_ scale: Image.Scale) -> some View { _modified() }
}
