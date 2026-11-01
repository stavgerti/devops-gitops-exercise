# AI prompts

Prompts given to the AI agent (Claude Code) during the exercise, in order.
Originals were in Hebrew; translated to English here.

## 1 – Plan

> This is a DevOps assignment I got from EX.CO. I have two hours to submit.
> Read the attached requirements document fully. I work on Windows with Docker Desktop.
> The goal is a simple, correct solution that is easy to explain.
> Prepare a short work plan in order of the requirements, prioritising Part 0, 1 and 2;
> Part 3 and bonuses only if time remains.
> Open a new repo for the assignment and start a README with the plan and technical choices.
> Record the prompts in ai-prompts.md and commit as you progress.
> Test every step before moving on. Briefly explain technical decisions and changes so I can
> present them in the code review.
> Don't do destructive actions or change external permissions without my approval.
> Show a short execution plan first, then we start.

## 2 – Approve plan with changes, start Part 0

> I approve the plan with these changes:
> - Use Python Flask for the app and Traefik as the ingress controller.
> - Start by checking Docker Desktop and starting it if needed.
> - Check whether an earlier kind cluster still exists or uses resources. Don't delete it without approval.
> - Create a new public repo, after a secrets check and setting a GitHub noreply email for new commits.
> - In Part 2 use a local Docker image via `kind load`, to avoid registry and permission delays.
> - Document prompts and decisions and commit as you go.
>
> Move fast in order of the requirements. Don't stop for approval on every routine file or action.
> Stop only before destructive actions, exposing sensitive data, or significant permission changes.
> Start Part 0 now, test, and show me a short summary when done.
