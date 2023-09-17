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

- `rust`: `rustfmt`
- `go`: `gofmt`
- `markdown`: `prettier` with `--prose-wrap` enabled if `colorcolumn` is set.

I'm working on some heuristics for detecting which formatter to use for
languages without a 'blessed' formatter. In the meantime, this is how you add
the ones you want to use:

    format.formatters.html = format.stdio_formatter("prettier --parser html")

### Advanced (and ranged) usage

The `stdio_formatter` function wraps the command to produce something like
this:

    {
        apply = function(win, range, pos) end,
        options = { ranged = false }
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
