# Versioning

Trials need to remain reproducible after a collection or one of its prompts has been edited. When viewing a trial, Prompt Refinery should be able to answer:

- Which version of the collection was selected?
- Which prompts belonged to that version, and in what order?
- What exact prompt text was sent to the model?
- Can those records still be inspected if the current collection changes?

The current `Trial -> Collection` and `Response -> Prompt` relationships identify mutable records. They do not preserve history: changing a prompt's template also changes what an old trial appears to have run.

## Possible approaches

### Copy snapshots onto trials and responses

At trial creation, copy the collection name onto the trial and copy each prompt's name, template, and position onto its response.

This is the smallest change and makes each response self-contained. It is suitable if versions only need to be inspected through trials. Its main limitation is duplication: two trials using the same unchanged collection produce identical snapshots, and there is no first-class collection version that can be viewed or compared independently.

### Add version numbers to mutable records

Add a `version` column to collections and prompts, incrementing it on every change, and record those numbers on trials and responses.

Version numbers alone are insufficient because they identify historical data without preserving it. This approach would still require a history table or snapshot containing the old values. It also makes membership and ordering changes difficult to represent as a single coherent collection version.

### Store immutable revisions

Keep `Collection` and `Prompt` as stable identities, while storing their historical values in immutable revision records. A trial references a collection revision rather than the live collection.

This requires more tables, but makes versions reusable, inspectable, and comparable. It also separates authoring mutable drafts from the immutable inputs used for execution.

## Recommended model

Use immutable collection revisions with explicit revision members:

- `Collection`
  - Stable identity used by the authoring UI.
  - Has many collection revisions.
- `CollectionRevision`
  - Belongs to a collection.
  - Has a monotonically increasing version number.
  - Stores versioned collection attributes such as its name.
  - Is immutable after creation.
- `Prompt`
  - Stable identity for a prompt across edits.
  - Has many prompt revisions.
- `PromptRevision`
  - Belongs to a prompt.
  - Has a monotonically increasing version number.
  - Stores the exact prompt name and template text.
  - Is immutable after creation.
- `CollectionRevisionPrompt`
  - Belongs to a collection revision and prompt revision.
  - Stores the prompt position within that collection revision.
  - Captures membership and ordering at that point in time.
- `Trial`
  - Belongs to a collection revision.
  - May retain a direct collection reference for convenient querying, but the revision is authoritative.
- `Response`
  - Belongs to a trial and a `CollectionRevisionPrompt` member.
  - Stores the rendered prompt actually sent to Ollama as well as the generated response.

Referencing the revision member from a response is stronger than referencing only a prompt revision. It proves that the prompt revision belonged to the trial's collection revision and records its position in that version.

## Creating a trial

Trial creation should happen in one database transaction:

1. Resolve or create an immutable revision representing the collection's current state.
2. Create the trial referencing that collection revision.
3. Create one pending response for every revision member, in position order.
4. Store the fully rendered prompt on each response before execution.
5. Commit the transaction, then enqueue the background job.

The worker must read prompt data through the response's revision member, never through the current mutable `Prompt`. This prevents edits made while a trial is queued or running from changing its execution.

## When to create revisions

Two policies are reasonable:

- Create a revision on every saved collection or prompt edit. This gives complete authoring history but can create many versions while a user is making small changes.
- Create a revision when a trial starts. This creates versions only for states that were actually executed and is simpler for the first implementation.

Creating revisions at trial time is a good initial policy. A content digest can avoid duplicating a revision when the collection has not changed since the previous trial. Explicit draft and publish behavior can be added later without changing the trial relationships.

## Integrity constraints

The database should enforce as much of the revision graph as possible:

- Unique `(collection_id, version)` on collection revisions.
- Unique `(prompt_id, version)` on prompt revisions.
- Unique prompt membership and position within a collection revision.
- Non-null foreign keys from revision members to both revisions.
- Non-null foreign key from trials to collection revisions.
- Non-null foreign key from responses to trials and revision members.
- Unique `(trial_id, collection_revision_prompt_id)` on responses.
- Restrict deletion of any revision referenced by a trial or response.

Application validation should additionally ensure that a response's revision member belongs to the same collection revision as its trial. This relationship can be enforced more strongly with composite foreign keys if the added schema complexity is justified.

Revision rows should never be updated or destroyed through normal application code. Database permissions or triggers could enforce immutability later, but model-level protections and restrictive foreign keys are a reasonable starting point for this local application.

## Displaying history

A trial page should display identifiers such as `Collection v3` and `Prompt v5`, while always rendering the snapshot text from the referenced revisions. Links can lead to read-only revision pages showing the collection membership, ordering, and templates exactly as they were when run.

Human-readable version numbers are useful for the interface, but record IDs and foreign keys remain the authoritative identity. An optional content digest can help detect identical versions and verify exported trial data.

## Migration from the current schema

Existing trials can be migrated by creating one collection revision per distinct historical state that can still be reconstructed. Because current prompt text is mutable, old trials may not be perfectly recoverable. Their initial revisions should therefore be marked as migrated or reconstructed rather than implying stronger historical accuracy than the existing data provides.

For new trials, revision references and rendered prompt snapshots should be mandatory. The existing direct `Trial -> Collection` and `Response -> Prompt` relationships can remain temporarily for compatibility, then be removed once all reads use immutable revisions.
