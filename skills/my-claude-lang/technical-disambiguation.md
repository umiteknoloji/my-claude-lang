# Technical Disambiguation

Gate 1 catches vague adjectives ("fast", "simple", "clean"). But some
ambiguities hide inside words that LOOK precise. This file extends Gate 1
to cover language-specific technical traps.

## Core Principle

When MCL detects a pattern below, it:
- Explains the possible interpretations briefly
- Recommends which one seems most likely based on context
- Asks the developer to confirm or correct
- Final decision is ALWAYS the developer's

Tone: "Based on the context, I think you mean X — but I want to confirm."

## False Friends

Words that look like English but mean something different in another language.

Examples:
- German "kontrollieren" = to check/verify, NOT to control
- German "performant" = high-performing (word doesn't exist in English)
- French "actuellement" = currently, NOT actually
- Spanish "realizar" = to carry out, NOT to realize
- Japanese katakana shifts: "リストア" (risutoa) may mean restore,
  restart, or reset depending on context

MCL response pattern:
- Do NOT silently translate using the English meaning
- DO say: "In English, [word] usually means [English meaning], but in
  [language] it often means [local meaning]. Which one do you mean?"
- If the developer confirms the local meaning → use that in the spec
- If the developer meant the English meaning → use that instead

## Compound Words

Some languages pack multiple concepts into single words. These must
be unpacked before translating.

Examples:
- German: "Zugriffskontrolle" = access + control (could mean
  authentication, authorization, permissions, or rate limiting)
- German: "Datenschutzbeauftragter" = data + protection + officer
- Finnish: compound nouns are extremely long and dense
- Turkish: "kullanıcıyetkilendirme" = user + authorization

MCL response pattern:
- Break the compound into its parts
- Ask which specific technical concept the developer means
- "Zugriffskontrolle could mean several things: authentication (who
  are you?), authorization (what can you do?), or rate limiting (how
  often?). Which one — or a combination?"

## Analogy-Based Requirements

When developers define scope by referencing another product:
"Make it like X" / "X gibi yap" / "Xみたいに"

Examples:
- "淘宝みたいなショッピングシステム" (shopping system like Taobao)
- "LINEみたいなチャット" (chat like LINE)
- "Slack gibi bir mesajlaşma" (messaging like Slack)

MCL response pattern:
- Do NOT accept the analogy as a complete requirement
- DO say: "[Product] has many features. Which specific aspects do
  you want? For example: [list 3-4 key features of that product].
  Which ones are in scope?"
- Break the analogy into concrete, spec-ready features
- Recommend starting with the core feature set, then expanding

## Negation-Based Requirements

When developers define what they DON'T want instead of what they DO want:
"Not like the old version" / "Eski versiyona benzemesin"

MCL response pattern:
- Acknowledge what they don't want
- Ask for the positive requirement: "I understand you don't want
  [old approach]. What should it be instead? For example, [suggest
  2-3 concrete alternatives based on context]."
- Recommend the approach that best fits the project context
- Do NOT proceed with only negative constraints — the spec needs
  positive acceptance criteria

## Passive Voice / Missing Actor

When a requirement hides WHO does the action, WHEN it happens, or HOW
it is triggered by using passive voice or impersonal constructions:

Examples:
- Chinese: "数据需要被处理" (data needs to be processed)
- Russian: "Нужно чтобы данные обрабатывались" (data should be processed)
- German: "Die Daten sollen verarbeitet werden" (data should be processed)
- Turkish: "Veriler işlenmeli" (data should be processed)
- Any language: "[thing] needs to be [done]" without specifying actor

MCL response pattern:
- Identify the missing parameters: WHO (which service/user/cron job),
  WHEN (on request, on schedule, on event), and HOW (batch, stream,
  real-time)
- Ask one at a time: "Who or what should process this data — a
  background job, a user action, or an API call?"
- Do NOT assume the actor — passive voice often means the developer
  hasn't decided yet, and MCL can help them think it through

## Date, Time, and Number Format Ambiguity

When a requirement contains dates, times, or numbers that could be
interpreted differently depending on regional conventions:

Examples:
- "٥/٤" or "5/4" → May 4th (MM/DD) or April 5th (DD/MM)?
- "12:00" → noon or midnight?
- "next Friday" → which Friday exactly?
- "1.000" → one thousand (DE/TR) or one point zero (EN)?
- "biweekly" → every two weeks or twice a week?

