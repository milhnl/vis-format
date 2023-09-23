local stdio_formatter = function(cmd, options)
  local apply = function(win, range, pos)
    local command = type(cmd) == 'function' and cmd(win, range, pos) or cmd
    local size = win.file.size
    local all = { start = 0, finish = size }
    local status, out, err = vis:pipe(win.file, all, command)
    if status == 0 then
      if range then
        local start, finish = range.start, range.finish
        win.file:delete(range)
        win.file:insert(start, out:sub(start + 1, finish + (out:len() - size)))
      else
        win.file:delete(all)
        win.file:insert(0, out)
      end
    else
      vis:message(err)
    end
  end
  return {
    apply = apply,
    options = options or { ranged = type(cmd) == 'function' },
  }
end

local with_filename = function(win, option)
  if win.file.path then
    return option .. "'" .. win.file.path:gsub("'", "\\'") .. "'"
  else
    return ''
  end
end

local formatters = nil
formatters = {
  bash = stdio_formatter(function(win)
    return 'shfmt ' .. with_filename(win, '--filename ') .. ' -'
  end),
  csharp = stdio_formatter('dotnet csharpier'),
  go = stdio_formatter('gofmt'),
  lua = {
    pick = function(win)
      local status, out, err = vis:pipe(
        win.file,
        { start = 0, finish = win.file.size },
        'test -e .lua-format && echo luaformatter || echo stylua'
      )
      return formatters[out:gsub('\n$', '')]
    end,
  },
  luaformatter = stdio_formatter('lua-format'),
  markdown = stdio_formatter(function(win)
    if win.options and win.options.colorcolumn ~= 0 then
      return 'prettier --parser markdown --prose-wrap always --print-width '
        .. (win.options.colorcolumn - 1)
    else
      return 'prettier --parser markdown'
    end
  end, { ranged = false }),
  rust = stdio_formatter('rustfmt'),
  stylua = stdio_formatter(function(win, range)
    if range and (range.start ~= 0 or range.finish ~= win.file.size) then
      return 'stylua -s --range-start '
        .. range.start
        .. ' --range-end '
        .. range.finish
        .. with_filename(win, '--stdin-filepath ')
        .. ' -'
    else
      return 'stylua -s ' .. with_filename(win, '--stdin-filepath ') .. ' -'
    end
  end),
  text = stdio_formatter(function(win)
    if win.options and win.options.colorcolumn ~= 0 then
      return 'fmt -w ' .. (win.options.colorcolumn - 1)
    else
      return 'fmt'
    end
  end, { ranged = false }),
}

local getwinforfile = function(file)
  for win in vis:windows() do
    if win and win.file and win.file.path == file.path then
      return win
    end
  end
end

local apply = function(file, range, pos)
  local win = getwinforfile(file)
  pos = pos or win.selection.pos
  if range and range.start == 0 and range.finish == win.file.size then
    range = nil
  end
  local formatter = formatters[win.syntax]
  if formatter and formatter.pick then
    formatter = formatter.pick(win)
  end
  if formatter == nil then
    vis:info('No formatter for ' .. win.syntax)
    return pos
  end
  if range ~= nil and not formatter.options.ranged then
    vis:info('Formatter for ' .. win.syntax .. ' does not support ranges')
    return pos
  end
  pos = formatter.apply(win, range) or pos
  vis:insert('') -- redraw and friends don't work
  return pos
end

return {
  formatters = formatters,
  apply = apply,
  stdio_formatter = stdio_formatter,
  with_filename = with_filename,
}
