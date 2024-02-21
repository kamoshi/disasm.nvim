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
    compilation = try_parse_config_line(lines, "compile: "),
    objdump     = try_parse_config_line(lines, "objdump: "),
    binary_file = try_parse_config_line(lines, "binary_file: ")
  }
end

---@param bufnr number
local function setConfiguration(bufnr)
  -- Create the variables to store the temp files
  vim.b.asm_tmp_file   = vim.b.asm_tmp_file or vim.fn.tempname()
  vim.b.error_tmp_file = vim.b.error_tmp_file or vim.fn.tempname()

  -- Get the default commands from the global namespace
  local default_compilation_command = vim.fn.printf( "gcc %s -o %s -g", vim.fn.expand("%"), vim.fn.expand("%:r"))
  local default_objdump_command = "objdump --demangle --line-numbers --file-headers --file-offsets --source-comment --no-show-raw-insn --disassemble -M intel " .. vim.fn.expand("%:r")
  local default_binary_file = vim.fn.expand("%:r")

  -- Set the default values for the compilation and objdump commands
  local config = vim.b.disassemble_config or {
    compilation = default_compilation_command,
    objdump = default_objdump_command,
    binary_file = default_binary_file,
    objdump_with_redirect = default_objdump_command
  }

  -- Try to parse the configuration file
  local config_file = vim.fn.printf("%s.%s", vim.fn.expand("%"), vim.g.disassemble_configuration_extension)
  if vim.fn.filereadable(config_file) ~= 0 then
    config = vim.tbl_extend('force', config, try_parse_config(vim.fn.readfile(config_file)))
  end

  -- Try to parse the start of the current file for configuration
  config = vim.tbl_extend('force', config, try_parse_config(vim.fn.getline(1,10)))

  -- Ask the user for the compilation and objdump extraction commands
  if vim.b.enable_compilation then
    local compilation = vim.fn.input({ prompt = "compilation command> ", default = config.compilation })
    config = vim.tbl_extend('force', config, { compilation = compilation })
  end

  local objdump   = vim.fn.input({ prompt = "objdump command> ", default = config.objdump })
  local objdump_r = objdump .. " 1>" .. vim.b.asm_tmp_file .. " 2>" .. vim.b.error_tmp_file

  config = vim.tbl_extend('force', config, { objdump = objdump, objdump_with_redirect = objdump_r })

  vim.b.disassemble_config = config

  vim.cmd [[redraw]]
  vim.notify('Disassemble.nvim configured for this buffer!', vim.log.levels.INFO)
end

function M.getConfig()
  -- Create the variable to store the window id
  vim.b.disassemble_popup_window_id = vim.b.disassemble_popup_window_id or false

  -- Check if the plugin should compile automatically
  vim.b.enable_compilation = vim.b.enable_compilation or vim.g.disassemble_enable_compilation

  -- " Check if the plugin is already configured
  if not vim.b.disassemble_config then
    setConfiguration()
  end
end

function M.disassemble_Config()
  setConfiguration()
end

function M.disassemble_SaveConfig()
  M.getConfig()

  local config_file = vim.fn.printf("%s.%s", vim.fn.expand("%"), vim.g.disassemble_configuration_extension)
  local output_configuration = {
    vim.fn.printf("compile: %s", vim.b.disassemble_config.compilation),
    vim.fn.printf("objdump: %s", vim.b.disassemble_config.objdump),
    vim.fn.printf("binary_file: %s", vim.b.disassemble_config.binary_file)
  }

  vim.fn.writefile(output_configuration, config_file)
  vim.notify("Disassemble configuration saved to '" .. config_file .. "'")
end

-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
-- " Compilation function
-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

