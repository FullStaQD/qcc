<div align="center">
  <img src="https://img.shields.io/badge/Status-Early_Development-red?style=for-the-badge" alt="Early Development">
</div>

---

### **⚠️ Notice: Early Development Phase**

This project is currently in its **infant stages**, so we are keeping things "in-house" for now while we find our footing.

- **No External PRs:** We aren't accepting outside contributions just yet.
- **Coming Soon:** We plan to open the gates to the community once the foundation is solid.

**Stay tuned—we'd love your help later!**

---

# Contributing

## Types of Contributions

TODO

## Guidelines

Please adhere to the following guidelines to help the project grow sustainably.

### Core Guidelines

- ["Commit early and push often"](https://www.worklytics.co/blog/commit-early-push-often).
- Write meaningful commit messages.
- Focus on a single feature or bug at a time and only touch relevant files.
  Split multiple features into separate contributions.
- Add tests for new features to ensure they work as intended.
- Document new features.
- Add tests for bug fixes to demonstrate the fix.
- Document your code thoroughly and ensure it is readable.
- Keep your code clean by removing debug statements, leftover comments, and unrelated code.
- Check your code for style and linting errors before committing.
- Follow the project's coding standards and conventions.
- Be open to feedback and willing to make necessary changes based on code reviews.

### C++ guidelines

As an LLVM/MLIR base project we mostly follow their guidelines.
We also follow Google's guidelines but LLVM guidelines take precedence.

As a particular example, we follow [LLVMs recommendation](https://llvm.org/docs/CodingStandards.html#include-style)
on include order from most specific (top) to least specific (bottom).

When it comes to includes with angle brackets vs quoted includes we follow Google's recommendation:
Headers should only be included using an angle-bracketed path if the library requires you to do so.
In particular, the following headers require angle brackets:

- C and C++ standard library headers (e.g., <stdlib.h> and ).
- POSIX, Linux, and Windows system headers (e.g., <unistd.h> and <windows.h>).
- In rare cases, third_party libraries (e.g., <Python.h>).

See also our `.clang-format` file.

Prefer an `#include` over a forward declaration; only forward-declare a type where upstream LLVM/MLIR
does so for that same type, and justify it in a brief comment at the declaration.

Also note that MLIR based projects typically do not _strictly_ follow const correctness.
The details can be found in [MLIR on the usage of 'const'](https://mlir.llvm.org/docs/Rationale/UsageOfConst/).
The slightly simplified gist is as follows:

- Do _not_ use `const` in combination with IR objects like `Operation*` or `Value`.
- _Try_ to follow const correctness for non-IR objects (e.g. `SmallVector`, `StringRef`).
- But even then do not worry too much about adding `const`, leave it out if in doubt.

That being said: do not take this guideline as a justification to drop const correctness in _other_ projects.
This is a particular quirk of MLIR based projects.

### Pull Request Workflow

- Create PRs early.
  Work-in-progress PRs are welcome; mark them as drafts on GitHub.
- Use a clear title, reference related issues by number, and describe the changes.
  Follow the PR template; only omit the issue reference if not applicable.
- All CI checks must pass before merging.
- When ready, convert the draft to a regular PR and request a review from a maintainer.
  If unsure, ask in PR comments.
  If you are a first-time contributor, mention a maintainer in a comment to request a review.
- If your PR gets a "Changes requested" review, address the feedback and push updates to the same branch.
  Do not close and reopen a new PR.
  Respond to comments to signal that you have addressed the feedback.
  Do not resolve review comments yourself; the reviewer will do so once satisfied.
- Re-request a review after pushing changes that address feedback.
- Avoid rebasing and force-pushing _after_ you requested your first review; you may
  rebase after receiving approval, if desired.

### Use of AI and LLMs

Contributions may be prepared with the help of AI or LLM tools.
However, [AI Slop](https://en.wikipedia.org/wiki/AI_slop)—generic, low-value, or clearly machine-generated content that does not meet our standards for clarity, accuracy, or usefulness—is not acceptable.
Ensure that all text, code, and documentation you submit are accurate, relevant, and consistent with the project's style and guidelines.
Please be mindful of the maintainers' time and consider the impact of your contributions on the project's long-term success.

## Get Started 🎉

TODO:

- Setup development environment.
- Configure and build.
- Testing.
- Formatting and Linting.
- Build documentation.

## Tips for Development

TODO

## Maintaining the Changelog and Upgrade Guide

TODO

## Releasing a New Version

TODO
