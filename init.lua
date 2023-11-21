local global_options = {
  check_same = true,
}

local stdio_formatter = function(cmd, options)
  local apply = function(win, range, pos)
    local command = type(cmd) == 'function' and cmd(win, range, pos) or cmd
    local size = win.file.size
    local check_same = (options and options.check_same ~= nil)
        and options.check_same
      or global_options.check_same
    local check = check_same == true
      or (type(check_same) == 'number' and check_same >= size)
    local all = { start = 0, finish = size }
    local status, out, err = vis:pipe(win.file, all, command)
    if status == 0 and (not check or win.file:content(all) ~= out) then
      if range then
        local start, finish = range.start, range.finish
        win.file:delete(range)
        win.file:insert(start, out:sub(start + 1, finish + (out:len() - size)))
      else
        win.file:delete(all)
        win.file:insert(0, out)
      end
    elseif status ~= 0 then
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

local formatters = {}
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
      return 'prettier --parser markdown --prose-wrap always '
        .. ('--print-width ' .. (win.options.colorcolumn - 1) .. ' ')
        .. with_filename(win, '--stdin-filepath ')
    else
      return 'prettier --parser markdown '
        .. with_filename(win, '--stdin-filepath ')
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

local apply = function(file_or_keys, range, pos)
  local win = type(file_or_keys) ~= 'string' and getwinforfile(file_or_keys)
    or vis.win
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
    return type(file_or_keys) ~= 'string' and pos or 0
  end
  if range ~= nil and not formatter.options.ranged then
    vis:info('Formatter for ' .. win.syntax .. ' does not support ranges')
    return type(file_or_keys) ~= 'string' and pos or 0
  end
  pos = formatter.apply(win, range) or pos
  vis:insert('') -- redraw and friends don't work
  return type(file_or_keys) ~= 'string' and pos or 0
end

return {
  formatters = formatters,
  options = globalOptions,
  apply = apply,
  stdio_formatter = stdio_formatter,
  with_filename = with_filename,
}
