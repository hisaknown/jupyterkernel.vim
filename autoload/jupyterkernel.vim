scriptencoding utf-8

let s:save_cpo = &cpoptions
set cpoptions&vim

if exists('s:is_loaded')
    finish
endif

let s:is_loaded = 1
let s:script_dir = expand('<sfile>:p:h')

let s:jupyterkernel_msg_id = 0
let s:jupyterkernel_buffer = ''

function! jupyterkernel#start_jkg(...) abort
    " Args: address_port
    if a:0 == 0
        " Make VimMessenger process
        if (g:jupyterkernel_address == 'localhost' || g:jupyterkernel_address == '127.0.0.1') && g:jupyterkernel_port == 0
            call execute('pyx ' .
                        \ 'from __future__ import print_function;' .
                        \ 'import socket;' .
                        \ 's = socket.socket();' .
                        \ 's.bind(("' . g:jupyterkernel_address . '", ' . g:jupyterkernel_port . '));' .
                        \ 'vim.vars["jupyterkernel_port"] = s.getsockname()[1];' .
                        \ 's.close()'
                        \ )
        endif
        if !exists('g:jupyterkernel_job') || job_status(g:jupyterkernel_job) != 'run'
            let g:jupyterkernel_job = job_start(
                        \ 'python ' . s:script_dir . '/jupyterkernel/jupyterkernel_client.py ' . 
                        \ '--vim_port ' . g:jupyterkernel_port
                        \ )
            " Connect to VimMessenger
            call timer_start(200, {timer -> jupyterkernel#connect_messenger(timer, g:jupyterkernel_address, g:jupyterkernel_port, bufnr('%'))}, {'repeat': -1})
        endif
    else
        if exists('b:jupyterkernel_ch') 
            if ch_status(b:jupyterkernel_ch) != 'closed' && ch_status(b:jupyterkernel_ch) != 'fail'
                call ch_close(b:jupyterkernel_ch)
            endif
            unlet b:jupyterkernel_ch
        endif
        let l:address = split(a:1, ':')[0]
        let l:port = split(a:1, ':')[1]
        " Connect to VimMessenger
        call timer_start(200, {timer -> jupyterkernel#connect_messenger(timer, l:address, l:port, bufnr('%'))}, {'repeat': -1})
    endif
endfunction

function! s:handle_result(ch, msg) abort
    " Handle message
    let l:msg = s:jupyterkernel_buffer . a:msg
    let l:msg_split = split(l:msg, '@@@', 1)
    let s:jupyterkernel_buffer = l:msg_split[-1]
    let l:msg_split = l:msg_split[:-2]

    try
        " Ignore InsertEnter temporary
        " NOTE: Firing InsertEnter or BufEnter causes neosnippet error.
        let l:eventignore = &eventignore
        set eventignore+=InsertEnter,BufEnter

        for l:msg in l:msg_split
            let l:msg_dict = json_decode(l:msg)
            " Temporary extract state info
            let l:temp_state = getbufvar(l:msg_dict['bufnr'], 'jupyterkernel_status')
            if index(['execute_result', 'stream', 'error'], l:msg_dict['msg_type']) != -1
                " Save current bufnr
                let l:former_bufnr = bufnr('%')
                " Open corresponding buffer temprorary
                call execute(l:msg_dict['bufnr'] . 'buffer')
                " Save curresponding buffer position
                let l:curpos = getcurpos()

                " Find corresponding line (or cell)
                let l:code_end_line = search('<!--.*' . json_encode({'msg_id': l:msg_dict['parent_header']['msg_id']})[1:-2] . '.*-->\n```.\+\n\_.\{-1,}```', 'nwe')
                " Check if stream code already exists
                if getline(l:code_end_line + 1) == '```'
                    call cursor(l:code_end_line + 1, 1)
                    let l:code_end_line = search('```\n\_.\{-1,}```', 'nWe')
                endif
                " Extract output
                if l:msg_dict['msg_type'] == 'execute_result'
                    let l:output = l:msg_dict['content']['data']['text/plain']
                else
                    let l:output = l:msg_dict['content']['text']
                endif
                " Add code fence
                if type(l:output) == v:t_string
                    let l:output = [l:output]
                endif
                let l:output = insert(l:output, '```')
                if l:msg_dict['msg_type'] == 'execute_result'
                    let l:output = insert(l:output, 'Out [' . l:msg_dict['content']['execution_count'] . ']:')
                endif
                let l:output = add(l:output, '```')
                " Put output
                call append(
                            \ l:code_end_line,
                            \ l:output,
                            \ )

                " Restore cursor position
                call cursor(l:curpos[1:])
                call execute(l:former_bufnr . 'buffer')
            elseif l:msg_dict['msg_type'] == 'execute_reply'
                " Save current bufnr
                let l:former_bufnr = bufnr('%')
                " Open corresponding buffer temprorary
                call execute(l:msg_dict['bufnr'] . 'buffer')
                " Save curresponding buffer position
                let l:curpos = getcurpos()

                " Find corresponding line (or cell)
                let l:code_start_line = search('<!--.*' . json_encode({'msg_id': l:msg_dict['parent_header']['msg_id']})[1:-2] . '.*-->', 'nw')
                call execute(l:code_start_line . 'substitute/In \[.\{-}\]/In [' . l:msg_dict['content']['execution_count'] .']')

                " Restore cursor position
                call cursor(l:curpos[1:])
                call execute(l:former_bufnr . 'buffer')
            elseif l:msg_dict['msg_type'] == 'status'
                let l:temp_state['kernel_state'] = l:msg_dict['content']['execution_state']
            elseif l:msg_dict['msg_type'] == 'kernel_id'
                " Save kernel id
                call setbufvar(l:msg_dict['bufnr'], 'jupyterkernel_kernel_id', l:msg_dict['kernel_id'])
            elseif l:msg_dict['msg_type'] == 'complete_reply'
                " Set completion candidates
                let l:candidates = []
                for l:i in range(len(l:msg_dict['content']['matches']))
                    call add(l:candidates, {
                                \ 'word': l:msg_dict['content']['matches'][i],
                                \ 'menu': l:msg_dict['content']['metadata']['_jupyter_types_experimental'][i]['type']})
                endfor
                if !complete_check() && mode() == 'i'
                    call complete(l:msg_dict['content']['cursor_start'] - s:complete_offset + 1, l:candidates)
                endif
            endif
            " Apply state info
            call setbufvar(l:msg_dict['bufnr'], 'jupyterkernel_status', temp_state)
            call jupyterkernel#set_winbar_status(l:msg_dict['bufnr'])
        endfor
    finally
        " Restore eventignore
        let &eventignore = l:eventignore
    endtry
endfunction

function! jupyterkernel#connect_messenger(timer, address, port, bufnr) abort
    let l:ch = ch_open(
                \ a:address . ':' .  a:port,
                \ {'mode': 'raw', 'callback': function('s:handle_result')},
                \ )
    if ch_status(l:ch) == 'open'
        call timer_stop(a:timer)
        if a:address != g:jupyterkernel_address || a:port != g:jupyterkernel_port
            call setbufvar(a:bufnr, 'jupyterkernel_ch', l:ch)
        else
            let g:jupyterkernel_ch = l:ch
        endif
    endif
endfunction

function! jupyterkernel#connect_kernel(...) abort
    " Args: kernel

    let l:dict = {
                \ 'type': 'start',
                \ 'bufnr': bufnr('%'),
                \ }
    if a:0 > 0
        if has_key(a:1, 'kernel_id')
            let l:dict['kernel_id'] = a:1['kernel_id']
        endif
        if has_key(a:1, 'kernel')
            let l:dict['kernel'] = a:1['kernel']
        endif
    endif

    if exists('b:jupyterkernel_ch')
        let l:ch = b:jupyterkernel_ch
    else
        let l:ch = g:jupyterkernel_ch
    endif
    call ch_sendraw(
                \ l:ch,
                \ json_encode(l:dict) . '@@@',
                \ )

    " Status dict
    let b:jupyterkernel_status = {
                \ 'kernel_state': 'busy',
                \ }
    call jupyterkernel#set_winbar_status(bufnr('%'))
    " Mapping
    nnoremap <buffer><silent> <S-Return> :<C-u>call jupyterkernel#send_inside_codefence()<CR>

    if &filetype != 'markdown'
        setlocal filetype=markdown
    endif
    setlocal omnifunc=jupyterkernel#complete
    autocmd BufWinLeave <buffer> call jupyterkernel#kill_kernel(getbufvar(str2nr(expand('<abuf>')), 'jupyterkernel_kernel_id'), str2nr(expand('<abuf>')))
endfunction

function! jupyterkernel#kill_kernel(...) abort
    " Args: kernel_id, bufnr

    let l:dict = {
                \ 'type': 'kill',
                \ }
    if a:0 > 0
        let l:dict['kernel_id'] = a:1
        let l:bufnr = a:2
    else
        let l:dict['kernel_id'] = b:jupyterkernel_kernel_id
        let l:bufnr = bufnr('%')
    endif

    if type(getbufvar(l:bufnr, 'jupyterkernel_ch')) == v:t_channel
        let l:ch = getbufvar(l:bufnr, 'jupyterkernel_ch')
    else
        let l:ch = g:jupyterkernel_ch
    endif
    call ch_sendraw(
                \ l:ch,
                \ json_encode(l:dict) . '@@@',
                \ )
endfunction

function! jupyterkernel#set_winbar_status(bufnr) abort
    let l:str = 'Jupyter/'
    let l:status = getbufvar(a:bufnr, 'jupyterkernel_status')

    if has_key(l:status, 'kernel_state')
        if l:status['kernel_state'] == 'busy'
            let l:str .= '●/'
        elseif l:status['kernel_state'] == 'idle'
            let l:str .= '○/'
        else
            let l:str .= l:status['kernel_state'] . '/'
        endif
    endif

    let l:current_winid = win_getid()
    call win_gotoid(win_findbuf(a:bufnr)[0])
    let l:winbar_status = getbufvar(a:bufnr, 'jupyterkernel_winbar_status')
    if l:winbar_status != ''
        execute('unmenu WinBar.' . l:winbar_status)
    endif
    execute('nnoremenu 1.0 WinBar.' . l:str . ' <Nop>')
    call win_gotoid(l:current_winid)
    call setbufvar(a:bufnr, 'jupyterkernel_winbar_status', l:str)
endfunction

function! jupyterkernel#get_around_codefence() abort
    let l:line_start = search('^```.\+$', 'bnW')
    let l:line_end = search('^```$', 'nW')
    " Check if there is code fence
    if l:line_start == 0 || l:line_end == 0
        echo 'Out of code fence!'
        return
    endif
    " Check if cursor is in a code block
    if search('^```', 'bnW') != l:line_start || search('^```', 'nW') != l:line_end
        echo 'Out of code fence!'
        return 1
    endif

    let l:dict = {
                \ 'line_start': l:line_start,
                \ 'line_end': l:line_end,
                \ 'content': getline(l:line_start, l:line_end),
                \ }

    return l:dict
endfunction

function! jupyterkernel#send_inside_codefence() abort
    " Get code
    let l:code = jupyterkernel#get_around_codefence()
    if type(l:code) != v:t_dict
        return
    endif
    let l:matched_text = l:code['content']
    let l:line_start = l:code['line_start']
    let l:line_end = l:code['line_end']

    " Get new (and unique) msg_id
    let l:msg_id = s:issue_msg_id()

    " Set metadata
    if l:line_start == 1 || search('<!--.*-->', 'bnW') != l:line_start - 1
        " Set new metadata
        call append(l:line_start - 1, 'In [ ]: <!-- -->')
        " Adjust line number
        let l:line_start += 1
        let l:line_end += 1
    elseif search('<!--.*-->', 'bnW') == l:line_start - 1
        " Set new metadata
        call setline(l:line_start - 1, 'In [ ]: <!-- -->')
    endif
    let l:meta = json_encode({
                \'msg_id': l:msg_id,
                \'type': 'code',
                \ })
    let l:meta = substitute(getline(l:line_start - 1), '<!--.*-->', '<!--' . l:meta . '-->', '')
    call setline(l:line_start - 1, l:meta)

    " Wipe existing output
    let l:curpos = getcurpos()
    if getline(l:line_end + 1)[:2] == '```'
        call cursor(l:line_end + 1, 1)
        if search('```\n\_.\{-1,}```\n', 'nWc') != 0
            call execute(
                        \ search('```\n\_.\{-1,}```\n', 'nWc') . ',' .
                        \ search('```\n\_.\{-1,}```\n', 'nWec') . 'delete _')
        endif
    endif
    if getline(l:line_end + 1)[:4] == 'Out ['
        call cursor(l:line_end + 1, 1)
        if search('Out \[\d\+\]:\n```\n\_.\{-1,}```\n', 'nWc') != 0
            call execute(
                        \ search('Out \[\d\+\]:\n```\n\_.\{-1,}```\n', 'nWc') . ',' .
                        \ search('Out \[\d\+\]:\n```\n\_.\{-1,}```\n', 'nWec') . 'delete _')
        endif
    endif
    call cursor(l:curpos[1:])

    let l:dict = {
                \ 'type': 'execute',
                \ 'kernel_id': b:jupyterkernel_kernel_id,
                \ 'code': join(l:matched_text[1:-2], "\n"),
                \ 'msg_id': l:msg_id,
                \ }
    if exists('b:jupyterkernel_ch')
        let l:ch = b:jupyterkernel_ch
    else
        let l:ch = g:jupyterkernel_ch
    endif
    call ch_sendraw(l:ch,
                \  json_encode(l:dict) . '@@@'
                \ )
endfunction

function! jupyterkernel#complete(findstart, base) abort
    if a:findstart
	    return -4
    endif

    " Get code
    let l:code = jupyterkernel#get_around_codefence()
    if type(l:code) != v:t_dict
        return
    endif
    let l:matched_text = l:code['content']
    let l:line_start = l:code['line_start']

    " Get new (and unique) msg_id
    let l:msg_id = s:issue_msg_id()

    " Extract cursor position
    let l:curpos = 0
    for l:s in l:matched_text[1:(line('.') - l:line_start - 1)]
        let l:curpos += strlen(l:s) + 1
    endfor
    let s:complete_offset = l:curpos
    let l:curpos += col('.') - 1

    let l:dict = {
                \ 'type': 'complete',
                \ 'kernel_id': b:jupyterkernel_kernel_id,
                \ 'code': join(l:matched_text[1:-2], "\n"),
                \ 'cursor_pos': l:curpos,
                \ 'msg_id': l:msg_id,
                \ }
    if exists('b:jupyterkernel_ch')
        let l:ch = b:jupyterkernel_ch
    else
        let l:ch = g:jupyterkernel_ch
    endif
    call ch_sendraw(l:ch,
                \  json_encode(l:dict) . '@@@'
                \ )

    return v:none
endfunction

function! s:issue_msg_id() abort
    let s:jupyterkernel_msg_id += 1
    return s:jupyterkernel_msg_id
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
