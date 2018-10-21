let s:save_cpo = &cpo
set cpo&vim

if exists('s:is_loaded')
    finish
endif
let s:is_loaded = 1

if !exists('g:jupyterkernel_port')
    let g:jupyterkernel_port = 0
endif
if !exists('g:jupyterkernel_address')
    let g:jupyterkernel_address = 'localhost'
endif
if !exists('g:jupyterkernel_kernel')
    let g:jupyterkernel_kernel = 'python'
endif

command! -nargs=* JupyterKernelConnect call s:connect('<args>')

function! s:connect(args) abort
    if a:args == ''
        call jupyterkernel#start_jkg()
        call timer_start(50, {timer -> s:start_kernel(timer, v:none)}, {'repeat': -1})
    else
        " Check args
        let l:args = split(a:args)
        let l:bufnr = v:none
        for l:a in l:args
            if stridx(l:a, ':') != -1 " Is address:port?
                let l:address_port = l:a
                call jupyterkernel#start_jkg(l:a)
                let l:bufnr = bufnr('%')
            else
                let l:kernel = l:a
            endif
        endfor

        " Connect to Jupyter Kernel Gateway
        if exists('l:address_port')
            call jupyterkernel#start_jkg(l:address_port)
        else
            call jupyterkernel#start_jkg()
        endif

        " Start kernel
        if exists('l:kernel')
            call timer_start(50, {timer -> s:start_kernel(timer, l:bufnr, l:kernel)}, {'repeat': -1})
        else
            call timer_start(50, {timer -> s:start_kernel(timer, l:bufnr)}, {'repeat': -1})
        endif
    endif
endfunction

function! s:start_kernel(timer, bufnr, ...)
    if a:bufnr != v:none
        let l:ch = getbufvar(a:bufnr, 'jupyterkernel_ch', 0)
        let l:ch_exists = type(l:ch) == v:t_channel
    else
        let l:ch_exists = exists('g:jupyterkernel_ch')
    endif
    if l:ch_exists
        call timer_stop(a:timer)
        if a:0 > 0
            call jupyterkernel#connect_kernel(a:1)
        else
            call jupyterkernel#connect_kernel()
        endif
    endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
