# media.nvim — documentation

What is where, and which question each page answers.

| Page | Answers |
| --- | --- |
| [installation.md](installation.md) | What has to be installed, and which load trigger to use. |
| [configuration.md](configuration.md) | Every `setup()` key, its default, and why that default. |
| [commands.md](commands.md) | Every `:Media` route and its arguments. |
| [BINDINGS.md](BINDINGS.md) | Keymaps, commands and autocommands at a glance. |
| [health.md](health.md) | Every line `:checkhealth media` can print, and what to do about it. |
| [ROADMAP.md](ROADMAP.md) | What is deliberately not here yet, and what it would cost. |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Layout, tests, ground rules. |

The reasoning behind each module lives in the module's own header comment —
`lua/media/core/frame.lua` explains why `-ss` goes before `-i`, and that is the
right place for it, not a documentation page that drifts from the code.

The public API another plugin consumes is documented in
[the README](../README.md#for-plugin-authors) and annotated in
`lua/media/init.lua`.
