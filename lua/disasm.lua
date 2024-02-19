local M = {}


function M.setup()
  vim.cmd [[
    command! Disassemble call disassemble#Disassemble()
    command! DisassembleFull call disassemble#DisassembleFull()
    command! DisassembleFocus call disassemble#Focus()
    command! DisassembleConfig call disassemble#Config()
    command! DisassembleSaveConfig call disassemble#SaveConfig()
  ]]
end


return M
