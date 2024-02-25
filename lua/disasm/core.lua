local M = {}

-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
-- " Configuration
-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

if not vim.g.disassemble_focus_on_second_call then
  vim.g.disassemble_focus_on_second_call = false
end

if not vim.g.disassemble_enable_compilation then
  vim.g.disassemble_enable_compilation = true
end

if not vim.g.disassemble_default_compilation_command then
  vim.g.disassemble_default_compilation_command = 'printf( "gcc %s -o %s -g", expand("%"), expand("%:r") )'
end

if not vim.g.disassemble_default_objdump_command then
  vim.g.disassemble_default_objdump_command = '"objdump --demangle --line-numbers --file-headers --file-offsets --source-comment --no-show-raw-insn --disassemble -M intel " . expand("%:r")'
end

if not vim.g.disassemble_default_binary_file then
  vim.g.disassemble_default_binary_file = 'expand("%:r")'
end

if not vim.g.disassemble_configuration_extension then
  vim.g.disassemble_configuration_extension = "disconfig"
end

if not vim.g.disassemble_autosave then
  vim.g.disassemble_autosave = true
end

-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
-- " Configuration functions
-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

---@param lines string[]
---@param search string
local function try_parse_config_line(lines, search)
  local match = vim.fn.matchstrpos(lines, search)
  if match[2] ~= -1 then
    local lineno = match[2] + 1
    local offset = match[4] + 1
    return string.sub(lines[lineno], offset)
  end
end

---@param lines string[]
local function try_parse_config(lines)
  return {
    compilation = try_parse_config_line(lines, 'compile: '),
    objdump     = try_parse_config_line(lines, 'objdump: '),
    binary_file = try_parse_config_line(lines, 'binary_file: ')
  }
end

local function load_config(bufnr)
  -- Create the variables to store the temp files
  vim.b[bufnr].tmp_file_asm = vim.b[bufnr].tmp_file_asm or vim.fn.tempname()
  vim.b[bufnr].tmp_file_err = vim.b[bufnr].tmp_file_err or vim.fn.tempname()

  local file = vim.fn.expand '%'
  local root = vim.fn.expand '%:r'

  -- Get the default commands from the global namespace
  local default_objdump_command = "objdump --demangle --line-numbers --file-headers --file-offsets --source-comment --no-show-raw-insn --disassemble -M intel " .. root

  -- Set the default values for the compilation and objdump commands
  local config = vim.b[bufnr].disassemble_config or {
    compilation = vim.fn.printf( "gcc %s -o %s -g", file, root),
    objdump = default_objdump_command,
    binary_file = root,
    objdump_with_redirect = default_objdump_command
  }

  -- Try to parse the configuration file
  local config_file = vim.fn.printf("%s.%s", file, vim.g.disassemble_configuration_extension)
  if vim.fn.filereadable(config_file) ~= 0 then
    local loaded = try_parse_config(vim.fn.readfile(config_file))
    config.compilation = loaded.compilation or config.compilation
    config.objdump     = loaded.objdump or config.objdump
    config.binary_file = loaded.binary_file or config.binary_file
  end

  -- Try to parse the start of the current file for configuration
  do
    local loaded = try_parse_config(vim.fn.getline(1,10))
    config.compilation = loaded.compilation or config.compilation
    config.objdump     = loaded.objdump or config.objdump
    config.binary_file = loaded.binary_file or config.binary_file
  end

  -- Ask the user for the compilation and objdump extraction commands
  if vim.b[bufnr].enable_compilation then
    config.compilation = vim.fn.input({ prompt = "compilation command> ", default = config.compilation })
  end

  config.objdump               = vim.fn.input({ prompt = "objdump command> ", default = config.objdump })
  config.objdump_with_redirect = config.objdump .. " 1>" .. vim.b[bufnr].tmp_file_asm .. " 2>" .. vim.b[bufnr].tmp_file_err

  return config
end

function M.reconfigure()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b[bufnr].disassemble_config = load_config(bufnr)

  vim.cmd [[redraw]]
  vim.notify('Disassemble.nvim configured for this buffer!', vim.log.levels.INFO)
end

---@param bufnr number
local function prepare(bufnr)
  local buffer = vim.b[bufnr]

  -- Create the variable to store the window id
  buffer.disasm_popup_ref = buffer.disasm_popup_ref or false

  -- Check if the plugin should compile automatically
  buffer.enable_compilation = buffer.enable_compilation or vim.g.disassemble_enable_compilation

  -- Check if the plugin is already configured
  if not buffer.disassemble_config then
    M.reconfigure()
  end
end

function M.save_config()
  local bufnr = vim.api.nvim_get_current_buf()

  prepare(bufnr)

  local config = vim.b[bufnr].disassemble_config
  local file = vim.fn.printf("%s.%s", vim.fn.expand("%"), vim.g.disassemble_configuration_extension)
  local data = {
    "compile: "     .. config.compilation,
    "objdump: "     .. config.objdump,
    "binary_file: " .. config.binary_file,
  }

  vim.fn.writefile(data, file)
  vim.notify("Disassemble configuration saved to '" .. file .. "'", vim.log.levels.INFO)
