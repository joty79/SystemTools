# README Template — Premium Quality

> This template defines the standard structure for generating beautiful, professional README.md files.
> It is AI-agnostic and can be used by any AI assistant (Antigravity, Codex, ChatGPT, Copilot, etc.)
> Place this file in your project root or reference it in your AI system prompt.

---

## Instructions For AI

When asked to generate a README for a project, follow this template exactly.
First scan ALL project files to understand the codebase, then fill in each section below.

---

## Template Structure

### 1. HEADER — Centered badges + title

```markdown
<p align="center">
  <img src="https://img.shields.io/badge/Platform-{VALUE}-{HEX_COLOR}?style=for-the-badge&logo={LOGO}&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Language-{VALUE}-{HEX_COLOR}?style=for-the-badge&logo={LOGO}&logoColor=white" alt="Language">
  <img src="https://img.shields.io/badge/License-{VALUE}-green?style=for-the-badge" alt="License">
</p>

<h1 align="center">{EMOJI} {Project Name}</h1>

<p align="center">
  <b>{One-liner description}</b><br>
  <sub>{Tagline: action → result}</sub>
</p>
```

Use shields.io `for-the-badge` style. Match color to tech stack.

---

### 2. OVERVIEW TABLE — Quick summary with anchor links

```markdown
## ✨ What's Inside

| # | Tool | Description |
|:-:|------|-------------|
| {EMOJI} | **[Name](#anchor)** | One-line description |
```

One row per tool/module. Emoji should match function (🔁=cycle, 📂=files, 🔒=security, ⚡=speed).

---

### 3. TOOL SECTIONS — Repeat for each tool

```markdown
## {EMOJI} {Tool Name}

> One-sentence elevator pitch

### The Problem
- Pain point 1
- Pain point 2
- Pain point 3

### The Solution

Explain approach in 1-2 sentences.

```
ASCII flow diagram showing the architecture/pipeline
```

Why this approach is better in 1 sentence.

### Usage

**From {GUI/context menu}** — step description in italics

**From terminal:**
```{lang}
# Common use case
command

# Advanced use case
command --with-flags
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Name` | `type` | value | What it does |
```

---

### 4. INSTALLATION

```markdown
## 📦 Installation

### Quick Setup
```{lang}
# Install
install command

# Verify
verify command

# Uninstall
uninstall command
```

### Requirements
| Requirement | Details |
|-------------|---------|
| **OS** | version |
| **Runtime** | version |
```

---

### 5. PROJECT STRUCTURE

```markdown
## 📁 Project Structure

```
ProjectName/
├── file.ext          # Short description
├── subdir/
│   └── file.ext      # Short description
└── README.md         # You are here
```
```

Include all files. Add inline comment for each. Use box-drawing chars.

---

### 6. TECHNICAL NOTES — Collapsible Q&A

```markdown
## 🧠 Technical Notes

<details>
<summary><b>Why does X work this way?</b></summary>

2-3 sentence explanation with **bold** key terms.

</details>
```

2-4 collapsible sections covering non-obvious design decisions.

---

### 7. FOOTER — Centered tagline

```markdown
---

<p align="center">
  <sub>Built with {TECH} · {Key feature} · {Constraint}</sub>
</p>
```

---

## Design Rules

1. **Premium feel** — must look professional on GitHub at first glance
2. **Tables > lists** — use tables for structured data (features, params, requirements)
3. **Code blocks always tagged** — specify language (powershell, python, bash, etc.)
4. **Emoji for headers** — consistent, relevant emoji per section
5. **Collapsible for deep dives** — use `<details>` for technical explanations
6. **Short paragraphs** — max 2-3 sentences
7. **ASCII diagrams** — for flows and architecture
8. **Real content only** — no placeholders, no lorem ipsum
9. **Anchor links** — overview table must link to detail sections
10. **Centered header + footer** — HTML `<p align="center">` for visual balance

## Quality Checklist

- [ ] Badges render correctly (valid shields.io URLs)
- [ ] Anchor links work (lowercase, hyphens)
- [ ] Every CLI parameter documented
- [ ] Code examples are copy-pasteable
- [ ] File tree matches actual structure
- [ ] No placeholder text anywhere
- [ ] Correct grammar and spelling (English for README)

---

## Reference Implementation

See `SystemTools/README.md` for a real-world example built from this template.
