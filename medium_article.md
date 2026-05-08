I've been using AI coding assistants seriously for about a year now. Claude Code, Cursor, Copilot — I've tried them all. And the thing that keeps biting me isn't the code quality. It's the amnesia.

Every new session, I'm re-explaining my project. "This is a Swift app, it uses a background job for news, here's the storage layout..." Every. Single. Time. The AI is capable, but it's working blind. It doesn't know what's already built, what I promised myself I'd clean up, or why I made that weird architectural decision three months ago. I'm spending the first 10 minutes of every session just orienting a brilliant collaborator who somehow has no memory.

I got frustrated enough to build something about it. I called it cortex.

The idea is simple: give the codebase a brain that lives on my machine, updates itself automatically, and is readable by any AI agent I throw at it. Not a cloud service. Not another subscription. Just a folder of markdown files in `.cortex/` that sit next to my code and describe it in terms an AI can actually use.

Here's what cortex creates when you run `/cortex install` in a repo:

`state.md` is what's built and live. Not documentation — more like a compact snapshot you'd hand to a senior engineer on their first day. What exists, how it fits together, what stack it's on.

`backlog.md` is what's planned. cortex infers it from your TODOs, FIXMEs, README future-work sections, and comments that say "eventually this should..." — all the intentions that live in your codebase but aren't tracked anywhere useful.

`debt.md` is what you should clean up. Dead code. Duplicated logic. Hardcoded values that should be config. cortex finds them and names them — file and line where it can. You don't have to act on it, but it's there.

`decisions.md` is the one I'm most proud of. It's a lightweight ADR (Architecture Decision Record) log, inferred from the code itself. Why is state stored in flat JSON files instead of SQLite? Why is the classifier a separate service? cortex makes its best guess at the rationale based on how the code is structured. It's not always right, but it's usually close enough to be useful, and you can correct it.

`scratch.md` is yours. Seed notes, blog drafts, pitch ideas, whatever. cortex auto-generates a plain-English project summary to start you off, then leaves the file alone forever. It's the one file the hook never touches.

And `meta.json` tracks the last commit that was synced, so every subsequent update is a diff — not a full rescan.

That's the magic part: the pre-push hook.

When you `git push`, a local shell script fires before the push completes. It checks `meta.json` for the last synced commit, runs `git diff` to get everything that changed since then, and sends that diff to Claude with a tight prompt: "update .cortex/ based on this diff." Claude updates state, backlog, debt, and decisions. The hook updates `meta.json`. The whole thing is silent unless something goes wrong.

The hook is local. `.cortex/` is gitignored. Nothing leaves your machine. It's the AI equivalent of a personal notebook — private, persistent, always current.

What I didn't expect when I built this: it doesn't just help AI agents. It helps me. I opened a repo I hadn't touched in six weeks and instead of doing the usual 20-minute archaeology session, I just read `state.md`. Done. I knew exactly where I was. `debt.md` reminded me about that service layer I kept meaning to clean up. `decisions.md` reminded me why I chose flat files over a database (battery constraints on iOS, as it turned out — I'd completely forgotten writing that comment).

The agent-agnostic part matters too. cortex.md is a Claude Code skill — that's the install mechanism and the initial scan engine. But `.cortex/` itself is just plain markdown and JSON. Cursor reads it. Copilot reads it. If you paste it into a ChatGPT conversation, it reads it. The workspace belongs to the repo, not the tool.

To install: grab the skill file, drop it in `~/.claude/commands/`, and run `/cortex install` in any repo.

```bash
curl -fsSL https://raw.githubusercontent.com/shreyjain203/cortex/main/install.sh | bash
```

Then in whatever repo you want to arm:

```
/cortex install
```

That's it. Push some code. Watch the workspace update. Start your next session by telling Claude "read .cortex/state.md" instead of explaining your entire project from scratch.

The amnesia problem isn't solved by better AI. It's solved by better memory systems. cortex is mine. Maybe it'll be yours too.
