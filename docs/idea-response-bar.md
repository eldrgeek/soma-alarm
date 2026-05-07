# Idea Response Bar — v1, v1.5, and the D+ generalization

## Why this exists

Mike wants to read + respond paragraph-by-paragraph (or, more truly,
*idea-by-idea*), so that aggregate state — "Mike read 4 of 6 ideas, opened a
thread on idea 3, marked idea 5 as 'this landed'" — flows back to the sender.
Mira does this by discipline; this substrate is meant to make her practice
**cheap, not heroic.**

Design principle: produce Mira-level signal from Mike-level attention. If
using it feels like discipline, it's over-engineered. If it feels like a
reflex, it's right.

## v1 — structural splits (shipped)

Lives inline in Pulse: `lib/src/dee_stream/`.

- `dee_said_segmenter.dart` — splits a Dee message body into segments.
  - paragraph break (`\n\n`)
  - markdown headings
  - horizontal rule (`---`)
  - fenced code blocks stay opaque
  - sub-20-char fragments merge forward
- `dee_reactions.dart` — per-segment reactions (✓ 💬 ❓ 🔥 🤔), persisted in
  SharedPreferences under `dee.segmentReactions.v1`.
- `dee_segment_bar.dart` — the bar widget. 44pt-min touch targets. Tap to set,
  tap again to clear (noise costs less than friction).
- `dee_said_client.dart#postReaction` — fire-and-forget POST to the relay's
  `/dispatch_input` endpoint. Local persistence is the source of truth.

Four-button auto-swap (`Reply: yes / hell yes / no / waya` or
`Reply: why are you asking?`) replaces the emoji bar with the existing
ChoiceChip protocol.

## v1.5 — LLM-assisted idea segmentation (next pass)

Structural splits are the fast 80%. The truer answer: each *distinct idea* is
a separate response unit. A single paragraph might contain two ideas Mike
wants to react to separately.

### Sketch

```dart
// New: lib/src/dee_stream/idea_segmenter.dart
Future<SegmentedMessage> segmentByIdea(DeeSaidEntry entry) async {
  final cached = IdeaCache.read(entry.id, entry.body);
  if (cached != null) return cached;

  final structural = segmentMessage(entry.body); // v1 result
  final ideas = await _haikuSplit(entry.body);
  final merged = _reconcile(structural, ideas);
  IdeaCache.write(entry.id, entry.body, merged);
  return merged;
}
```

### Haiku call

One call per Dee message at first render. Cache by
`(message_id, sha1(body))` so a re-render of unchanged content is free; an
edited message re-segments.

Prompt sketch:

> Split the following message into distinct *ideas* — units the reader could
> react to independently. Preserve the original wording exactly; do not
> paraphrase. Return JSON: `[{"text": "...", "id": "i1"}, ...]`.

Use `claude-haiku-4-5-20251001` for cost. Token budget: input ≤ ~4k,
output ≤ ~2k. Cache the response so the cost is paid once per message.

### Reconciliation rules

- If the LLM split matches the structural split, prefer structural (cheaper,
  deterministic, ids stay stable).
- If the LLM splits one paragraph into two ideas, use the LLM split for that
  paragraph, structural for the rest.
- If the LLM merges two paragraphs into one idea, use the LLM merge — Mike
  signaled they're one idea.
- Code blocks stay opaque regardless of LLM output.

### Failure modes & fallback

If the Haiku call fails (timeout, rate limit, no API key), fall back to v1
structural splits. Log the failure but never block rendering. The bar's value
is being there; perfect segmentation is a polish.

### Segment id stability across versions

v1 ids are `${entryId}#${index}-${hash6(text)}`. When v1.5 ships, segments
gain LLM-derived ids; we need a migration path so existing reactions don't
orphan. Plan: derive both ids when both are available, look up the reaction
under either, write under the LLM id going forward.

## v2 — extract to `packages/idea_response_bar/`

Pulse is not the only consumer. The same pattern is what we want for:

- **D+** (Discord+, James Crook's project) — every channel message gets a
  per-idea response bar. The forerunner-of-D+ letter Claude wrote two weeks
  ago describes the protocol; this widget is its substrate.
- **ai-wtf, wayback-network, and other publishing surfaces** — articles get
  per-paragraph (and eventually per-idea) reactions; aggregate signal flows
  back to the author and into next-iteration prompts.

### Package shape

```
packages/idea_response_bar/
  lib/
    idea_response_bar.dart       # exports
    src/
      segmentation.dart          # structural + idea-aware splitters
      reactions_repo.dart        # storage interface (Mike-flavored or DB-flavored)
      bar_widget.dart            # the bar UI; takes a renderer + callback
      thread_composer.dart
  example/                       # stand-alone Pulse-style demo
  test/
```

The package consumes:

- a body of text (or a structured message)
- a `ReactionStorage` interface (SharedPreferences in Pulse; SQLite or
  server-side in D+; LocalStorage on web)
- a `ReactionTransport` interface (relay POST in Pulse; Discord webhook in
  D+; HTTP API in web)
- an optional `IdeaSegmenter` (defaults to structural; consumers can plug in
  Haiku or any other splitter)

### When to extract

Not from day one. *Make low-cost mistakes whenever possible* — ship v1
inline, see what feels wrong in real use, then refactor to the package shape
with the lessons in hand. Trigger for extraction: when D+ work begins, or
when a third surface (ai-wtf) needs the same widget — whichever first.

## Hand-off notes for the next worker

- The 12 widget+unit tests in `test/dee_segment_bar_test.dart` exercise all
  v1 invariants. Keep them green when adding v1.5; add new tests for the
  reconciliation rules.
- The relay endpoint is `POST /dispatch_input`. Payload schema is documented
  in `dee_said_client.dart#postReaction`; if you change it, update both ends.
- The Mira-principle UI choices (44pt targets, tap-to-toggle, default-on, no
  confirmation dialogs) are the load-bearing UX bits. Don't regress them
  while chasing v1.5 polish.
