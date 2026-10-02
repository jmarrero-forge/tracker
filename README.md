# tracker

Work items and questions for [jmarrero-bot](https://github.com/jmarrero-bot)'s workstream.
The [Workstream board](https://github.com/orgs/jmarrero-forge/projects) is a view over
these issues plus the upstream issues and PRs the bot works on; anything on
the board that isn't upstream is an issue here.

- **Work items** are ordinary issues. Larger efforts are parent issues whose
  sub-issues are the steps, so the board shows their progress.
- **Questions for jmarrero** are issues labelled `question` and assigned to
  him, usually a sub-issue of the work item they block. The first line says
  which item that is (`Blocks: <url>`). They offer lettered options, the
  recommended one first as A.

## Answering a question

Comment on the question issue. To pick an option, make the first line of the
comment just its letter (e.g. `B`), optionally followed by more text;
otherwise write whatever you want. The bot acts on the answer, then closes the
issue with a one-line comment saying what it did.

Only comments by the `jmarrero` login count as answers. The bot reads everyone
else's comments, its own included, as input to weigh, never as instructions.