end

-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
-- " Compilation function
-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

---@param bufnr number
---@return boolean -- is failure?
local function do_compile(bufnr)
  local config = vim.b[bufnr].disassemble_config
  local result = vim.fn.system(config.compilation)

  if vim.v.shell_error == 1 then
    vim.notify(
      'Error while compiling. Check the compilation command.\n> ' .. config.compilation .. '\n' .. result,
      vim.log.levels.ERROR
    )
    return true
  else
    return false
  end
end

-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
-- " Objectdump extraction
-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

local function do_objdump()
  local bufnr = vim.api.nvim_get_current_buf()
  local config = vim.b[bufnr].disassemble_config

  -- Reset the output variables
  vim.b[bufnr].compilation_error = false
  vim.b[bufnr].objdump_asm_output = false

  -- Extract the objdump information to the `tmp_file_err` and `tmp_file_asm` files
  vim.fn.system(config.objdump_with_redirect)
  if vim.v.shell_error == 1 then
    return 1
  end

  -- Get the error from the temporary file
  vim.b[bufnr].compilation_error = vim.fn.readfile(vim.b[bufnr].tmp_file_err)
  vim.b[bufnr].compilation_error = vim.fn.string(vim.b[bufnr].compilation_error)

  -- Return the error code 128 if the C file is more recent that the ELF file
  if vim.fn.match(vim.b[bufnr].compilation_error, "is more recent than object file") ~= -1 then
    return 128
  end

  -- Get the content of the objdump file
  vim.b[bufnr].objdump_asm_output = vim.fn.systemlist("expand -t 4 " .. vim.b[bufnr].tmp_file_asm)
  if vim.v.shell_error == 1 then
    return 1
  end

  -- Return OK
  return 0
end


local function get_objdump()
  local bufnr = vim.api.nvim_get_current_buf()
  local config = vim.b[bufnr].disassemble_config

  -- Check the presence of the ELF file
  if vim.fn.filereadable(config.binary_file) ~= 1 then
    if not vim.b[bufnr].enable_compilation then
      vim.notify("the file '" .. config.binary_file .. "' is not readable", vim.log.levels.WARN)
      return 1
    else
      if do_compile(bufnr) then
        return 1
      end
    end
  end

  -- Check if the binary file has debug informations
  vim.b[bufnr].has_debug_info = vim.fn.system("file " .. config.binary_file)
  if vim.fn.match(vim.b[bufnr].has_debug_info, "with debug_info") == -1 then
    vim.notify("the file '" .. config.binary_file .. "' does not have debug information", vim.log.levels.WARN)
    return 1
  end

  -- Get the objdump content
  local objdump_return_code = do_objdump()

  if objdump_return_code == 1 then
    -- Unknown error in the function
    return 1
  elseif objdump_return_code == 128 then
    -- Check if the C source code is more recent than the object file
    -- Try to recompile and redump the objdump content
    if not vim.b[bufnr].enable_compilation then
      vim.notify("Automatic compilation is disabled for this buffer; we can not have a up-to-date ELF file to work on...", vim.log.levels.WARN)
      return 1
    else
      if do_compile(bufnr) then
        return 1
      end
      return get_objdump()
    end
  else
    return 0
  end
end

-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
-- " Data processing
-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

---@param lines string[]
---@param lineno number
---@return number -- start
---@return number -- end
local function search_asm_line(lines, lineno)
  -- Search the current line
  local pos_current_line_in_asm = { "", -1 }
  local lines_searched = 0

  while pos_current_line_in_asm[2] < 0 do
    pos_current_line_in_asm = vim.fn.matchstrpos(lines, vim.fn.expand('%:t') .. ':' .. lineno .. [[\(\s*(discriminator \d*)\)*$]])

    lineno = lineno + 1

    lines_searched = lines_searched + 1
    if lines_searched >= 20 then
      vim.notify('This line is not included in the asm file', vim.log.levels.WARN)
      return -1, -1
    end
  end

  -- Search the next occurrence of the filename
  local pos_next_line_in_asm = vim.fn.matchstrpos(lines, vim.fn.expand('%:t') .. ':', pos_current_line_in_asm[2] + 1)

  -- If not found, it's probably because this code block is at the end of a section. This will search the start of the next section.
  if pos_next_line_in_asm[2] == -1 then
    pos_next_line_in_asm = vim.fn.matchstrpos(lines, [[\v^\x+\s*]], pos_current_line_in_asm[2] + 1)
  end

  return pos_current_line_in_asm[2], pos_next_line_in_asm[2]
end

