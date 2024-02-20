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


return M
