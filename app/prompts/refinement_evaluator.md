You are improving a prompt template so that a smaller "student" model produces the same outputs as a larger "reference" model.

The template uses these variables: {{variables}}. Each variable appears in the template as a placeholder, written as the variable name inside double braces, and is replaced with a test case's value before the prompt is sent. Keep every placeholder the current template uses, and don't add new ones.

Current template:
---
{{current_prompt}}
---

Earlier attempts:
{{history}}

For each test case below you are given the variable values, the reference output, and the student output.

{{cases}}

1. For each test case, give a verdict: "match" if the student output is as good as the reference for the task, "partial" if it is close but differs in a way that matters, or "miss" otherwise. Judge substance and format, not wording.
2. Summarise the student's main shortcomings in one or two sentences.
3. Write an improved template that addresses them. Keep the task and output format the same as the reference outputs. Prefer clear instructions and constraints over adding examples. If you don't think the template can be improved further, return it unchanged and set "done" to true.
