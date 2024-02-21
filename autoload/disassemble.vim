let s:core = luaeval('require "disasm.core"')

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Main functions
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! disassemble#Disassemble()
  " Close the current window if we are already in a popup buffer and want to
  " get a popup, which make no sense in this context
  if get(b:, "disassemble_this_is_a_popup_buffer", v:false)
    silent! call nvim_win_close(0, v:true)
    return 0
  endif

  if g:disassemble_autosave
    silent! write
  endif

  " Load the configuration for this buffer
  call s:core.getConfig()

  " Remove or focus the popup
  if b:disassemble_popup_window_id
    if g:disassemble_focus_on_second_call
      call disassemble#Focus()
      return 0
    else
      call disassemble#Close()
    endif
  endif

  " Extract the objdump content to the correct buffer variables
  if s:core.get_objdump()
    return 1
  endif

  let [l:pos_current_line_in_asm, l:pos_next_line_in_asm] = s:core.searchCurrentLine()
  if l:pos_current_line_in_asm == -1
    return 1
  endif

  " Only select the current chunk of asm
  let b:objdump_asm_output = b:objdump_asm_output[l:pos_current_line_in_asm:l:pos_next_line_in_asm - 1]

  " Set the popup options
  let l:width = max(map(copy(b:objdump_asm_output), "strlen(v:val)"))
  let l:height = l:pos_next_line_in_asm - l:pos_current_line_in_asm

  " Create the popup window
  let l:buf = nvim_create_buf(v:false, v:true)
  let l:opts = { "relative": "cursor",
        \ "width": l:width,
        \ "height": l:height,
        \ "col": 0,
        \ "row": 1,
        \ "anchor": "NW",
        \ "style": "minimal",
        \ "focusable": v:true,
        \ }

  let b:disassemble_popup_window_id = nvim_open_win(l:buf, 0, l:opts)

  call nvim_buf_set_lines(l:buf, 0, l:height, v:false, b:objdump_asm_output)
  call nvim_buf_set_option(l:buf, "filetype", "asm")
  call nvim_buf_set_var(l:buf, "disassemble_this_is_a_popup_buffer", v:true)
  call nvim_win_set_cursor(b:disassemble_popup_window_id, [1, 0])

  augroup disassembleOnCursorMoveGroup
    autocmd!
    autocmd CursorMoved,BufLeave *.c,*.cpp call disassemble#Close()
  augroup END
endfunction

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

