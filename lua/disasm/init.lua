local core = require 'disasm.core'

local M = {
  disassemble = core.disassemble,
  disassemble_full = core.disassemble_full,
  focus       = core.focus_popup,
  reconfigure = core.reconfigure,
  save_config = core.save_config,
  close       = core.disassemble_Close,
}


function M.setup()
  vim.g.disasm_ns = vim.api.nvim_create_namespace 'disasm'
  vim.api.nvim_set_hl(0, 'DisasmCurrent', { fg = '#ffffff', bg = '#333333' })
end


return M
