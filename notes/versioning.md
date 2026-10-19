# Versioning

Trials need to remain reproducible after the prompt or test suite they ran has been edited. When viewing a trial, Prompt Refinery should be able to answer:

- Which version of the prompt was selected?
- Which version of the test suite was selected?
- Which test cases belonged to that suite version, and in what order?
- What variable values did each test case supply?
- What exact prompt text was sent to the model?
- Can those records still be inspected if the current prompt or test suite changes?

A trial evaluates a single prompt against a test suite, so prompts, test suites, and test cases are versioned.

This design is implemented. The sections below describe the model and the reasoning behind it.

## Possible approaches

### Copy snapshots onto trials and responses

At trial creation, copy the prompt's name and template and the suite's name onto the trial, and copy each test case's variable values and position onto its response.

This is the smallest change and makes each trial self-contained. It is suitable if versions only need to be inspected through trials. Its main limitation is duplication: two trials using the same unchanged prompt or suite produce identical snapshots, and there is no first-class version that can be viewed or compared independently.

### Add version numbers to mutable records

Add a `version` column to prompts, test suites, and test cases, incrementing it on every change, and record those numbers on trials and responses.

Version numbers alone are insufficient because they identify historical data without preserving it. This approach would still require a history table or snapshot containing the old values. It also makes membership and ordering changes difficult to represent as a single coherent suite version.

### Store immutable revisions

Keep `Prompt`, `TestSuite`, and `TestCase` as stable identities, while storing their historical values in immutable revision records. A trial references a prompt revision and a test suite revision rather than the live records.

This requires more tables, but makes versions reusable, inspectable, and comparable. It also separates authoring mutable drafts from the immutable inputs used for execution.

## Model

Prompt Refinery uses an immutable prompt revision, and immutable test suite revisions with explicit revision members:

- `Prompt`
  - Stable identity for a prompt across edits.
  - Has many prompt revisions.
- `PromptRevision`
  - Belongs to a prompt.
  - Has a monotonically increasing version number.
  - Stores the exact prompt name and template text.
  - Is immutable after creation.
- `TestSuite`
  - Stable identity used by the authoring UI.
  - Has many test suite revisions.
- `TestSuiteRevision`
  - Belongs to a test suite.
  - Has a monotonically increasing version number.
  - Stores versioned suite attributes: its name and variables.
  - Is immutable after creation.
- `TestCase`
  - Stable identity for a test case across edits.
  - Has many test case revisions.
- `TestCaseRevision`
  - Belongs to a test case.
  - Has a monotonically increasing version number.
  - Stores the exact variable values for the case.
  - Is immutable after creation.
- `TestSuiteRevisionCase`
  - Belongs to a test suite revision and test case revision.
  - Stores the case position within that suite revision.
  - Captures membership and ordering at that point in time.
- `Trial`
  - Belongs to a prompt revision and a test suite revision. It has no direct prompt or test suite reference; those are reached through the revisions.
- `Response`
  - Belongs to a trial and a `TestSuiteRevisionCase` member.
  - Stores the rendered prompt actually sent to Ollama as well as the generated response.

Responses do not need their own prompt reference. Every response in a trial was rendered from the trial's prompt revision, so storing it once on the trial removes any chance of a response pointing at a different revision.

Referencing the revision member from a response is stronger than referencing only a test case revision. It proves that the test case revision belonged to the trial's suite revision and records its position in that version.

## Creating a trial

Trial creation happens in one database transaction:

1. Resolve or create an immutable revision representing the prompt's current state.
2. Resolve or create an immutable revision representing the test suite's current state, including a revision for each of its test cases.
3. Create the trial referencing both revisions.
4. Create one pending response for every suite revision member, in position order.
5. Render the prompt revision's template with each member's variable values, and store the result on the response before execution.
6. Commit the transaction, then enqueue the background job.

The worker must read prompt and test case data through the trial's revisions or the response's rendered prompt, never through the current mutable `Prompt`, `TestSuite`, or `TestCase`. This prevents edits made while a trial is queued or running from changing its execution.

## When to create revisions

Two policies are reasonable:

- Create a revision on every saved prompt, test suite, or test case edit. This gives complete authoring history but can create many versions while a user is making small changes.
- Create a revision when a trial starts. This creates versions only for states that were actually executed and is simpler for the first implementation.

Prompt Refinery creates revisions at trial time. A content digest avoids duplicating a revision when the prompt or suite has not changed since the previous trial, and the authoring pages compare the digest with the latest revision to show whether there are draft changes. Explicit draft and publish behavior can be added later without changing the trial relationships.

A CSV import is an ordinary edit to a test suite: it adds or replaces test cases, and the next trial captures the result as a new suite revision.

Refinement also creates revisions: when the teacher model proposes an improved prompt, it is stored as a new revision of the same prompt, so the path from the starting prompt to the final prompt is preserved as ordinary revision history. Every iteration runs against the same test suite revision, so results remain comparable across iterations.

## Integrity constraints

The database enforces as much of the revision graph as possible:

- Unique `(prompt_id, version)` and `(prompt_id, content_digest)` on prompt revisions.
- Unique `(test_suite_id, version)` and `(test_suite_id, content_digest)` on test suite revisions.
- Unique `(test_case_id, version)` and `(test_case_id, content_digest)` on test case revisions.
- Unique test case membership and position within a test suite revision.
- Non-null foreign keys from revision members to both revisions.
- Non-null foreign keys from trials to prompt revisions and test suite revisions.
- Non-null foreign keys from responses to trials and revision members.
- Unique `(trial_id, test_suite_revision_case_id)` on responses.
- Restrict deletion of any revision referenced by a trial or response.

Application validation additionally ensures that a response's revision member belongs to the same test suite revision as its trial, and that every variable used by the prompt revision's template is one of the suite revision's variables. Test case validation guarantees each case has a value for every suite variable. The first relationship could be enforced more strongly with composite foreign keys if the added schema complexity is justified.

Revision rows should never be updated or destroyed through normal application code. Database permissions or triggers could enforce immutability later, but model-level protections and restrictive foreign keys are a reasonable starting point for this local application.

## Displaying history

Trial pages display identifiers such as `Explain r5` and `Topics r3`, while always rendering the snapshot text from the referenced revisions. Prompt and test suite history pages show each revision's template, or the suite's membership, ordering, and variable values exactly as they were captured.

Human-readable version numbers are useful for the interface, but record IDs and foreign keys remain the authoritative identity. The content digest can help detect identical versions and verify exported trial data.

## Migration history

Prompt Refinery originally grouped prompts into collections, and trials ran a whole collection through `CollectionRevision` and `CollectionRevisionPrompt` records. When trials moved to a single prompt revision and test suite revision, the existing trials could not be expressed in the new model and were deleted rather than split. Collections and their revisions were then removed entirely, leaving prompts as standalone records; previously soft-deleted prompts became archived prompts.
