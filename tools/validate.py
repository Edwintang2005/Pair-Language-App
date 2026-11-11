#!/usr/bin/env python3
"""Check content/sessions.json, words-de.json and words-zh.json are consistent.

Usage: python3 tools/validate.py [content_dir]
Exits non-zero if any error is found. Warnings don't fail the run.
"""
import json
import re
import sys
import unicodedata
from pathlib import Path

POS = {"noun", "verb", "adjective", "adverb", "pronoun", "interjection", "phrase", "particle",
       "numeral", "conjunction", "preposition"}
WORDS_PER_SIDE = 5
ID_RE = re.compile(r"^(de|zh)-[a-z0-9]+(-[a-z0-9]+)*$")

errors, warnings = [], []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def load(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        err(f"{path.name}: cannot parse: {e}")
        return None


def check_common(w, lang):
    wid = w.get("id", "<missing id>")
    for field in ("id", "word", "gloss", "pos", "examples", "tip"):
        if not w.get(field):
            err(f"{wid}: missing '{field}'")
    if not ID_RE.match(wid) or not wid.startswith(lang + "-"):
        err(f"{wid}: id must look like '{lang}-some-slug'")
    if w.get("pos") not in POS:
        err(f"{wid}: unknown pos '{w.get('pos')}'")
    for i, ex in enumerate(w.get("examples") or []):
        if not ex.get("text") or not ex.get("english"):
            err(f"{wid}: example {i} needs 'text' and 'english'")
        if lang == "zh" and not ex.get("pinyin"):
            err(f"{wid}: example {i} needs 'pinyin'")
    return wid


def appears_in_examples(w, lang):
    """The word itself must show up in its example sentence, exactly as it's taught."""
    word = w.get("word", "")
    for ex in w.get("examples") or []:
        text = ex.get("text", "")
        if lang == "zh":
            if word in text:
                return True
        elif re.search(r"(?<![^\W\d_])" + re.escape(word.lower()) + r"(?![^\W\d_])", text.lower()):
            return True
    return False


def warn_digits(w, wid):
    """Numbers in examples should be written as words: text-to-speech and the speaking check both
    handle words more reliably, and learners need to hear the word."""
    for ex in w.get("examples", []):
        if re.search(r"\d", ex.get("text", "")):
            warn(f"{wid}: example has digits; write the number as a word")


def check_de(w):
    wid = check_common(w, "de")
    warn_digits(w, wid)
    if not appears_in_examples(w, "de"):
        err(f"{wid}: '{w.get('word')}' doesn't appear in its example sentence")
    pos = w.get("pos")
    if pos == "noun":
        n = w.get("noun") or {}
        if n.get("gender") not in {"m", "f", "n"}:
            err(f"{wid}: noun needs noun.gender of m/f/n")
        if "plural" not in n:
            err(f"{wid}: noun needs noun.plural (null if none)")
        if "hint" in n and (not isinstance(n["hint"], str) or not n["hint"].strip()):
            err(f"{wid}: noun.hint must be a non-empty string")
        if not w.get("word", " ")[0].isupper():
            err(f"{wid}: German nouns are capitalised")
    elif "noun" in w:
        err(f"{wid}: 'noun' block on a non-noun")
    if pos == "verb":
        v = w.get("verb") or {}
        for f in ("present3sg", "participle", "auxiliary"):
            if not v.get(f):
                err(f"{wid}: verb needs verb.{f}")
        if v.get("auxiliary") not in {"haben", "sein"}:
            err(f"{wid}: verb.auxiliary must be haben or sein")
    elif "verb" in w:
        err(f"{wid}: 'verb' block on a non-verb")


PUNCTUATION = ",.?!:;\"'„“”‚‘’«»…–—，。？！、：；“”‘’《》（）"


def is_vowel(c):
    return unicodedata.normalize("NFD", c)[0].lower() in "aeiou"


def pinyin_char_count(word):
    """Characters a pinyin word stands for: one per syllable (runs of vowels), plus 儿 for erhua.
    Mirrors SentenceBuilder.characterCount in the app."""
    count = 0
    for part in word.split("'"):
        prev = False
        for c in part:
            v = is_vowel(c)
            if v and not prev:
                count += 1
            prev = v
    letters = word.lower()
    if len(letters) >= 2 and letters[-1] == "r":
        before = letters[-2]
        if not is_vowel(before) or unicodedata.normalize("NFD", before)[0] != "e":
            count += 1
        elif len(letters) >= 3 and letters[-3] != "'" and not is_vowel(letters[-3]):
            count += 1
    return count


def pinyin_lines_up(example):
    """The "Build the sentence" drill cuts Chinese sentences where the pinyin has spaces, so the
    pinyin's syllables have to match the characters one for one."""
    text = [c for c in example.get("text", "") if c not in PUNCTUATION and not c.isspace()]
    words = [t.strip(PUNCTUATION) for t in example.get("pinyin", "").split()]
    return sum(pinyin_char_count(t) for t in words if t) == len(text)


def check_zh(w):
    wid = check_common(w, "zh")
    warn_digits(w, wid)
    if not appears_in_examples(w, "zh"):
        err(f"{wid}: '{w.get('word')}' doesn't appear in its example sentence")
    for ex in w.get("examples", []):
        if ex.get("pinyin") and not pinyin_lines_up(ex):
            err(f"{wid}: example pinyin doesn't line up with the characters (one syllable per character, "
                f"apostrophes between syllables that could run together: Wǎn'ān)")
    if not w.get("pinyin"):
        err(f"{wid}: missing 'pinyin'")
    elif re.search(r"\d", w["pinyin"]):
        err(f"{wid}: use tone marks, not tone numbers, in pinyin")
    chars = w.get("characters")
    if chars:
        if "".join(c.get("char", "") for c in chars) != w.get("word"):
            err(f"{wid}: characters don't spell out '{w.get('word')}'")
        for c in chars:
            if not c.get("pinyin") or not c.get("meaning"):
                err(f"{wid}: each character needs pinyin and meaning")
    elif len(w.get("word", "")) > 1:
        warn(f"{wid}: multi-character word has no 'characters' breakdown")
    mw = w.get("measureWord")
    if mw is not None:
        if not mw.get("word") or not mw.get("pinyin"):
            err(f"{wid}: measureWord needs word and pinyin")
        also = mw.get("also", [])
        if not isinstance(also, list) or not all(isinstance(a, str) and a for a in also):
            err(f"{wid}: measureWord.also must be a list of measure words")
        elif mw.get("word") in also:
            err(f"{wid}: measureWord.also repeats the main measure word")
    counting = w.get("counting")
    if counting is not None and counting not in {"direct", "none"}:
        err(f"{wid}: counting must be 'direct' or 'none'")
    if w.get("pos") == "noun":
        # The measure-word drill needs to know how every noun is counted.
        if (mw is None) == (counting is None):
            err(f"{wid}: nouns need exactly one of measureWord or counting")
    elif counting is not None:
        err(f"{wid}: 'counting' is for nouns only")


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "content"
    sessions = load(root / "sessions.json")
    words = {"de": load(root / "words-de.json"), "zh": load(root / "words-zh.json")}
    if errors:
        return report()

    by_id = {"de": {}, "zh": {}}
    for lang, data in words.items():
        if data.get("language") != lang:
            err(f"words-{lang}.json: 'language' should be '{lang}'")
        for w in data.get("words", []):
            (check_de if lang == "de" else check_zh)(w)
            wid = w.get("id")
            if wid in by_id[lang]:
                err(f"{wid}: duplicate id")
            by_id[lang][wid] = w

    used = set()
    for i, s in enumerate(sessions.get("sessions", []), start=1):
        label = f"session {s.get('number')}"
        if s.get("number") != i:
            err(f"{label}: expected number {i} (numbers must be 1-based and contiguous)")
        for field in ("theme", "conversationStarter"):
            if not s.get(field):
                err(f"{label}: missing '{field}'")
        for lang in ("de", "zh"):
            ids = s.get(lang) or []
            if len(ids) != WORDS_PER_SIDE:
                err(f"{label}: {lang} has {len(ids)} words, expected {WORDS_PER_SIDE}")
            for wid in ids:
                if wid not in by_id.get(lang, {}):
                    err(f"{label}: unknown {lang} id '{wid}'")
                if wid in used:
                    err(f"{label}: '{wid}' already used in an earlier session")
                used.add(wid)

    for lang, ids in by_id.items():
        for wid in ids:
            if wid not in used:
                warn(f"{wid}: not assigned to any session")

    n = len(sessions.get("sessions", []))
    print(f"{n} sessions, {len(by_id.get('de', {}))} German words, {len(by_id.get('zh', {}))} Chinese words")
    return report()


def report():
    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error:   {e}")
    print("OK" if not errors else f"{len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
