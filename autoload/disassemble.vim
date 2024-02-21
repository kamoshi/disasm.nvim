let s:core = luaeval('require "disasm.core"')

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Compilation function
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:do_compile()
  let l:compilation_result = system(b:disassemble_config["compilation"])
  if v:shell_error
    echohl WarningMsg
    echomsg "Error while compiling. Check the compilation command."
    echo "\n"

    echohl Question
    echomsg "> " . b:disassemble_config["compilation"]
    echo "\n"

    echohl ErrorMsg
    echo l:compilation_result
    echo "\n"

    echohl None

    return 1

  else
    return 0

  endif
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Objectdump extraction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:do_objdump()
  " Reset the output variables
  let b:compilation_error = v:false
  let b:objdump_asm_output = v:false

  " Extract the objdump information to the `error_tmp_file` and `asm_tmp_file` files
  call system(b:disassemble_config["objdump_with_redirect"])
  if v:shell_error
    return 1
  endif

  " Get the error from the temporary file
  let b:compilation_error = readfile(b:error_tmp_file)
  let b:compilation_error = string(b:compilation_error)

  " Return the error code 128 if the C file is more recent that the ELF file
  if match(b:compilation_error, "is more recent than object file") != -1
    return 128
  endif

  " Get the content of the objdump file
  let b:objdump_asm_output = systemlist("expand -t 4 " . b:asm_tmp_file)
  if v:shell_error
    return 1
  endif

  " Return OK
  return 0
endfunction

function! s:get_objdump()
  " Check the presence of the ELF file
  if !filereadable(b:disassemble_config["binary_file"])
    if !b:enable_compilation
      echohl WarningMsg
      echomsg "the file '" . b:disassemble_config["binary_file"] . "' is not readable"
      echohl None
      return 1
    else
      if s:do_compile()
        return 1
      endif
    endif
  endif

  " Check if the binary file has debug informations
  let b:has_debug_info = system("file " . b:disassemble_config["binary_file"])
  if match(b:has_debug_info, "with debug_info") == -1
    echohl WarningMsg
    echomsg "the file '" . b:disassemble_config["binary_file"] . "' does not have debug information"
    echohl None
    return 1
  endif

  " Get the objdump content
  let l:objdump_return_code = s:do_objdump()

  if l:objdump_return_code == 1
    " Unknown error in the function
    return 1

  elseif l:objdump_return_code == 128
    " Check if the C source code is more recent than the object file
    " Try to recompile and redump the objdump content
    if !b:enable_compilation
      echohl WarningMsg
      echomsg "Automatic compilation is disabled for this buffer; we can not have a up-to-date ELF file to work on..."
      echohl None
      return 1

    else
      if s:do_compile()
        return 1
      endif
      return s:get_objdump()
    endif

  else
    return 0

  endif
endfunction

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
  if s:get_objdump()
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

