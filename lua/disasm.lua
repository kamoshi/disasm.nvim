local core = require 'disasm.core'

local M = {
  disassemble = core.disassemble_Disassemble,
  disassemble_full = core.disassemble_DisassembleFull,
  focus = core.disassemble_Focus,
  config = core.disassemble_Config,
  save_config = core.disassemble_SaveConfig,
  close = core.disassemble_Close,
}


function M.setup()
end


return M
