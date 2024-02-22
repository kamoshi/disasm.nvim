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
end


return M
