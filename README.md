# Jupyterkernel.vim
Give the power of Jupyter to your vim.

Note: This plugin is EXPERIMENTAL so far.

## Requirements
- Vim 8
    - `+python` or `+python3`
- Python 3 (as `python`)
    - `jupyter`
    - `jupyter_kernel_gateway`
    - `psutil`

## Try it out
- `:JupyterKernelConnect`
- Write some code within code fence.
    - NOTE: Language must be specified in the upper fence.
- Press `<S-Return>` (Shift+Return) in the code fence.
- Yay!
- Example:
![screencast](https://raw.githubusercontent.com/wiki/hisaknown/jupyterkernel.vim/jupyterkernel.gif)

## Commands
- `JupyterKernelConnect [address:port] [kernel]`
    - `[address:port]` (optional): Address and port (e.g. `localhost:8888`)
    - `[kernel]` (optional): Kernel name (e.g. `python`)

## Variables
- `g:jupyterkernel_address`: Default address to Jupyter Kernel Gateway. Defaults to `localhost`.
- `g:jupyterkernel_port`: Default port to Jupyter Kernel Gateway. Defaults to `0`.
- `g:jupyterkernel_kernel`: Default kernel

NOTE: If `g:jupyterkernel_address == 'localhost'` and  `g:jupyterkernel_port == 0`, an instance of Jupyter Kernel Gateway is launched on `localhost:[random port]` with the first call of `JupyterKernelConnect`.

## Debugging
- Launch (Vim)-(Jupyter Kernel Gateway) connecter manually.
    - Can be interrupt by `Ctrl-C`.
```bash
python autoload/jupyterkernel/jupyterkernel_client.py --vim_port 55555
```
- Launch Vim, and execute command `JupyterKernelConnect localhost:55555`.
- Run some code.
- Log should show in the terminal which runs `jupyterkernel_client.py`.

## TODOs
- Save to, and load from `.ipynb`
- Notify disconnect
- Explicit quitting, other than closing buffer
    - Closing buffer is only a way to close session (i.e. kill kernel), so far.
