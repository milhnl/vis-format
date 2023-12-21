local global_options = {
  check_same = true,
}

local func_formatter = function(func, options)
  local apply = function(win, range, pos)
    local size = win.file.size
    local all = { start = 0, finish = size }
    if range == nil then
      range = all
    end
    local check_same = (options and options.check_same ~= nil)
        and options.check_same
      or global_options.check_same
    local check = check_same == true
      or (type(check_same) == 'number' and check_same >= size)
    out, err = func(win, range, pos)
    if err ~= nil then
      if err:match('\n') then
        vis:message(err)
      else
        vis:info(err)
      end
      return
    elseif out == nil or out == '' then
      vis:info('No output from formatter')
    elseif not check or win.file:content(all) ~= out then
      local start, finish = range.start, range.finish
      win.file:delete(range)
      win.file:insert(start, out:sub(start + 1, finish + (out:len() - size)))
    end
    return pos
  end
  return {
    apply = apply,
    options = options,
  }
end

local stdio_formatter = function(cmd, options)
  return func_formatter(function(win, range, pos)
    local command = type(cmd) == 'function' and cmd(win, range, pos) or cmd
    local status, out, err = vis:pipe(win.file, range, command)
    if status ~= 0 then
      return nil, err
    end
    return out, nil
  end, options or { ranged = type(cmd) == 'function' })
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
  diff = {
    pick = function(win)
      for _, pattern in ipairs(vis.ftdetect.filetypes['git-commit'].ext) do
        if ((win.file.name or ''):match('[^/]+$') or ''):match(pattern) then
          return formatters['git-commit']
        end
      end
    end,
  },
  ['git-commit'] = func_formatter(function(win, range, pos)
    local width = (win.options and win.options.colorcolumn ~= 0)
        and (win.options.colorcolumn - 1)
      or 72
    local parts = {}
    local fmt = nil
    local summary = true
    for line in win.file:lines_iterator() do
      local txt = not line:match('^#')
      if fmt == nil or fmt ~= txt then
        fmt = txt and not summary
        local prev = parts[#parts] and parts[#parts].finish or 0
        parts[#parts + 1] = {
          fmt = fmt,
          start = prev,
          finish = prev + #line + 1,
        }
        summary = summary and not txt
      else
        parts[#parts].finish = parts[#parts].finish + #line + 1
      end
    end
    local out = ''
    for _, part in ipairs(parts) do
      if part.fmt then
        local status, partout, err =
          vis:pipe(win.file, part, 'fmt -w ' .. width)
        if status ~= 0 then
          return nil, err
        end
        out = out .. (partout or '')
      else
        out = out .. win.file:content(part)
      end
    end
    return out
  end, { ranged = false }),
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
  powershell = stdio_formatter([[
    "$( (command -v powershell.exe || command -v pwsh) 2>/dev/null )" -c '
        Invoke-Formatter  -ScriptDefinition `
          ([IO.StreamReader]::new([Console]::OpenStandardInput()).ReadToEnd())
      ' | sed -e :a -e '/^[\r\n]*$/{$d;N;};/\n$/ba'
  ]]),
  rust = stdio_formatter('rustfmt'),
  stylua = stdio_formatter(function(win, range)
    if range and (range.start ~= 0 or range.finish ~= win.file.size) then
      return 'stylua -s --range-start '
        .. range.start
        .. ' --range-end '
        .. range.finish
        .. with_filename(win, ' --stdin-filepath ')
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
  local ret = type(file_or_keys) ~= 'string'
      and function()
        return pos
      end
    or function()
      return 0
    end
  pos = pos or win.selection.pos
  local formatter = formatters[win.syntax]
  if formatter and formatter.pick then
    formatter = formatter.pick(win)
  end
  if formatter == nil then
    vis:info('No formatter for ' .. win.syntax)
    return ret()
  end
  if
    range ~= nil
    and not formatter.options.ranged
    and range.start ~= 0
    and range.finish ~= win.file.size
  then
    vis:info('Formatter for ' .. win.syntax .. ' does not support ranges')
    return ret()
  end
  pos = formatter.apply(win, range, pos) or pos
  vis:insert('') -- redraw and friends don't work
  return ret()
end

return {
  formatters = formatters,
  options = globalOptions,
  apply = apply,
  stdio_formatter = stdio_formatter,
  with_filename = with_filename,
}
