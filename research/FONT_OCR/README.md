# Sakura Taisen font OCR

> [!NOTE]
> If you want to use this project as the basis to a translation in your language, you DON'T need to repeat these steps, the extractor already knows the "game-to-unicode" translation.

> [!NOTE]
> I'll often mix "glyph" (the lexical unicode character) and "graphical glyph" (the character, in the game, represented as a series of byte). Until I find a better name to identify the second, you'll have to use your brains.

The game uses one separate font per section. Therefore, extracting/inserting text means working with two files at once:
- `0nnnKNJ.BIN`: a mix between a graphics and a [text table](https://datacrystal.tcrf.net/wiki/Text_Table): it contains graphical glyphs in `16x16` squares, and their internal index is what the engine will use to render them.
- `0nnnTBL.BIN`: contains text, where each 16-bit character references a glyph from its corresponding `0nnnKNJ.BIN` file.

The original translation project used a very pragmatic approach: since they had the text, and the graphics, they simply output graphical rendering of each dialog in the game. For insertion, since they provided their own unique font for all game sections, they could just provide text, and use the corresponding glyphs manually since they knew the index.

It works, but it comes with an issue: the project needs to share images, a LOT of images.

```bash
~/P/H/Webpages/ExtractedData $ ll Dialog/*/*.png | wc -l
  31545
```

For the french translation, I wanted to try another approach:
- extract all the glyphs graphics separately
- give each of them an identity (its sha256)
- map each to its corresponding glyph
- build up a [text table](https://datacrystal.tcrf.net/wiki/Text_Table) of `(sha256)=(glyph)`
- our extractor script would connect the remaining dots and output unicode dialogues in .txt format

## 1. Extract the glyphs

Relevant file: [`sakura_glyphs.py`](./sakura_glyphs.py)

First step: running this will go over all `0nnnKNJ.BIN` files, extract their `16x16` graphical glyphes, and write each in a .bmp file, named `{sha256(bytes)}.bmp`.

We end up with 1693 images, which is NOT THAT BAD ACTUALLY? Just as many kanjis as I need to learn if I want to escape [N6 hell](https://en.wikipedia.org/wiki/Japanese-Language_Proficiency_Test).

## 2. Annotate the kanjis

The most annoying part. The original team's approach actually had a GOOD point: even if a complex kanji gets squeeeeezed into a 16x16 grid, with enough context, it's easy to pick up (for a good japanese speaker anyway).

I didn't feel like writing manually all glyphs, plus there are some kanjis I don't even know, but I didn't want to give AI a free-reign to "Read all those files, OCR them. Make no mistakes".

I decided to go with a three-tier approach:
- use a few OCR models to make a first pass
- manually validate/correct
- output ALL the game dialogues according to the validated characters, with the holes in place, and have an LLM read them and audit/provide insights

### 2.1. OCR is not that hard

I went the [Tesseract](https://en.wikipedia.org/wiki/Tesseract_(software)) way first. Not the fastest, but the most evident. However, I quickly noticed that I could select some glyhs in [Finder](https://en.wikipedia.org/wiki/Finder_(software))'s preview, so a second script ran using Apple's [Vision](https://developer.apple.com/documentation/vision) framework which produced interesting results too.

### 2.2. Always a human behind the wheel

Since I had two corpuses, I decided to run another approach: a glyph_table.db sqlite3 DB, with two tables: one for all 1693 glyphs, with `hash` and `character`, and one for both framework proposals, so I could go through all proposals and see the most efficient first

The work only took around two hours. Clearly some mistakes were made: I may have misread some kanji keys, and I know for a fact that the hiragana and katakana `he` characters got mixed up, along with stuff like `ロ` and `口` (ro katakana, and mout kanji). But it was okay to validate most of the work.

> [!NOTE]
> I recommend using [Jisho's radical search](https://jisho.org/#radical). By this point, you'll easily recognize radicals or keys that are always the same, making it easy to recognize/guess even the worst of gibberish.

#### The Mother Goose

Interesting case: while 99% of dialogues will use one glyph per tile, there is ONE specific word that's 5-glyph long, that's been squeezed into four tiles:

`「マーザーグ」` (followed by a `ㇲ`, making "Mother Goose")

Used only four times in `0100`, `0101`, `0103` and `0108`, this specific word is split over:
- `f38802057446209c5c2cffe33ad7a99c85b86c4aeef98d3b8b04ef8fe9d07111.bmp` => `マ` and half of `ー`
- `9d8940d6dd5b544a7cc3d912280d532620dbae97fb5ae4e246bab4dd45940174.bmp` => half of `ー` and `ザ` with some `ー`
- `1add7e5f77eac542c0fa584c3b08bcd3c3eed766294ba6d5da98101b439a673b.bmp` => finishes `ー` and 1/10ths of `グ`
- `fb65f906842cc1719179677fb83608eb4942caecfb729c1de419dee11a3fea22.bmp` => finished `グ`

That's the only occurrence of those graphical glyphes in the dialogues, so a deliberate choice was made to map them as `マー`, `ザー`, `グ` and `` (empty character).

### 2.3. Let the clanker do it

Final step was done using an LLM. The idea was simple:

> Read all those japanese dialogues files produced by OCR. You must do two passes:
> 
> Check for suspicious text that could indicate an incorrect glypht-to-unicode mapping. Focus on:
> 1. Confusion between visually similar characters:
>    カ/力, ニ/二, タ/夕, エ/工, ベ/べ, 又/叉, etc.
>
> 2. Incorrect kanji in common Japanese expressions.
>
> 3. Inconsistent spellings of character names, locations, or terminology.
>
> 4. Characters that are linguistically implausible in context.
>
> 5. Unresolved glyphs represented as [?XXXX:hash].
>
> 6. Repeated anomalies across different dialogue tables that might
     indicate a systematic mapping error.
>
> - DO NOT modify any files or database entries.
> - DO NOT automatically correct Japanese grammar, spelling, or style.
> - The original game may contain typos, dialects, archaic expressions,
    intentional misspellings, jokes, or slurred speech.
> - A linguistically incorrect sentence is NOT necessarily an OCR error.
> - Do not assume that a plausible correction is the correct original text.
> - Do not recommend changing a glyph's SQLite mapping without checking
>   its other occurrences.

That task helped clearly identify a lot of human errors I had made, and made it easy to guess some from context. It also proved how good the original approach was, since each character was always present in a context and easier to read.

### 2.4. Final pass and validation

By this point, we can double-check the LLM's contextual audit and proposed fixes. Be careful: some of them are plain wrong, and some will probably look okay to both humans and LLMs, but someone who studied their kanjis properly will immediately notice "lmao no you missed that obvious trap".

Now, after a few round of refreshes:
```fish
mkdir -p research/FONT_OCR/dialogues

ludared artifacts list | string match -r '^.*/SAKURA[12]/.*(?:TBL|MES)\.BIN$' | while read -l artifact
    set name (basename $artifact)

    switch $name
        case '*TBL.BIN'
            set font (string replace 'TBL.BIN' 'KNJ.BIN' -- $name)
        case '*MES.BIN'
            set font (string replace 'MES.BIN' 'MES.FNT' -- $name)
    end

    set manifest ""

    for file in research/FONT_OCR/glyph-work/fonts/*.json
        if grep -Fq "/$font\"" $file
            set manifest $file
            break
        end
    end

    if test -z "$manifest"
        echo "Manifeste introuvable : $font"
        continue
    end

    set cached (ludared cache path $artifact)

    echo "Extraction : $name"

    python3 research/FONT_OCR/extract_dialogues.py \
        --manifest $manifest \
        --output research/FONT_OCR/dialogues/(string replace '.BIN' '.txt' -- $name) \
        $cached
end
```

We can check for our missing glyphs:

```bash
$ grep "  # code=" research/FONT_OCR/dialogues/*.txt | wc -l
     136
```

Can you believe we're THIS close to having finished our OCR?

While my opening paragraph may sound like I'm dismissive[^paranoia] of the works of the giants whose shoulder I'm now working from, their work actually helped that step a lot, since I could skim through their exported `ExtractedData/nnnnTBL/nnn.png` to get a proper picture of the missing kanjis with their context, double-check with Jisho, then check if the result made sense as a whole sentence.

## 3. Closing

With all our data, and with [export_font_tables.py](./export_font_tables.py), we can now export proper `.tbl` back into `workspace/tables`, which makes it trivial[^shoulders] to extract the original japanese text

***
[^paranoia]: Or maybe it's just good old fashioned paranoia talking!
[^shoulders]: Of course, this triviality only exists thanks to the original team's work!