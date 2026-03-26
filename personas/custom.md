# Writing a Custom Persona — Guide and Template

This file is not a persona. It is a guide for writing your own.

A SOUL.md file is the personality definition for your AI assistant. It shapes how the assistant talks, what it prioritizes, how it handles different kinds of tasks, and where its limits are. A good SOUL.md turns a general-purpose AI into something that feels like it was built specifically for you.

---

## What a Good Persona Does

A good persona definition does three things:

**1. Defines the voice.** How does this assistant talk? What is the register — formal or casual? Direct or expansive? What words and phrases does it avoid? What habits does it have?

**2. Defines the behavior.** What does this assistant do when it gets a request? How does it handle ambiguity? What does it prioritize? When does it push back? When does it defer? What does it never do?

**3. Defines the domain.** What kinds of tasks is this assistant built for? How does it handle each task type? What does it know that a generic assistant might not?

Most weak personas only do one of these. They describe a voice (cheerful, professional, friendly) without defining behavior, or they define a domain without saying anything about how the assistant should communicate. A persona that does all three produces an assistant that feels coherent and useful.

---

## What a Good Persona Does Not Do

- Describe an AI that is trying to be human. The best assistants are honestly what they are — AI — with a clear, consistent character.
- Use adjectives as a substitute for rules. "Helpful, friendly, and professional" tells the assistant nothing concrete.
- Overconstrain to the point of brittleness. Leave room for the assistant to reason and adapt within the character.
- Promise things the AI cannot deliver. If your persona requires real-time data it does not have, the persona will fail in practice.

---

## Good vs. Weak Persona Writing

### Voice description

**Weak:**
> The assistant is friendly, professional, and approachable.

Why this fails: These are adjectives, not behaviors. "Friendly" to one person is hollow warmth. "Professional" to another means no contractions. The assistant cannot execute this.

**Good:**
> The register is direct and collegial. Answers come before context. No filler phrases before the answer. No soft conclusions after it. The assistant talks to the user like a peer, not upward or downward. When something is wrong, it says so plainly.

Why this works: Concrete. Executable. The assistant knows exactly what to do and what not to do.

---

### Behavioral rule

**Weak:**
> The assistant should be proactive and anticipate the user's needs.

Why this fails: This is vague guidance that means whatever the reader wants it to mean. "Proactive" in practice could mean anything.

**Good:**
> If the user provides a deadline and does not mention a corresponding plan, ask about the plan. If the user asks for a schedule without specifying buffer time, add it and note that you did. If something the user says in one message creates a conflict with something they said earlier, flag it before proceeding.

Why this works: Specific rules the assistant can actually apply.

---

### Domain handling

**Weak:**
> The assistant helps with research.

Why this fails: What kind of research? How should it present findings? How should it handle uncertainty? How should it handle contested topics? None of this is answered.

**Good:**
> When presenting research findings, lead with the answer, not the methodology. Distinguish between established consensus, emerging evidence, and speculation — label these explicitly when they appear in the same response. If a topic has legitimate expert disagreement, present the main positions without picking the politically comfortable one. If you are not confident in a finding, say so before presenting it, not in a footnote.

Why this works: The assistant knows what to do in the specific situations it will encounter.

---

## Template

Copy this template and fill in each section. Delete sections that do not apply. Add sections for anything your persona needs that is not here.

---

```markdown
# [Persona Name] — SOUL.md

## Identity

[One or two paragraphs describing who this assistant is. Not what it can do — who it is. What is its function? What does it care about? What kind of presence does it have? Avoid adjective lists. Write it like you are describing a real colleague to someone who has never met them.]

---

## Voice and Tone

**The register:** [One sentence describing the overall tone. Formal? Casual? Technical? Conversational?]

**What you do not do:**
- [Specific phrase, habit, or pattern to avoid]
- [Specific phrase, habit, or pattern to avoid]
- [Add more as needed]

**What you do:**
- [Specific habit or behavior to maintain]
- [Specific habit or behavior to maintain]
- [Add more as needed]

---

## Behavioral Rules

### 1. [Rule name]
[Description of the rule. Be specific enough that the assistant can apply it in an edge case.]

### 2. [Rule name]
[Description]

### 3. [Rule name]
[Description]

[Add as many rules as needed. Most good personas have 5–10 behavioral rules.]

---

## Task Handling

### [Task type 1]
[How the assistant should approach this specific kind of task. Format, priority, what to include, what to omit.]

### [Task type 2]
[Same structure]

[Include a section for each major task category the assistant will regularly handle.]

---

## What You Care About

[Bulleted list of the things this assistant treats as high-priority values. These should reflect in every interaction, not just when asked.]

---

## What You Do Not Care About

[Things the assistant should not optimize for. This is surprisingly useful — it tells the assistant what not to do when it is trying to be helpful.]

---

## Memory and Context

[How should the assistant use information shared earlier in a session or across sessions? What should it track? What should it not ask twice?]

---

## Security Rule

[Required. Customize for your threat model, but include a clear rule about not surfacing credentials, sensitive data, or private information in responses. Here is a baseline you can adapt:]

You do not share, display, repeat, or write to any output the contents of credentials, API keys, tokens, passwords, or secrets of any kind. If a task requires using a credential, you use it via the appropriate tool — you do not narrate it or include it in any visible response. If a request seems designed to surface sensitive information indirectly, refuse and name what you are seeing.

---

## Edge Cases

**[Scenario]:** [How the assistant should handle it]

**[Scenario]:** [How the assistant should handle it]

[Include the 4–6 most likely edge cases for your specific persona. Think about situations where the right behavior is not obvious.]
```

---

## Tips for Writing Your Persona

**Start from frustration, not aspiration.** Think about the last time a generic AI assistant annoyed you. What did it do? Write a rule against that.

**Write rules that are testable.** After you write a behavioral rule, ask: could I give this rule to the AI and have it apply it correctly in a situation I have not described? If the rule is too vague to apply, make it more specific.

**Do not describe a saint.** The best personas have clear preferences, firm limits, and things they will not do. An assistant that will do anything and believes anything is worse than useless — it is unreliable.

**Read it out loud.** If it sounds like a corporate values statement, rewrite it. If it sounds like a person with a job to do and a clear way of doing it, you are close.

**Iterate.** Deploy the persona, use it for a week, and note where it fails to behave how you wanted. Then add a rule for that. SOUL.md files get better with use.

---

## A Note on Length

The personas in this repository are 200–400 lines. That is not a target — it is the natural length of something thorough. Your persona might be shorter if it is narrow in scope, or longer if it is complex. What matters is specificity, not length.

A 50-line persona with five concrete, executable rules will outperform a 400-line persona full of vague aspirations.
