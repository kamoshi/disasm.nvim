let s:core = luaeval('require "disasm.core"')

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Main functions
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! disassemble#DisassembleFull()
  if g:disassemble_autosave
    silent! write
  endif

  " Load the configuration for this buffer
  call s:core.getConfig()

  " Extract the objdump content to the correct buffer variables
  if s:get_objdump()
    return 1
  endif

  let [l:pos_current_line_in_asm, l:pos_next_line_in_asm] = s:core.searchCurrentLine()
  if l:pos_current_line_in_asm == -1
    return 1
  endif

  " Create or reuse the last buffer
  if !get(b:, "buffer_full_asm", v:false)
    let b:buffer_full_asm = nvim_create_buf(v:true, v:true)
    call nvim_buf_set_name(b:buffer_full_asm, "[Disassembled] " . b:disassemble_config["binary_file"])
  else
    call nvim_buf_set_option(b:buffer_full_asm, "readonly", v:false)
  endif

  " Set the content to the buffer
  call nvim_buf_set_lines(b:buffer_full_asm, 0, 0, v:false, b:objdump_asm_output)

  " Set option for that buffer
  call nvim_buf_set_option(b:buffer_full_asm, "filetype", "asm")
  call nvim_buf_set_option(b:buffer_full_asm, "readonly", v:true)

  " Focus the buffer
  execute 'buffer ' . b:buffer_full_asm

  " Open the current line
  call nvim_win_set_cursor(0, [l:pos_current_line_in_asm+2, 0])

endfunction

function! disassemble#Close()
  if get(b:,"auto_close", v:true)
    if get(b:, "disassemble_popup_window_id", v:false)
      silent! call nvim_win_close(b:disassemble_popup_window_id, v:true)
      let b:disassemble_popup_window_id = v:false

      " Remove the autocmd for the files for performances reasons
      augroup disassembleOnCursorMoveGroup
        autocmd!
      augroup END
    endif
  else
    let b:auto_close = v:true
  endif
endfunction

function! disassemble#Focus()
  let b:auto_close = v:false
  if get(b:, "disassemble_popup_window_id", v:false)
    silent! call nvim_set_current_win(b:disassemble_popup_window_id)
  else
    echohl WarningMsg
    echomsg "No popup at the moment"
    echohl None
  endif
endfunction

