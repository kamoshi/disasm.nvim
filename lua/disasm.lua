local core = require 'disasm.core'

local M = {
  disassemble = core.disassemble_Disassemble,
}


function M.setup()
  vim.cmd [[
    command! DisassembleFull call disassemble#DisassembleFull()
    command! DisassembleFocus call disassemble#Focus()
    command! DisassembleConfig call disassemble#Config()
    command! DisassembleSaveConfig call disassemble#SaveConfig()
  ]]
end


return M
