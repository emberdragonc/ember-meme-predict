# Phase 0: Planning (Get Shit Done)

Before touching any code or design docs, answer these questions ruthlessly.

## 1. WHAT - Define the Problem

### The One-Liner
> What is this in one sentence a 5-year-old could understand?

Example: "People give money to projects, get it back if the project fails."

### The Problem Statement
- What pain does this solve?
- Who has this pain?
- How do they solve it today?
- Why is that solution inadequate?

### Success Looks Like
- [ ] Specific outcome 1
- [ ] Specific outcome 2
- [ ] Specific outcome 3

## 2. WHY - Validate the Need

### Why Now?
- What changed that makes this possible/necessary?
- Why hasn't someone built this already?
- If they have, why build another?

### Why Me?
- Am I the right builder for this?
- Do I have the skills needed?
- What do I need to learn?

### Why This Approach?
- What alternatives did I consider?
- Why is this approach better?
- What are the tradeoffs?

## 3. WHO - Identify Stakeholders

### Primary Users
- Who will use this most?
- What do they care about?
- What would make them NOT use it?

### Secondary Users
- Who else interacts with this?
- What do they need?

### Adversaries
- Who might try to exploit this?
- What would they try to do?
- How much would they spend to attack?

## 4. SCOPE - Draw the Lines

### In Scope (MVP)
- [ ] Core feature 1
- [ ] Core feature 2
- [ ] Core feature 3

### Out of Scope (V1)
- ❌ Feature we won't build yet
- ❌ Nice-to-have we're deferring
- ❌ Edge case we're ignoring

### Non-Goals
- This is NOT trying to solve X
- This is NOT competing with Y
- This will NOT handle Z

## 5. RISKS - Face Reality

### Technical Risks
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| ? | High/Med/Low | High/Med/Low | How to reduce |

### Security Risks
| Attack Vector | Likelihood | Impact | Mitigation |
|---------------|------------|--------|------------|
| ? | High/Med/Low | High/Med/Low | How to prevent |

### Business Risks
- What if no one uses it?
- What if a competitor ships first?
- What if requirements change?

## 6. DEPENDENCIES - Map the Terrain

### External Dependencies
- [ ] Contracts I'm building on (OpenZeppelin, etc.)
- [ ] Oracles or external data
- [ ] Other protocols

### Knowledge Dependencies
- [ ] What do I need to learn first?
- [ ] Who can I ask for help?
- [ ] What docs should I read?

### Resource Dependencies
- [ ] Gas costs / deployment costs
- [ ] Time required
- [ ] Audit budget

## 7. MILESTONES - Break It Down

### Milestone 1: [Name]
- **Goal:** What's done when this is complete?
- **Deliverables:** Specific outputs
- **Time:** Estimated hours/days
- **Done when:** Acceptance criteria

### Milestone 2: [Name]
...

### Milestone 3: [Name]
...

## 8. DECISION LOG

Track key decisions and why:

| Decision | Options Considered | Choice | Rationale | Date |
|----------|-------------------|--------|-----------|------|
| ? | A, B, C | B | Because... | YYYY-MM-DD |

## 9. OPEN QUESTIONS

Things I still need to figure out:
- [ ] Question 1
- [ ] Question 2
- [ ] Question 3

## 10. GO/NO-GO

Before proceeding to Design, confirm:

- [ ] Problem is clearly defined
- [ ] Scope is bounded and achievable
- [ ] Risks are identified and acceptable
- [ ] I have (or can get) required skills
- [ ] Timeline is realistic
- [ ] Success criteria are measurable

**If any checkbox is unchecked, DO NOT PROCEED. Resolve it first.**

---

## Quick Template

For faster projects, use this condensed version:

```markdown
# [Project Name] - Planning

## One-Liner
> [Simple description]

## Problem
[Who] has [problem] because [reason].

## Solution
[What we're building] that [key benefit].

## Scope
IN: [feature 1], [feature 2], [feature 3]
OUT: [deferred 1], [deferred 2]

## Risks
1. [Risk] → [Mitigation]
2. [Risk] → [Mitigation]

## Milestones
1. [Milestone] - [Time estimate]
2. [Milestone] - [Time estimate]

## Go/No-Go
[x] Problem clear
[x] Scope bounded
[x] Risks acceptable
[x] Skills available
[x] Time realistic

→ PROCEED TO DESIGN
```

---

*"Weeks of coding can save hours of planning."*
