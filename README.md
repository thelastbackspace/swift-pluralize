# Pluralize

[![CI](https://github.com/thelastbackspace/swift-pluralize/actions/workflows/ci.yml/badge.svg)](https://github.com/thelastbackspace/swift-pluralize/actions/workflows/ci.yml)

Pluralize and singularize English words — irregulars, uncountables,
and case preservation included.

```swift
import Pluralize

let p = Pluralize()

p.plural("cat")        // "cats"
p.plural("person")     // "people"
p.singular("geese")    // "goose"
p.count("test", 3, inclusive: true)  // "3 tests"

p.isPlural("cats")     // true
p.isSingular("goose")  // true
```

Words keep their case shape: `"Cat"` → `"Cats"`,
`"CAT"` → `"CATS"`.

## Adding to a package

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/thelastbackspace/swift-pluralize", from: "1.0.0")
]
```

and `"Pluralize"` to your target's dependencies.

## API

### `Pluralize`

A value-type rule book holding irregular pairs, uncountables, and
regex rules; `init()` loads the upstream defaults. Rules are matched
with `NSRegularExpression` (ICU) case-insensitively.

- `plural(_:)` / `singular(_:)` — convert a word.
- `count(_:_:inclusive:)` — pick the form for a count, optionally
  prefixed (`"1 test"`, `"3 tests"`).
- `isPlural(_:)` / `isSingular(_:)`.

### Custom rules

All mutating, on a `var` instance:

- `addIrregularRule(single:plural:)` — register a pair.
- `addUncountableRule(_:)` — same form both ways.
- `addPluralRule(_:replacement:)` / `addSingularRule(_:replacement:)` —
  ICU pattern; replacements interpolate `$0`–`$9`.

## Notes

- `Pluralize` is a value type (`Sendable`): copy it to snapshot custom
  rules.
- Case restoration uses Unicode-aware `lowercased()`/`uppercased()`.

## Testing

```sh
swift test
```

The suite ports upstream's test file: 657 singular/plural pairs,
checked through plural, singular, `isPlural`, `isSingular`, and count
conversion, plus case preservation and custom-rule tests.

## Contributing

PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The CI gate
(`swift build`, `swift test`) must pass.

## Credits

Behavior, the rule tables, and the test suite follow the npm package
[`pluralize`](https://github.com/blakeembrey/pluralize) v8.0.0 (MIT,
© Blake Embrey); the implementation is original. Swift implementation
© 2026 thelastbackspace, MIT — see [LICENSE](LICENSE).