MCL response pattern:
- Never assume a date/number format
- Ask explicitly: "When you say 5/4, do you mean April 5th or May 4th?"
- For relative dates: convert to absolute dates after confirmation
- For ambiguous number formats: confirm the intended value
- This is especially critical in specs where deadlines, intervals,
  or thresholds affect system behavior

## Contextual Technical Homonyms

Same technical word, different meaning depending on context:

Examples:
- "cache" = browser cache, application cache, build cache, CDN cache
- "server" = physical server, cloud instance, development server, process
- "migration" = database migration, data migration, cloud migration
- "deploy" = to production, to staging, to local docker
- "test" = unit test, integration test, manual test, UAT
- "接口" (Chinese) = API endpoint, interface, port
- "対応" (Japanese) = handle, support, respond, fix, make compatible

MCL response pattern:
- When a technical term has multiple valid interpretations in the
  current context → ask which one
- "When you say 'cache', do you mean the build cache or the
  application cache? This changes the approach."
- Recommend the most likely interpretation based on the conversation
  context, but let the developer confirm

## Synonym Conflation

When a developer uses two similar technical terms in one request that
could mean the same operation or two distinct operations:

Examples:
- "rollback the migration and revert the schema" — same thing or two steps?
- "restart the server and redeploy" — one operation or two?
- "reset and clear the cache" — same action or different scopes?
- "update and upgrade the dependencies" — patch update or major upgrade?

MCL response pattern:
- Ask: "Are [term1] and [term2] the same operation, or two separate
  steps? For example, rollback could mean undo the DB migration, while
  revert could mean restore the schema file in git — these are different."
- If same → use one term in the spec for clarity
- If different → spec each as a separate step with its own criteria

## Double Negation

When a developer's sentence contains multiple negations that make the
actual intent ambiguous:

Examples:
- Arabic: "مش عايز الصفحة ما تكونش بطيئة" (don't want the page to not be slow)
- French: "Je ne veux pas que ce ne soit pas rapide"
- Any language: stacked negatives that could resolve to positive or negative

MCL response pattern:
- Do NOT guess the resolved meaning
- Restate in positive terms and confirm: "I want to make sure —
  do you want the page to be fast? Or is there a specific performance
  concern you're describing?"
- Let the developer state the positive requirement clearly

## Time Duration Semantics

When a requirement involves time durations, TTL, or expiry that could
have different technical meanings:

Examples:
- "expire time 30min" = TTL from write? TTL from last access (sliding)?
  absolute expiry timestamp?
- "session timeout 1h" = idle timeout or absolute timeout?
- "cache for 5 minutes" = hard TTL or soft TTL with stale-while-revalidate?
- "retry after 3 seconds" = fixed delay, exponential backoff, or jitter?

MCL response pattern:
- Ask which semantic applies: "When you say 'expire in 30 minutes',
  do you mean 30 minutes from creation, or 30 minutes from last access?"
- Recommend the most common pattern for the technology in context
  (e.g., Redis TTL is typically from write), but let the developer confirm

## Priority vs Dependency

When developers specify task order without clarifying the relationship:
"First do X, then do Y" / "Önce X, sonra Y"

MCL response pattern:
- Ask: "Should Y wait for X to be finished (dependency), or is this
  just your preferred order (priority)? I recommend [dependency/priority]
  because [reason]."
- This affects spec structure and execution plan

## Platform-Specific Constraints

When developers mention a platform that has unique technical constraints:

Examples:
- WeChat Mini Programs (no cookies, WXML/WXSS, sandbox)
- iOS App Store (review guidelines, no hot-patching)
- Shopify apps (Liquid templates, API rate limits)

MCL response pattern:
- If MCL knows the platform constraints → mention them proactively:
  "WeChat Mini Programs have specific constraints like [X, Y, Z].
  Should I include these in the spec?"
- If MCL is unsure about platform details → ask: "Are there specific
  platform constraints I should know about for [platform]?"
- Let the developer confirm which constraints apply

## Compliance Implications

When a requirement may conflict with regulations the developer
hasn't mentioned:

Examples:
- "Store all user data in localStorage" + EU context → GDPR concern
- "Log everything the user does" → privacy concern
- "Collect all form fields" → data minimization principle
- "Store passwords in the database" → security concern

MCL response pattern:
- Do NOT assume the developer is unaware
- DO mention the potential concern as a recommendation:
  "I want to flag something: storing personal data in localStorage
  may have GDPR/KVKK implications. I'd recommend [alternative
  approach]. Would you like to discuss this, or do you have it
  covered?"
- The developer decides — MCL flags, does not block
- If the developer says "I have it covered" → accept and proceed
