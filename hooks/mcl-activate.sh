#!/bin/bash
# MCL Auto-Activation Hook
# Detects non-English input and reminds Claude to activate MCL protocol.
# Install: see setup.sh or README for instructions.

input=$(cat)
prompt=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null)

if [ -z "$prompt" ]; then
  exit 0
fi

# Detect non-Latin script characters (letters only, not symbols/emoji)
non_english=$(echo "$prompt" | python3 -c "
import sys, unicodedata
text = sys.stdin.read()
for char in text:
    cat = unicodedata.category(char)
    if cat.startswith('L') and ord(char) > 127:
        name = unicodedata.name(char, '')
        # Skip common programming symbols that happen to be letters
        if 'EMOJI' not in name:
            print('yes')
            sys.exit(0)
# Also check for Turkish/accented Latin characters used in natural language
import re
# Turkish: ğşıöüçĞŞİÖÜÇ, German: äöüßÄÖÜ, French: àâçéèêëîïôùûüÿœæ, etc.
if re.search(r'[ğşıçĞŞİÇäßàâèéêëîïôùûœæñ]', text):
    print('yes')
    sys.exit(0)
# Common non-English function words (catches ASCII-only non-English)
# Turkish, German, French, Spanish, Portuguese, Italian, Dutch, Polish
words = text.lower().split()
markers = {
    # Turkish
    'bir', 've', 'ile', 'ama', 'için', 'bu', 'su', 'ne', 'nasil',
    'yap', 'et', 'ol', 'var', 'yok', 'mi', 'mu', 'lazim', 'istiyorum',
    'ekle', 'sil', 'degistir', 'duzelt', 'iste', 'calis', 'hemen',
    'sonra', 'once', 'simdi', 'tamam', 'evet', 'hayir', 'neden',
    'ben', 'sen', 'biz', 'siz', 'bunu', 'sunu', 'onu', 'onun',
    'bitir', 'baslat', 'kur', 'ac', 'kapat', 'goster', 'bak',
    'lutfen', 'gerek', 'gerekiyor', 'yapilsin', 'olsun', 'gibi',
    'kadar', 'daha', 'cok', 'az', 'hep', 'hic', 'sadece',
    # German
    'ein', 'eine', 'und', 'aber', 'oder', 'nicht', 'ist', 'sind',
    'mach', 'macht', 'soll', 'wenn', 'dann', 'auch', 'noch',
    'der', 'die', 'das', 'ich', 'wir', 'bitte', 'jetzt', 'hier',
    'kein', 'keine', 'nur', 'erstelle', 'zeige', 'seite',
    # French
    'une', 'les', 'des', 'est', 'sont', 'mais', 'avec', 'pour',
    'pas', 'que', 'qui', 'dans', 'faire', 'fait',
    'cette', 'ces', 'mon', 'ton', 'notre', 'votre',
    # Spanish
    'una', 'los', 'las', 'pero', 'como', 'para', 'por', 'con',
    'hacer', 'esta', 'esto', 'ese',
    'crear', 'quiero', 'necesito', 'tiene', 'puede',
    # Portuguese
    'uma', 'nos', 'nas', 'mas', 'como', 'fazer', 'isso',
    'criar', 'quero', 'preciso', 'pode', 'tem',
    # Italian
    'gli', 'sono', 'anche', 'questo', 'quella', 'fare',
    'crea', 'pagina', 'voglio', 'devo', 'puoi', 'questa', 'quello',
    'molto', 'cosa', 'perche', 'funziona', 'tutti',
    # Dutch
    'een', 'het', 'ook', 'maar', 'niet', 'voor', 'naar',
    'maak', 'dit', 'dat', 'wel', 'nog', 'moet', 'kan',
    # Indonesian/Malay
    'saya', 'anda', 'ini', 'itu', 'dan', 'atau', 'dari', 'buat',
    'halaman', 'tolong', 'mau', 'sudah', 'belum', 'akan', 'bisa', 'harus',
}
if len(set(words) & markers) >= 2:
    print('yes')
    sys.exit(0)
print('no')
" 2>/dev/null)

if [ "$non_english" = "yes" ]; then
  cat <<'HOOK_OUTPUT'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "NON-ENGLISH INPUT DETECTED. You MUST activate the my-claude-lang (MCL) skill NOW. This is mandatory, not optional. Follow MCL protocol: (1) Respond in the developer's language, (2) Apply Gate 1 — resolve ambiguity before translating, (3) Apply Gate 2 — challenge vague terms, (4) Apply Gate 3 — explain, don't just translate, (5) Gather all parameters (intent, constraints, success_criteria, context) before writing any code, (6) Ask questions ONE AT A TIME. Read the full MCL skill files for detailed rules. NEVER skip MCL when non-English input is detected."
  }
}
HOOK_OUTPUT
fi

exit 0