---@return boolean -- is failure?
local function do_compile()
  local result = vim.fn.system(vim.b.disassemble_config.compilation)
  if vim.v.shell_error == 1 then
    vim.notify(
      'Error while compiling. Check the compilation command.\n> ' .. vim.b.disassemble_config.compilation .. '\n' .. result,
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

function M.do_objdump()
  -- Reset the output variables
  vim.b.compilation_error = false
  vim.b.objdump_asm_output = false

  -- Extract the objdump information to the `error_tmp_file` and `asm_tmp_file` files
  vim.fn.system(vim.b.disassemble_config.objdump_with_redirect)
  if vim.v.shell_error == 1 then
    return 1
  end

  -- Get the error from the temporary file
  vim.b.compilation_error = vim.fn.readfile(vim.b.error_tmp_file)
  vim.b.compilation_error = vim.fn.string(vim.b.compilation_error)

  -- Return the error code 128 if the C file is more recent that the ELF file
  if vim.fn.match(vim.b.compilation_error, "is more recent than object file") ~= -1 then
    return 128
  end

  -- Get the content of the objdump file
  vim.b.objdump_asm_output = vim.fn.systemlist("expand -t 4 " .. vim.b.asm_tmp_file)
  if vim.v.shell_error == 1 then
    return 1
  end

  -- Return OK
  return 0
end


function M.get_objdump()
  -- Check the presence of the ELF file
  if vim.fn.filereadable(vim.b.disassemble_config["binary_file"]) ~= 1 then
    if not vim.b.enable_compilation then
      vim.notify("the file '" .. vim.b.disassemble_config["binary_file"] .. "' is not readable", vim.log.levels.WARN)
      return 1
    else
      if do_compile() then
        return 1
      end
    end
  end

  -- Check if the binary file has debug informations
  vim.b.has_debug_info = vim.fn.system("file " .. vim.b.disassemble_config["binary_file"])
  if vim.fn.match(vim.b.has_debug_info, "with debug_info") == -1 then
    vim.notify("the file '" .. vim.b.disassemble_config["binary_file"] .. "' does not have debug information", vim.log.levels.WARN)
    return 1
  end

  -- Get the objdump content
  local objdump_return_code = M.do_objdump()

  if objdump_return_code == 1 then
    -- Unknown error in the function
    return 1
  elseif objdump_return_code == 128 then
    -- Check if the C source code is more recent than the object file
    -- Try to recompile and redump the objdump content
    if not vim.b.enable_compilation then
      vim.notify("Automatic compilation is disabled for this buffer; we can not have a up-to-date ELF file to work on...", vim.log.levels.WARN)
      return 1
    else
      if do_compile() then
        return 1
      end
      return M.get_objdump()
    end
  else
    return 0
  end
end

-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
-- " Data processing
-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function M.searchCurrentLine()
  -- Search the current line
  local current_line_checked = vim.fn.line '.'
  local pos_current_line_in_asm = { "", -1 }
  local lines_searched = 0

  while pos_current_line_in_asm[2] < 0 do
    pos_current_line_in_asm = vim.fn.matchstrpos(vim.b.objdump_asm_output, vim.fn.expand('%:t') .. ':' .. current_line_checked .. [[\(\s*(discriminator \d*)\)*$]])

    current_line_checked = current_line_checked + 1

    lines_searched = lines_searched + 1
    if lines_searched >= 20 then
      vim.api.nvim_echo({{'this is line not found in the asm file ... ? contact the maintainer with an example of this situation', 'WarningMsg'}}, true, {})
      return { -1, -1 }
    end
  end

  -- Search the next occurrence of the filename
  local pos_next_line_in_asm = vim.fn.matchstrpos(vim.b.objdump_asm_output, vim.fn.expand('%:t') .. ':', pos_current_line_in_asm[2] + 1)

  -- If not found, it's probably because this code block is at the end of a section. This will search the start of the next section.
  if pos_next_line_in_asm[2] == -1 then
    pos_next_line_in_asm = vim.fn.matchstrpos(vim.b.objdump_asm_output, [[\v^\x+\s*]], pos_current_line_in_asm[2] + 1)
  end

  return { pos_current_line_in_asm[2], pos_next_line_in_asm[2] }
end

-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
-- " Main functions
-- """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function M.disassemble_Disassemble()
  -- Close the current window if we are already in a popup buffer and want to
  -- get a popup, which make no sense in this context
  if vim.b.disassemble_this_is_a_popup_buffer then
    vim.api.nvim_win_close(0, true)
    return 0
  end

  if vim.g.disassemble_autosave then
    vim.cmd [[silent! write]]
  end

  -- Load the configuration for this buffer
  M.getConfig()

  -- Remove or focus the popup
  if vim.b.disassemble_popup_window_id then
    if vim.g.disassemble_focus_on_second_call then
      M.disassemble_Focus()
      return 0
    else
      M.disassemble_Close()
    end
  end

  -- Extract the objdump content to the correct buffer variables
  if M.get_objdump() == 1 then
    return 1
  end

  local res = M.searchCurrentLine()
  local pos_current_line_in_asm, pos_next_line_in_asm = res[1], res[2]
  if pos_current_line_in_asm == -1 then
    return 1
  end

  -- Only select the current chunk of asm
  vim.b.objdump_asm_output = {unpack(vim.b.objdump_asm_output, pos_current_line_in_asm + 1, pos_next_line_in_asm)}

  -- Set the popup options
  local width  = vim.fn.max(vim.fn.map(vim.fn.copy(vim.b.objdump_asm_output), "strlen(v:val)"))
  local height = pos_next_line_in_asm - pos_current_line_in_asm

  -- Create the popup window
  local buf = vim.api.nvim_create_buf(false, true)
  local opts = {
    relative  = 'cursor',
    width     = width,
    height    = height,
    col       = 0,
    row       = 1,
    anchor    = "NW",
    style     = "minimal",
    focusable = true,
  }

  vim.b.disassemble_popup_window_id = vim.api.nvim_open_win(buf, false, opts)

  vim.api.nvim_buf_set_lines(buf, 0, height, false, vim.b.objdump_asm_output)
  vim.api.nvim_buf_set_option(buf, "filetype", "asm")
  vim.api.nvim_buf_set_var(buf, "disassemble_this_is_a_popup_buffer", true)
  vim.api.nvim_win_set_cursor(vim.b.disassemble_popup_window_id, { 1, 0 })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufLeave' }, {
    group = vim.api.nvim_create_augroup('disassembleOnCursorMoveGroup', { clear = true }),
    pattern = { '*.c', '*.cpp' },
    callback = M.disassemble_Close,
  })
end

function M.disassemble_DisassembleFull()
  if vim.g.disassemble_autosave then
    vim.cmd [[silent! write]]
  end

  --  the configuration for this buffer
  M.getConfig()

  -- Extract the objdump content to the correct buffer variables
  if M.get_objdump() == 1 then
    return 1
  end

  local pos_current_line_in_asm = M.searchCurrentLine()[1]
  if pos_current_line_in_asm == -1 then
    return 1
  end

  -- Create or reuse the last buffer
  if not vim.b.buffer_full_asm then
    vim.b.buffer_full_asm = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(vim.b.buffer_full_asm, "[Disassembled] " .. vim.b.disassemble_config["binary_file"])
  else
    vim.api.nvim_buf_set_option(vim.b.buffer_full_asm, "readonly", false)
  end

  -- Set the content to the buffer
  vim.api.nvim_buf_set_lines(vim.b.buffer_full_asm, 0, 0, false, vim.b.objdump_asm_output)

  -- Set option for that buffer
  vim.api.nvim_buf_set_option(vim.b.buffer_full_asm, "filetype", "asm")
  vim.api.nvim_buf_set_option(vim.b.buffer_full_asm, "readonly", true)

  -- Focus the buffer
  vim.cmd [[execute 'buffer ' . b:buffer_full_asm]]

  -- Open the current line
  vim.api.nvim_win_set_cursor(0, { pos_current_line_in_asm+2, 0 })
end

function M.disassemble_Close()
  if vim.b.auto_close then
    if vim.b.disassemble_popup_window_id then
      vim.api.nvim_win_close(vim.b.disassemble_popup_window_id, true)
      vim.b.disassemble_popup_window_id = false

      -- Remove the autocmd for the files for performances reasons
      vim.api.nvim_clear_autocmds({ group = 'disassembleOnCursorMoveGroup' })
    end
  else
    vim.b.auto_close = true
  end
end

function M.disassemble_Focus()
  vim.b.auto_close = false
  if vim.b.disassemble_popup_window_id then
    vim.api.nvim_set_current_win(vim.b.disassemble_popup_window_id)
  else
    vim.notify("No popup at the moment", vim.log.levels.WARN)
  end
end

return M
