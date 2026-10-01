# Fonts

Every `.ttf` in this folder, with the exact PostScript name Swift must use in
`Font.custom("<name>", …)` / `UIFont(name: "<name>", …)`. Regenerate this table with
`fontTools` (`TTFont(path)["name"].getDebugName(6)`) if a file here ever changes — never
guess a PostScript name from the filename.

## Outfit (variable-weight body face, existing)

| file | PostScript name | family | weight |
|---|---|---|---|
| Outfit-Light.ttf | `Outfit-Light` | Outfit Light | 300 |
| Outfit-Regular.ttf | `Outfit-Regular` | Outfit | 400 |
| Outfit-Medium.ttf | `Outfit-Medium` | Outfit Medium | 500 |
| Outfit-SemiBold.ttf | `Outfit-SemiBold` | Outfit SemiBold | 600 |
| Outfit-Bold.ttf | `Outfit-Bold` | Outfit | 700 |
| Outfit-ExtraBold.ttf | `Outfit-ExtraBold` | Outfit ExtraBold | 800 |

## DM Mono (existing)

| file | PostScript name | family | weight |
|---|---|---|---|
| DMMono-Regular.ttf | `DMMono-Regular` | DM Mono | 400 |
| DMMono-Medium.ttf | `DMMono-Medium` | DM Mono Medium | 500 |

## Membership-tier typefaces (added)

Converted from the Google Fonts woff2 subsets embedded in `tempus_final_prerelease.html`
(route 1 of the sourcing task — see below), via `fontTools`: brotli-decompress the woff2,
pick the subset whose cmap covers basic Latin, and for the variable-font families cut a
static instance per weight with `fontTools.varLib.instancer` (all axes pinned — none of
these ship as variable fonts here). Bodoni Moda also carries an `opsz` axis (6–96); it was
pinned to its default value (11) since no display-specific optical size was specified —
revisit if the Premier tier card wants a heavier optical cut at large sizes.

### Big Shoulders Display (Essential tier card)

| file | PostScript name | family | weight |
|---|---|---|---|
| BigShouldersDisplay-Regular.ttf | `BigShouldersDisplay-Regular` | Big Shoulders Display | 400 |
| BigShouldersDisplay-Bold.ttf | `BigShouldersDisplay-Bold` | Big Shoulders Display | 700 |

### Cormorant Garamond (Signature tier card)

| file | PostScript name | family | weight/style |
|---|---|---|---|
| CormorantGaramond-Light.ttf | `CormorantGaramond-Light` | Cormorant Garamond | 300 |
| CormorantGaramond-LightItalic.ttf | `CormorantGaramond-LightItalic` | Cormorant Garamond | 300 italic |
| CormorantGaramond-Regular.ttf | `CormorantGaramond-Regular` | Cormorant Garamond | 400 |
| CormorantGaramond-Italic.ttf | `CormorantGaramond-Italic` | Cormorant Garamond | 400 italic |
| CormorantGaramond-Medium.ttf | `CormorantGaramond-Medium` | Cormorant Garamond | 500 |
| CormorantGaramond-MediumItalic.ttf | `CormorantGaramond-MediumItalic` | Cormorant Garamond | 500 italic |
| CormorantGaramond-SemiBold.ttf | `CormorantGaramond-SemiBold` | Cormorant Garamond | 600 |
| CormorantGaramond-SemiBoldItalic.ttf | `CormorantGaramond-SemiBoldItalic` | Cormorant Garamond | 600 italic |
| CormorantGaramond-Bold.ttf | `CormorantGaramond-Bold` | Cormorant Garamond | 700 |
| CormorantGaramond-BoldItalic.ttf | `CormorantGaramond-BoldItalic` | Cormorant Garamond | 700 italic |

### Bodoni Moda (Premier tier card)

| file | PostScript name | family | weight/style |
|---|---|---|---|
| BodoniModa-Regular.ttf | `BodoniModa-Regular` | Bodoni Moda | 400 |
| BodoniModa-Italic.ttf | `BodoniModa-Italic` | Bodoni Moda | 400 italic |
| BodoniModa-Medium.ttf | `BodoniModa-Medium` | Bodoni Moda | 500 |
| BodoniModa-MediumItalic.ttf | `BodoniModa-MediumItalic` | Bodoni Moda | 500 italic |
| BodoniModa-SemiBold.ttf | `BodoniModa-SemiBold` | Bodoni Moda | 600 |
| BodoniModa-SemiBoldItalic.ttf | `BodoniModa-SemiBoldItalic` | Bodoni Moda | 600 italic |
| BodoniModa-Bold.ttf | `BodoniModa-Bold` | Bodoni Moda | 700 |
| BodoniModa-BoldItalic.ttf | `BodoniModa-BoldItalic` | Bodoni Moda | 700 italic |
| BodoniModa-ExtraBold.ttf | `BodoniModa-ExtraBold` | Bodoni Moda | 800 |
| BodoniModa-ExtraBoldItalic.ttf | `BodoniModa-ExtraBoldItalic` | Bodoni Moda | 800 italic |
| BodoniModa-Black.ttf | `BodoniModa-Black` | Bodoni Moda | 900 |
| BodoniModa-BlackItalic.ttf | `BodoniModa-BlackItalic` | Bodoni Moda | 900 italic |

### Syne (Prestige tier card)

| file | PostScript name | family | weight |
|---|---|---|---|
| Syne-Regular.ttf | `Syne-Regular` | Syne | 400 |
| Syne-Medium.ttf | `Syne-Medium` | Syne | 500 |
| Syne-SemiBold.ttf | `Syne-SemiBold` | Syne | 600 |
| Syne-Bold.ttf | `Syne-Bold` | Syne | 700 |
| Syne-ExtraBold.ttf | `Syne-ExtraBold` | Syne | 800 |

### Italiana (Founders tier card)

| file | PostScript name | family | weight |
|---|---|---|---|
| Italiana-Regular.ttf | `Italiana-Regular` | Italiana | 400 |

### Archivo Black (one display use)

| file | PostScript name | family | weight |
|---|---|---|---|
| ArchivoBlack-Regular.ttf | `ArchivoBlack-Regular` | Archivo Black | 400 |

All six families still need their `Info.plist` `UIAppFonts` entries and, per the existing
`TFont` convention, accessors keyed on the PostScript names above.
