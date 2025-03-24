local format = {
  options = {
    check_same = true,
  },
}

local with_filename = function(win, option)
  if win.file.path then
    return option .. "'" .. win.file.path:gsub("'", "\\'") .. "'"
  else
    return ''
  end
end

local new_pos_heuristic = function(win, new, pos)
  local new_size = #new
  do -- Try creating a pattern that'll match one position in the new content
    local converters = {
      function(fragment)
        return fragment
          :gsub('([(%:)%:.%:%%:+%:-%:*%:?%:[%:^%:$])', '%%%1') -- all rgx chars
          :gsub('(%S)%s+', '%1%%s*') -- only leading space literal, rest flex
      end,
      function(fragment)
        return fragment
          :gsub('^%s+', '') -- ignore leading space
          :gsub('([(%:)%:.%:%%:+%:-%:*%:?%:[%:^%:$])', '%%%1') -- all rgx chars
          :gsub('%s+', '%%s*') -- flexibly match all space
      end,
      function(fragment)
        return fragment
          :gsub('%W+', '%%W+') -- only match on alphanumerics
          :gsub('^%%W%+', '') -- ignore non-alphanumerics at start
      end,
    }
    local converter_index = 1
    local fragment_size = 4
    while
      fragment_size <= 1024
      and fragment_size <= (win.file.size - pos) * 2
      and converter_index <= #converters
    do
      local pattern =
        converters[converter_index](win.file:content(pos, fragment_size))
      local new_pos = new:find(pattern)
      if new_pos == nil then
        converter_index = converter_index + 1
      elseif -- pattern has 1 match, and it isn't too far away (false positive)
        math.abs(new_pos - pos)
          < (math.abs(new_size - win.file.size) * 10 + 30)
        and new:find(pattern, new_pos + 1) == nil
      then
        return new_pos - 1
      else
        fragment_size = fragment_size * 2
      end
    end
  end

  do -- Try same offset of right side of the same line if # of lines matches
    local new_pos, new_lines, new_line_start = nil, 1, nil
    for i = 1, new_size do
      if new:sub(i, i) == '\n' then
        if new_lines == win.selection.line and new_line_start ~= nil then
          local line_length = #win.file.lines[win.selection.line]
          new_pos = i - line_length + win.selection.col - 2
          new_pos = new_line_start < new_pos and new_pos or new_line_start
        end
        new_lines = new_lines + 1
        if new_lines == win.selection.line then
          new_line_start = i
        end
      end
    end
    if (new_lines - 1) == #win.file.lines then
      return new_pos
    end
  end

  return nil
end

local win_formatter = function(func, options)
  return {
    apply = function(win, range, pos)
      if
        range ~= nil
        and not options.ranged
        and range.start ~= 0
        and range.finish ~= win.file.size
      then
        return nil,
          'Formatter for ' .. win.syntax .. ' does not support ranges',
          pos
      end
      local _, err, new_pos = func(win, range, pos)
      vis:insert('') -- redraw and friends don't work
      return nil, err, new_pos or pos
    end,
    options = options,
  }
end

local func_formatter = function(func, options)
  return win_formatter(function(win, range, pos)
    local size = win.file.size
    local all = { start = 0, finish = size }
    if range == nil then
      range = all
    end
    local check_same = (options and options.check_same ~= nil)
        and options.check_same
      or format.options.check_same
    local check = check_same == true
      or (type(check_same) == 'number' and check_same >= size)

    local out, err, new_pos = func(win, range, pos)
    if err ~= nil then
      return nil, err, pos
    elseif out == nil or out == '' then
      return nil, 'No output from formatter', pos
    elseif not check or win.file:content(all) ~= out then
      new_pos = new_pos or new_pos_heuristic(win, out, pos) or pos
      local start, finish = range.start, range.finish
      win.file:delete(range)
      win.file:insert(start, out:sub(start + 1, finish + (out:len() - size)))
    end
    return nil, nil, new_pos
  end, options)
end

local stdio_formatter = function(cmd, options)
  return func_formatter(function(win, range, pos)
    local command = type(cmd) == 'function' and cmd(win, range, pos) or cmd
    local status, out, err = vis:pipe(win.file, range, command)
    if status ~= 0 then
      return nil, err, nil
    end
    return out, nil, nil
  end, options or { ranged = type(cmd) == 'function' })
end

