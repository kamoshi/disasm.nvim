local core = require 'disasm.core'

local M = {
  disassemble = core.disassemble_Disassemble,
  disassemble_full = core.disassemble_DisassembleFull,
  focus = core.disassemble_Focus,
  reconfigure = core.reconfigure,
  save_config = core.save_config,
  close = core.disassemble_Close,
}


function M.setup()
end


return M
