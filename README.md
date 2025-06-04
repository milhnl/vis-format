# vis-format - integrates vis with external formatters

A plugin for [vis](https://github.com/martanne/vis) to integrate `prettier`,
`rustfmt` etc.

### Installation

Clone this repository to where you install your plugins. (If this is your first
plugin, running `git clone https://github.com/milhnl/vis-format` in
`~/.config/vis/` will probably work).

Then, add something like the following to your `visrc`.

    local format = require('vis-format')
    vis:map(vis.modes.NORMAL, '=', format.apply)

### Usage

Press `=` to format the whole file.

Currently, the following formatters are supported out-of-the-box.

- `bash`: [shfmt](https://github.com/mvdan/sh)
- `csharp`: [CSharpier](https://csharpier.com/). Although
  [dotnet-format](https://github.com/dotnet/format) is the 'default' formatter
  for dotnet, it does not support formatting stdin (and does not break lines).
- `git-commit`: Actually `diff` with an extra check, as that's how
  `vis.ftdetect` ends up labeling it. Uses `fmt -w` and some glue code to
  reformat the commit body, but not the summary and comments.
- `go`: `gofmt`
- `lua`: [StyLua](https://github.com/JohnnyMorganz/StyLua) and
  [LuaFormatter](https://github.com/Koihik/LuaFormatter), depending on which
  config file is in the working directory.
- `markdown`: `prettier` with `--prose-wrap` enabled if `colorcolumn` is set.
- `powershell`:
  [PSScriptAnalyzer](https://learn.microsoft.com/en-gb/powershell/utility-modules/psscriptanalyzer/overview?view=ps-modules#installing-psscriptanalyzer).
  via `powershell.exe` in the WSL if available or `pwsh`. It does not support a
  configuration file, so `win.options` is used.
- `python`: [autopep8](https://pypi.org/project/autopep8/),
  [black](https://pypi.org/project/black/),
  [ruff](https://docs.astral.sh/ruff/) or
  [yapf](https://github.com/google/yapf) depending on the first `tool.*`
  matching one of these tools found in `pyproject.toml`.
- `rust`: `rustfmt`
- `text`: `fmt` with width based on colorcolumn if set, otherwise joined
  paragraphs.

I'm working on some more heuristics for detecting which formatter to use for
languages without a 'blessed' formatter. In the meantime, this is how you add
the ones you want to use:

    format.formatters.html = format.stdio_formatter("prettier --parser html")

### Advanced usage

The following methods and tables are fields of the table that is returned by
`require('vis-format')` (e.g. `format`). You can use them to extend or
configure `vis-format`.

#### `formatters`

A table containing the configured formatters. There are some predefined (see
the list above under "Usage"), and you can add or override those by assigning
your formatter to a key corresponding to the vis `syntax` it is relevant for.
Each entry is of either of these forms:

    {
      apply = func(win, range, pos) end,
      options = {
        ranged = nil,
        check_same = nil,
      }
    }

or

    {
      pick = func(win, range, pos) end,
    }

The first form directly defines a formatter. An entry containing `pick` is
executed and its result is directly used as a formatter. A recommended way to
use `pick` is to return a different formatter from the `formatters` table. Note
that using the vis `syntax` as keys in this table is only necessary for
formatters that are run directly. This means that `lua` is a good key for a
`pick` entry, which chooses between the formatters found at `stylua` and
`luaformatter`.

#### `stdio_formatter(command[, options])`

The `stdio_formatter` function wraps the command to produce something like
this:

    {
      apply = function(win, range, pos) end,
      options = { ranged = false }
    }

The command given can also be a function, which is expected to return a string,
which is then used as a command. This allows you to use the given range, or
options from `win`. `ranged` is automatically set to true in this case.

Apart from mapping `vis-format` in normal mode, you can also define an operator
(with `vis:operator_new`) to format ranges of code/text. This will require a
formatter that can work with ranges of text. Configuring that looks like this:

    -- Add a formatter that can use a range
    format.formatters.lua = format.stdio_formatter(function(win, range, pos)
      return 'stylua -s --range-start ' .. range.start .. ' --range-end '
        .. range.finish .. ' -'
    end)

    -- Bind it to keys
    vis:operator_new('=', format.apply) -- this'll handle ranges
    vis:map(vis.modes.NORMAL, '=', function() -- this'll format whole files
      format.apply(vis.win.file, nil, vis.win.selection.pos)
    end)

#### `with_filename`

Most formatters take a path for where `stdin` would be. If the file has a path
`with_filename` concatenates the option and the shell-escaped path. Note that
it does not add any spaces to separate options/arguments.

    stdio_formatter(function(win)
      return 'shfmt ' .. with_filename(win, '--filename ') .. ' -'
    end, { ranged = false })

#### `options`

The options listed here are also available in the options field of a formatter.

- `options.check_same` (`boolean|number`) — After formatting, to avoid updating
  the file, `vis-format` can compare the old and the new. If this is set to a
  number, that's the maximum size of the file for which it is enabled.
- `options.on_save` (`boolean|function(win)`) — Enable a pre-save hook that
  formats the file. If `on_save` is a function, it is run before saving to
  determine whether formatting is required.

### Bugs

#### Possible cursor jumps

You might see the cursor jump around when formatting. This should be very rare,
as I have not seen it happen yet. Most formatters do not report the new cursor
position, so there is a set of heuristics to avoid this. These heuristics might
not always work perfectly, but I'd like to try to make them better.

If you notice any jumps, please open an issue with the file and original cursor
position.

There is one situation that I do not consider a bug, and that's the cursor
moving to the first non-whitespace character if the whitespace it is on
changes.

#### Ranged formatting

Ranged formatting is not enabled and will currently not work with `prettier`.
Prettier extends the range given on the command line to the beginning and end
of the statement containing it. This will not work with how `vis-format`
currently applies the output. I have some ideas on how to fix this, but wanted
to release what works first.

#### Note on editor options and vis versions before 0.9

`vis` has an `options` table with editor settings like tab width etc. built-in
since 0.9. `vis-format` will not read this most of the time, because the
correct way to configure formatters is with their dedicated configuration
files, or `.editorconfig` (Which can be read in vis with
[vis-editorconfig](https://github.com/seifferth/vis-editorconfig) and
[vis-editorconfig-options](https://github.com/milhnl/vis-editorconfig-options)
).

The included formatter integrations that _do_ use this information assume that
the `options` table in `vis` and `win` is present. If you use an older version,
`vis-format` will still work, but can't detect your editor settings. To fix
that, look at the
[vis-options-backport](https://github.com/milhnl/vis-options-backport) plugin.
This will 'polyfill' that for older versions.