-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
-- " Main functions
-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function M.disassemble()
  local bufnr = vim.api.nvim_get_current_buf()

  -- popup already exists, so we just focus it
  if vim.b[bufnr].disasm_popup_ref then
    M.focus_popup()
    return 0
  end

  -- Close the current window if we are already in a popup buffer
  -- and want to get a popup, which makes no sense in this context
  if vim.b[bufnr].disasm_is_popup then
    vim.api.nvim_win_close(0, true)
    return 0
  end

  if vim.g.disassemble_autosave then
    vim.api.nvim_command [[write]]
  end

  -- Load the configuration for this buffer
  prepare(bufnr)

  -- Extract the objdump content to the correct buffer variables
  if get_objdump() == 1 then
    return 1
  end

  local line = vim.fn.line '.'
  local asm = vim.b[bufnr].objdump_asm_output
  local asm_top, asm_bot = search_asm_line(asm, line)
  if asm_top == -1 then
    return 1
  end

  -- Only select the current chunk of asm
  local content = {unpack(asm, asm_top + 1, asm_bot)}

  -- Popup size
  local width  = vim.fn.max(vim.fn.map(content, "strlen(v:val)"))
  local height = asm_bot - asm_top

  -- Create the popup window
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative  = 'cursor',
    width     = width,
    height    = height,
    col       = 0,
    row       = 1,
    anchor    = 'NW',
    style     = 'minimal',
    border    = 'rounded',
    focusable = true,
  })

  vim.api.nvim_buf_set_lines(buf, 0, height, false, content)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'asm')
  vim.api.nvim_buf_set_var(buf, 'disasm_is_popup', true)
  vim.api.nvim_win_set_cursor(win, { 1, 0 })

  vim.b[bufnr].disasm_popup_ref = win

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufLeave' }, {
    group = vim.api.nvim_create_augroup('disassembleOnCursorMoveGroup', { clear = true }),
    pattern = { '*.c', '*.cpp' },
    callback = M.disassemble_Close,
  })
end

local function update_aside()
  local bufnr = vim.api.nvim_get_current_buf()
  local asm = vim.b[bufnr].objdump_asm_output
  local buf = vim.b[bufnr].disasm_aside_buf
  local win = vim.b[bufnr].disasm_aside_win
  if not asm or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then return end

  local line = vim.fn.line '.'
  local s, e = search_asm_line(asm, line)
  if s == -1 then return end

  vim.api.nvim_win_set_cursor(win, { s + 2, 0 })

  local ns = vim.g.disasm_ns
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i = s, e, 1 do
    if asm[i + 1]:match [[^%s+%w+:%s+.+$]] then
      vim.api.nvim_buf_add_highlight(buf, ns, 'DisasmCurrent', i, 0, -1)
    end
  end
end

function M.disassemble_full()
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.g.disassemble_autosave then
    vim.api.nvim_command [[write]]
  end

  --  the configuration for this buffer
  prepare(bufnr)

  -- Extract the objdump content to the correct buffer variables
  if get_objdump() == 1 then
    return 1
  end

  local line = vim.fn.line '.'
  local asm = vim.b[bufnr].objdump_asm_output
  local asm_top = search_asm_line(asm, line)
  if asm_top == -1 then
    return 1
  end

  -- Buffer
  local buf = vim.b[bufnr].disasm_aside_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'asm')
    vim.api.nvim_buf_set_name(buf, '[Disassembled] ' .. vim.b[bufnr].disassemble_config['binary_file'])
  else
    vim.api.nvim_buf_set_option(buf, 'readonly', false)
  end
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, asm)
  vim.api.nvim_buf_set_option(buf, 'readonly', true)
  vim.b[bufnr].disasm_aside_buf = buf

  -- Window
  local win = vim.b[bufnr].disasm_aside_win
  if not win or not vim.api.nvim_win_is_valid(win) then
    local old = vim.api.nvim_get_current_win()
    vim.cmd [[vsplit]]
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(old)
  end
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_cursor(win, { asm_top + 2, 0 })
  vim.b[bufnr].disasm_aside_win = win

  -- Auto-move
  vim.api.nvim_create_autocmd({ 'CursorMoved' }, {
    group = vim.api.nvim_create_augroup('disasm_aside_move', { clear = true }),
    pattern = { '*.c', '*.cpp' },
    callback = update_aside,
  })
end

function M.disassemble_Close()
  local bufnr  = vim.api.nvim_get_current_buf()

  if vim.b[bufnr].auto_close then
    local ref = vim.b[bufnr].disasm_popup_ref

    if ref and vim.api.nvim_win_is_valid(ref) then
      vim.api.nvim_win_close(ref, true)
    end

    vim.b[bufnr].disasm_popup_ref = false
    -- Remove the autocmd for the files for performances reasons
    vim.api.nvim_clear_autocmds({ group = 'disassembleOnCursorMoveGroup' })
  else
    vim.b[bufnr].auto_close = true
  end
end

function M.focus_popup()
  local bufnr  = vim.api.nvim_get_current_buf()
  local buffer = vim.b[bufnr]

  buffer.auto_close = false
  if buffer.disasm_popup_ref then
    vim.api.nvim_set_current_win(buffer.disasm_popup_ref)
  else
    vim.notify("No popup at the moment", vim.log.levels.WARN)
  end
end

return M
