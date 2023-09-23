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
- `go`: `gofmt`
- `lua`: [StyLua](https://github.com/JohnnyMorganz/StyLua) and
  [LuaFormatter](https://github.com/Koihik/LuaFormatter), depending on which
  config file is in the working directory.
- `markdown`: `prettier` with `--prose-wrap` enabled if `colorcolumn` is set.
- `rust`: `rustfmt`
- `text`: `fmt` like the `vis` default, but with width set if available

I'm working on some more heuristics for detecting which formatter to use for
languages without a 'blessed' formatter. In the meantime, this is how you add
the ones you want to use:

    format.formatters.html = format.stdio_formatter("prettier --parser html")

### Advanced usage

The following methods and tables are fields of the table that is returned by
`require('vis-format')` (e.g. `format`). You can use them to extend or
configure `vis-format`.

#### `stdio_formatter`

The `stdio_formatter` function wraps the command to produce something like
this:

    {
        apply = function(win, range, pos) end,
        options = { ranged = false, check_same = nil }
    }

The command given can also be a function, which is expected to return a string,
which is then used as a command. This allows you to use the given range, or
options from `win`. `ranged` is automatically set to true in this case.

Apart from mapping `=` in normal mode, you can also define an operator to
format blocks of code/text. This will require a formatter that can work with
ranges of text. Configuring that looks like this:

    format.formatters.lua = format.stdio_formatter(function(win, range, pos)
      return 'stylua -s --range-start ' .. range.start .. ' --range-end '
        .. range.finish .. ' -'
    end)

#### `with_filename`

Most formatters take a path for where `stdin` would be. If the file has a path
`with_filename` concatenates the option and the shell-escaped path. Note that
it does not add any spaces to separate options/arguments.

    stdio_formatter(function(win)
      return 'shfmt ' .. with_filename(win, '--filename ') .. ' -'
    end, { ranged = false })

#### `options`

- `options.check_same` (`boolean|number`) — After formatting, to avoid updating
  the file, `vis-format` can compare the old and the new. If this is set to a
  number, that's the maximum size of the file for which it is enabled. This
  option is also available in the per-formatter options.

### Bugs

Ranged formatting is not enabled and will currently not work with `prettier`.
Prettier extends the range given on the command line to the beginning and end
of the statement containing it. This will not work with how `vis-format`
currently applies the output. I have some ideas on how to fix this, but wanted
to release what works first.

#### Note on vis versions before 0.9

The included formatter integrations assume that the `options` table in `vis`
and `win` is present. If you use an older version, `vis-format` will still
work, but can't detect your editor settings. To fix that, look at the
[vis-options-backport](https://github.com/milhnl/vis-options-backport) plugin.
This will 'polyfill' that for older versions.
