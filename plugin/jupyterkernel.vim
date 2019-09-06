let s:save_cpo = &cpo
set cpo&vim

if exists('s:is_loaded')
    finish
endif
let s:is_loaded = 1

if !exists('g:jupyterkernel#_client_port')
    let g:jupyterkernel#_client_port = 0
endif
if !exists('g:jupyterkernel#default_kernel')
    let g:jupyterkernel#default_kernel = 'python'
endif

command! -nargs=* JupyterKernelConnect call s:connect('<args>')

function! s:connect(args) abort
    let l:args = split(a:args)
    let l:kernelspec = {'kernel': g:jupyterkernel#default_kernel}
    let l:address = 'localhost'
    let l:port = 0

    " Check args
    if a:args != ''
        for l:a in l:args
            if stridx(l:a, ':') != -1 " Is address:port?
                let l:address = split(l:a, ':')[0]
                let l:port = str2nr(split(l:a, ':')[1])
            else
                let l:kernelspec['kernel'] = l:a
            endif
        endfor
    endif

    " Connect to Jupyter Kernel Gateway
    call jupyterkernel#start_jkg(l:address, l:port)

    " Start kernel
    call timer_start(50, {timer -> s:start_kernel(timer, bufnr('%'), l:kernelspec)}, {'repeat': -1})

    " Set status
    let b:jupyterkernel_status = {
                \ 'kernel_state': 'Starting',
                \ }
    call jupyterkernel#set_winbar_status(bufnr('%'))
endfunction

function! s:start_kernel(timer, bufnr, ...)
    if a:bufnr != v:null
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
