"""Offline Spanish <-> English translation (CTranslate2 + SentencePiece with
Argos Translate models). Nothing goes over the network.

Runs with the venv in ~/.local/share/translator (only ctranslate2 + sentencepiece):
    PY=~/.local/share/translator/venv/bin/python
    $PY -I translate.py "Hola, ¿qué tal?"              prints the translation
    $PY -I translate.py --json --from auto -- TEXT      {"from": "es", "to": "en", "text": "..."}
    (--from: auto | es | en; loading + translating takes ~0.2 s, so no daemon)
Models: ~/.local/share/translator/models/<from>_<to>/ (model/ + sentencepiece.model)
"""
import json
import os
import re
import sys

import ctranslate2
import sentencepiece

MODELS = os.path.expanduser("~/.local/share/translator/models")
_loaded = {}


def model(pair):
    """(translator, tokenizer) for "es_en" / "en_es", loaded once."""
    if pair not in _loaded:
        path = os.path.join(MODELS, pair)
        translator = ctranslate2.Translator(os.path.join(path, "model"), device="cpu",
                                            inter_threads=1, intra_threads=4)
        sp = sentencepiece.SentencePieceProcessor(model_file=os.path.join(path, "sentencepiece.model"))
        _loaded[pair] = (translator, sp)
    return _loaded[pair]


# Language guess: Spanish-only characters, then common short words
ES_WORDS = set("el la los las de del que y en un una es por para con no se lo al como más pero "
               "su sus le ya muy también está están hay qué cómo dónde cuándo porque yo tú él "
               "nosotros ellos este esta eso hola gracias bueno".split())
EN_WORDS = set("the a an of and to in is are was were be been it that this for on with as at by "
               "from you he she we they i not but have has do does what how where when why "
               "my your hello thanks good".split())


def detect(text):
    if re.search(r"[ñ¿¡áéíóú]", text.lower()):
        return "es"
    words = re.findall(r"[a-záéíóúñü']+", text.lower())
    es = sum(w in ES_WORDS for w in words)
    en = sum(w in EN_WORDS for w in words)
    return "es" if es > en else "en"


def translate(text, src="auto"):
    src = detect(text) if src == "auto" else src
    dst = "en" if src == "es" else "es"
    translator, sp = model(f"{src}_{dst}")
    out = []
    # Keep line breaks; translate each line's sentences in one batch
    for line in text.split("\n"):
        sentences = [s for s in re.split(r"(?<=[.!?…])\s+", line.strip()) if s]
        if not sentences:
            out.append("")
            continue
        tokens = [sp.encode(s, out_type=str) for s in sentences]
        results = translator.translate_batch(tokens, beam_size=4, replace_unknowns=True)
        out.append(" ".join(sp.decode(r.hypotheses[0]) for r in results))
    return src, dst, "\n".join(out)


def main(args):
    as_json, src, words = False, "auto", []
    i = 0
    while i < len(args):
        if args[i] == "--":                 # everything after it is text
            words += args[i + 1:]
            break
        if args[i] == "--json":
            as_json = True
        elif args[i] == "--from" and i + 1 < len(args):
            src = args[i + 1]
            i += 1
        else:
            words.append(args[i])
        i += 1
    text = " ".join(words)
    if src not in ("auto", "es", "en"):
        sys.exit("--from must be auto, es or en")
    src, dst, out = translate(text[:5000], src)
    print(json.dumps({"from": src, "to": dst, "text": out}, ensure_ascii=False) if as_json else out)


if __name__ == "__main__":
    main(sys.argv[1:])
