//! Pluralize and singularize English words.
//!
//! A behavior-faithful Swift port of the npm package
//! [`pluralize`](https://github.com/blakeembrey/pluralize) (v8.0.0).
//! The upstream test suite is ported in the tests target.

import Foundation

/// A rule book of irregulars, uncountables, and regex rules. `init()`
/// loads the upstream defaults; the `add*` methods extend it.
public struct Pluralize: Sendable {

    private var irregularSingles: [String: String]
    private var irregularPlurals: [String: String]
    private var uncountables: Set<String>
    private var pluralRules: [Rule]
    private var singularRules: [Rule]

    public init() {
        irregularSingles = [:]
        irregularPlurals = [:]
        uncountables = []
        pluralRules = []
        singularRules = []

        // Order matters: later additions are checked first.
        for (single, plural) in Self.defaultIrregulars {
            addIrregularRule(single: single, plural: plural)
        }
        for (pattern, replacement) in Self.defaultPluralRules {
            addPluralRule(pattern, replacement: replacement)
        }
        for (pattern, replacement) in Self.defaultSingularRules {
            addSingularRule(pattern, replacement: replacement)
        }
        for word in Self.defaultUncountables {
            uncountables.insert(word)
        }
        // Regex uncountables: identity rules on both sides.
        for pattern in Self.defaultUncountableRegexes {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                pluralRules.append(Rule(regex: regex, replacement: "$0"))
                singularRules.append(Rule(regex: regex, replacement: "$0"))
            }
        }
    }

    // MARK: - Conversion

    /// Pluralize a word (`"cat"` → `"cats"`).
    public func plural(_ word: String) -> String {
        replaceWord(
            word,
            replaceMap: irregularSingles,
            keepMap: irregularPlurals,
            rules: pluralRules
        )
    }

    /// Singularize a word (`"cats"` → `"cat"`).
    public func singular(_ word: String) -> String {
        replaceWord(
            word,
            replaceMap: irregularPlurals,
            keepMap: irregularSingles,
            rules: singularRules
        )
    }

    /// Pluralize or singularize a word based on `count`; with
    /// `inclusive`, the count prefixes the word (`"3 ducks"`).
    public func count(_ word: String, _ count: Int, inclusive: Bool = false) -> String {
        let form = count == 1 ? singular(word) : plural(word)
        return inclusive ? "\(count) \(form)" : form
    }

    /// True when the word is already plural.
    public func isPlural(_ word: String) -> Bool {
        checkWord(
            word,
            replaceMap: irregularSingles,
            keepMap: irregularPlurals,
            rules: pluralRules
        )
    }

    /// True when the word is already singular.
    public func isSingular(_ word: String) -> Bool {
        checkWord(
            word,
            replaceMap: irregularPlurals,
            keepMap: irregularSingles,
            rules: singularRules
        )
    }

    // MARK: - Custom rules

    /// Add a pluralization rule. The pattern is an ICU regular
    /// expression, matched case-insensitively; replacements interpolate
    /// `$0`–`$9`.
    public mutating func addPluralRule(_ rule: String, replacement: String) {
        guard let regex = try? NSRegularExpression(pattern: rule, options: [.caseInsensitive]) else {
            return
        }
        pluralRules.append(Rule(regex: regex, replacement: replacement))
    }

    /// Add a singularization rule.
    public mutating func addSingularRule(_ rule: String, replacement: String) {
        guard let regex = try? NSRegularExpression(pattern: rule, options: [.caseInsensitive]) else {
            return
        }
        singularRules.append(Rule(regex: regex, replacement: replacement))
    }

    /// Mark a word as uncountable (same in singular and plural).
    public mutating func addUncountableRule(_ word: String) {
        uncountables.insert(word.lowercased())
    }

    /// Register an irregular single/plural pair (both directions).
    public mutating func addIrregularRule(single: String, plural: String) {
        let s = single.lowercased()
        let p = plural.lowercased()
        irregularSingles[s] = p
        irregularPlurals[p] = s
    }

    // MARK: - Internals

    private struct Rule {
        let regex: NSRegularExpression
        let replacement: String
    }

    private func replaceWord(
        _ word: String,
        replaceMap: [String: String],
        keepMap: [String: String],
        rules: [Rule]
    ) -> String {
        let token = word.lowercased()

        if keepMap[token] != nil {
            return Self.restoreCase(word: word, token: token)
        }
        if let replacement = replaceMap[token] {
            return Self.restoreCase(word: word, token: replacement)
        }
        return sanitizeWord(token: token, word: word, rules: rules)
    }

    private func checkWord(
        _ word: String,
        replaceMap: [String: String],
        keepMap: [String: String],
        rules: [Rule]
    ) -> Bool {
        let token = word.lowercased()

        if keepMap[token] != nil { return true }
        if replaceMap[token] != nil { return false }

        if token.isEmpty || uncountables.contains(token) { return true }

        // Rules are checked in reverse insertion order.
        for rule in rules.reversed() {
            if rule.regex.firstMatch(
                in: token, range: NSRange(token.startIndex..., in: token)) != nil
            {
                let replaced = replace(token, with: rule)
                return replaced == token
            }
        }
        return true
    }

    private func sanitizeWord(token: String, word: String, rules: [Rule]) -> String {
        // Empty string or doesn't need fixing.
        if token.isEmpty || uncountables.contains(token) {
            return word
        }

        for rule in rules.reversed() {
            if rule.regex.firstMatch(
                in: word, range: NSRange(word.startIndex..., in: word)) != nil
            {
                return replace(word, with: rule)
            }
        }
        return word
    }

    /// Replace the first match of a rule in a word.
    private func replace(_ word: String, with rule: Rule) -> String {
        let range = NSRange(word.startIndex..., in: word)
        guard let match = rule.regex.firstMatch(in: word, range: range) else {
            return word
        }

        // Interpolate $0-$9 against the match's capture groups.
        var groups = [String]()
        for i in 0...min(9, match.numberOfRanges - 1) {
            if let r = Range(match.range(at: i), in: word) {
                groups.append(String(word[r]))
            } else {
                groups.append("")
            }
        }
        let replaced = Self.interpolate(rule.replacement, groups: groups)

        let matched = Range(match.range, in: word).map { String(word[$0]) } ?? ""

        let matchedRange = Range(match.range, in: word) ?? word.startIndex..<word.startIndex
        let cased: String
        if matched.isEmpty {
            // Empty match: restore the case of the preceding character.
            guard
                match.range.location > 0,
                matchedRange.lowerBound > word.startIndex
            else {
                return String(word[..<matchedRange.upperBound]) + replaced
                    + String(word[matchedRange.upperBound...])
            }
            let before = word[word.index(before: matchedRange.lowerBound)]
            cased = Self.restoreCase(word: String(before), token: replaced)
        } else {
            cased = Self.restoreCase(word: matched, token: replaced)
        }

        // Substitute the replacement into the word.
        return String(word[..<matchedRange.lowerBound]) + cased
            + String(word[matchedRange.upperBound...])
    }

    /// Port of upstream's `restoreCase`: replicate the case shape of
    /// `word` onto `token`.
    static func restoreCase(word: String, token: String) -> String {
        // Tokens are an exact match.
        if word == token { return token }

        // Lower cased words. E.g. "hello".
        if word == word.lowercased() { return token.lowercased() }

        // Upper cased words. E.g. "WHISKY".
        if word == word.uppercased() { return token.uppercased() }

        // Title cased words. E.g. "Title".
        if let first = word.first, first.isUppercase {
            return String(token.prefix(1)).uppercased() + token.dropFirst().lowercased()
        }

        // Lower cased words. E.g. "test".
        return token.lowercased()
    }

    /// Interpolate `$0`–`$9` in a replacement template.
    static func interpolate(_ template: String, groups: [String]) -> String {
        var result = ""
        let chars = Array(template)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "$" && i + 1 < chars.count && chars[i + 1].isNumber {
                var j = i + 1
                var digits = ""
                while j < chars.count && chars[j].isNumber {
                    digits.append(chars[j])
                    j += 1
                }
                if let n = Int(digits), n < groups.count {
                    result += groups[n]
                }
                i = j
            } else {
                result.append(c)
                i += 1
            }
        }
        return result
    }

    // MARK: - Default rule tables (upstream pluralize v8.0.0)

    private static let defaultIrregulars: [(String, String)] = [
        // Pronouns.
        ("I", "we"), ("me", "us"), ("he", "they"), ("she", "them"),
        ("them", "them"), ("myself", "ourselves"), ("yourself", "yourselves"),
        ("itself", "themselves"), ("herself", "themselves"),
        ("himself", "themselves"), ("themself", "themselves"),
        ("is", "are"), ("was", "were"), ("has", "have"),
        ("this", "these"), ("that", "those"), ("my", "our"),
        ("its", "their"), ("his", "their"), ("her", "their"),
        // Words ending with a consonant and `o`.
        ("echo", "echoes"), ("dingo", "dingoes"), ("volcano", "volcanoes"),
        ("tornado", "tornadoes"), ("torpedo", "torpedoes"),
        // Ends with `us`.
        ("genus", "genera"), ("viscus", "viscera"),
        // Ends with `ma`.
        ("stigma", "stigmata"), ("stoma", "stomata"), ("dogma", "dogmata"),
        ("lemma", "lemmata"), ("schema", "schemata"), ("anathema", "anathemata"),
        // Other irregular rules.
        ("ox", "oxen"), ("axe", "axes"), ("die", "dice"), ("yes", "yeses"),
        ("foot", "feet"), ("eave", "eaves"), ("goose", "geese"),
        ("tooth", "teeth"), ("quiz", "quizzes"), ("human", "humans"),
        ("proof", "proofs"), ("carve", "carves"), ("valve", "valves"),
        ("looey", "looies"), ("thief", "thieves"), ("groove", "grooves"),
        ("pickaxe", "pickaxes"), ("passerby", "passersby"),
        ("canvas", "canvases"),
    ]

    private static let defaultPluralRules: [(String, String)] = [
        ("s?$", "s"),
        ("[^\\u0000-\\u007F]$", "$0"),
        ("([^aeiou]ese)$", "$1"),
        ("(ax|test)is$", "$1es"),
        ("(alias|[^aou]us|t[lm]as|gas|ris)$", "$1es"),
        ("(e[mn]u)s?$", "$1s"),
        ("([^l]ias|[aeiou]las|[ejzr]as|[iu]am)$", "$1"),
        ("(alumn|syllab|vir|radi|nucle|fung|cact|stimul|termin|bacill|foc|uter|loc|strat)(?:us|i)$", "$1i"),
        ("(alumn|alg|vertebr)(?:a|ae)$", "$1ae"),
        ("(seraph|cherub)(?:im)?$", "$1im"),
        ("(her|at|gr)o$", "$1oes"),
        ("(agend|addend|millenni|dat|extrem|bacteri|desiderat|strat|candelabr|errat|ov|symposi|curricul|automat|quor)(?:a|um)$", "$1a"),
        ("(apheli|hyperbat|periheli|asyndet|noumen|phenomen|criteri|organ|prolegomen|hedr|automat)(?:a|on)$", "$1a"),
        ("sis$", "ses"),
        ("(?:(kni|wi|li)fe|(ar|l|ea|eo|oa|hoo)f)$", "$1$2ves"),
        ("([^aeiouy]|qu)y$", "$1ies"),
        ("([^ch][ieo][ln])ey$", "$1ies"),
        ("(x|ch|ss|sh|zz)$", "$1es"),
        ("(matr|cod|mur|sil|vert|ind|append)(?:ix|ex)$", "$1ices"),
        ("\\b((?:tit)?m|l)(?:ice|ouse)$", "$1ice"),
        ("(pe)(?:rson|ople)$", "$1ople"),
        ("(child)(?:ren)?$", "$1ren"),
        ("eaux$", "$0"),
        ("m[ae]n$", "men"),
        ("^thou$", "you"),
    ]

    private static let defaultSingularRules: [(String, String)] = [
        ("s$", ""),
        ("(ss)$", "$1"),
        ("(wi|kni|(?:after|half|high|low|mid|non|night|[^\\w]|^)li)ves$", "$1fe"),
        ("(ar|(?:wo|[ae])l|[eo][ao])ves$", "$1f"),
        ("ies$", "y"),
        ("(dg|ss|ois|lk|ok|wn|mb|th|ch|ec|oal|is|ck|ix|sser|ts|wb)ies$", "$1ie"),
        ("\\b(l|(?:neck|cross|hog|aun)?t|coll|faer|food|gen|goon|group|hipp|junk|vegg|(?:pork)?p|charl|calor|cut)ies$", "$1ie"),
        ("\\b(mon|smil)ies$", "$1ey"),
        ("\\b((?:tit)?m|l)ice$", "$1ouse"),
        ("(seraph|cherub)im$", "$1"),
        ("(x|ch|ss|sh|zz|tto|go|cho|alias|[^aou]us|t[lm]as|gas|(?:her|at|gr)o|[aeiou]ris)(?:es)?$", "$1"),
        ("(analy|diagno|parenthe|progno|synop|the|empha|cri|ne)(?:sis|ses)$", "$1sis"),
        ("(movie|twelve|abuse|e[mn]u)s$", "$1"),
        ("(test)(?:is|es)$", "$1is"),
        ("(alumn|syllab|vir|radi|nucle|fung|cact|stimul|termin|bacill|foc|uter|loc|strat)(?:us|i)$", "$1us"),
        ("(agend|addend|millenni|dat|extrem|bacteri|desiderat|strat|candelabr|errat|ov|symposi|curricul|quor)a$", "$1um"),
        ("(apheli|hyperbat|periheli|asyndet|noumen|phenomen|criteri|organ|prolegomen|hedr|automat)a$", "$1on"),
        ("(alumn|alg|vertebr)ae$", "$1a"),
        ("(cod|mur|sil|vert|ind)ices$", "$1ex"),
        ("(matr|append)ices$", "$1ix"),
        ("(pe)(rson|ople)$", "$1rson"),
        ("(child)ren$", "$1"),
        ("(eau)x?$", "$1"),
        ("men$", "man"),
    ]

    private static let defaultUncountables: [String] = [
        "adulthood", "advice", "agenda", "aid", "aircraft", "alcohol",
        "ammo", "analytics", "anime", "athletics", "audio", "bison",
        "blood", "bream", "buffalo", "butter", "carp", "cash",
        "chassis", "chess", "clothing", "cod", "commerce",
        "cooperation", "corps", "debris", "diabetes", "digestion",
        "elk", "energy", "equipment", "excretion", "expertise",
        "firmware", "flounder", "fun", "gallows", "garbage",
        "graffiti", "hardware", "headquarters", "health", "herpes",
        "highjinks", "homework", "housework", "information", "jeans",
        "justice", "kudos", "labour", "literature", "machinery",
        "mackerel", "mail", "media", "mews", "moose", "music", "mud",
        "manga", "news", "only", "personnel", "pike", "plankton",
        "pliers", "police", "pollution", "premises", "rain",
        "research", "rice", "salmon", "scissors", "series", "sewage",
        "shambles", "shrimp", "software", "staff", "swine", "tennis",
        "traffic", "transportation", "trout", "tuna", "wealth",
        "welfare", "whiting", "wildebeest", "wildlife", "you",
    ]

    private static let defaultUncountableRegexes: [String] = [
        "pok[eé]mon$",
        "[^aeiou]ese$",  // "chinese", "japanese"
        "deer$",         // "deer", "reindeer"
        "fish$",         // "fish", "blowfish", "angelfish"
        "measles$",
        "o[iu]s$",       // "carnivorous"
        "pox$",          // "chickpox", "smallpox"
        "sheep$",
    ]
}