local prettier_formatter = function(cmd, options)
  return func_formatter(function(win, range, pos)
    local command = type(cmd) == 'function' and cmd(win, range, pos) or cmd
    command = command
      .. with_filename(win, ' --stdin-filepath ')
      .. (' --cursor-offset ' .. pos)
    local status, out, err = vis:pipe(win.file, range, command)
    if status ~= 0 then
      return nil, err, nil
    end
    local new_pos = tonumber(err)
    return out, nil, new_pos >= 0 and new_pos or nil
  end, options or { ranged = type(cmd) == 'function' })
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
      local fz = io.popen([[
        test -e .lua-format && echo luaformatter || echo stylua
      ]])
      if fz then
        local out = fz:read('*a')
        local _, _, status = fz:close()
        if status == 0 then
          return formatters[out:gsub('\n$', '')]
        end
      end
    end,
  },
  luaformatter = stdio_formatter('lua-format'),
  markdown = prettier_formatter(function(win)
    if win.options and win.options.colorcolumn ~= 0 then
      return 'prettier --parser markdown --prose-wrap always '
        .. ('--print-width ' .. (win.options.colorcolumn - 1))
    else
      return 'prettier --parser markdown'
    end
  end, { ranged = false }),
  powershell = stdio_formatter(function(win)
    local indent_style = win.options.expandtab and 'space' or 'tab'
    return [[
      (set -o pipefail 2>/dev/null) && set -o pipefail
      sed 's/\r$//' \
        | "$( (command -v powershell.exe || command -v pwsh) 2>/dev/null)" -c '
          Invoke-Formatter -Settings @{
            Rules = @{
              PSAvoidTrailingWhitespace = @{ Enable = $true };
              PSUseConsistentWhitespace = @{ Enable = $true };
              PSUseConsistentIndentation = @{
                Enable = $true;
                IndentationSize = ]] .. win.options.tabwidth .. [[;
                Kind = "]] .. indent_style .. [[";
              };
            };
          } -ScriptDefinition `
          ([IO.StreamReader]::new([Console]::OpenStandardInput()).ReadToEnd())
        ' \
        | sed -e :a -e '/^\(\r\{0,1\}\n\)*$/{$d;N;};/\n$/ba'
    ]]
  end, { ranged = false }),
  rust = stdio_formatter([[
    edition="$(
      cargo metadata --format-version=1 --no-deps 2>/dev/null \
        | sed -E 's/.*"edition":"([^"]*)".*/\1/'
    )"
    if [ -n "$edition" ]; then
      rustfmt --edition "$edition"
    else
      rustfmt
    fi
  ]]),
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
      return "fmt | awk -v n=-1 '"
        .. '  {'
        .. '    if ($0 == "") {'
        .. '      n = n <= 0 ? 2 : 1'
        .. '    } else {'
        .. '      if (n == 0) sub(/^ */, "");'
        .. '      n = 0;'
        .. '    }'
        .. '    printf("%s", $0 (n == 0 ? " " : ""));'
        .. '    for(i = 0; i < n; i++)'
        .. '      printf("\\n");'
        .. '  }'
        .. "'"
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

local pick = function(win)
  local formatter = formatters[win.syntax]
  if formatter and formatter.pick then
    formatter = formatter.pick(win)
  end
  return formatter
end

local keyhandler = function(file_or_keys, range, pos)
  local _, err
  local win = type(file_or_keys) ~= 'string' and getwinforfile(file_or_keys)
    or vis.win
  local ret = type(file_or_keys) ~= 'string'
      and function()
        return pos
      end
    or function()
      win.selection.pos = pos
      return 0
    end
  pos = pos ~= nil and pos or win.selection.pos
  local formatter = format.pick(win)
  if formatter == nil then
    vis:info('No formatter for ' .. win.syntax)
    return ret()
  end
  _, err, pos = formatter.apply(win, range, pos)
  if err ~= nil then
    if err:match('\n') then
      vis:message(err)
    else
      vis:info(err)
    end
  end
  vis:insert('') -- redraw and friends don't work
  return ret()
end

vis.events.subscribe(vis.events.FILE_SAVE_PRE, function(file)
  local win = type(file) ~= 'string' and getwinforfile(file) or vis.win
  local formatter = format.pick(win)
  if formatter == nil then
    return
  end
  local on_save = (formatter.options and formatter.options.on_save ~= nil)
      and formatter.options.on_save
    or format.options.on_save
  if type(on_save) == 'function' and not on_save(win) then
    return
  elseif not on_save then
    return
  end
  local _, err, pos = formatter.apply(win, nil, win.selection.pos)
  if err ~= nil then
    vis:info('Warning: formatting failed. Run manually for details')
  else
    win.selection.pos = pos
    vis:insert('') -- redraw and friends don't work
  end
end)

format.formatters = formatters
format.pick = pick
format.apply = keyhandler
format.stdio_formatter = stdio_formatter
format.with_filename = with_filename

return format
