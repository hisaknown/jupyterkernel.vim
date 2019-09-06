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
    - `[address:port]` (optional): Address and port to Jupyter Kernel Gateway (e.g. `localhost:8888`). If omitted, Jupyter Kernel Gateway will run in localhost with random port.
    - `[kernel]` (optional): Kernel name (e.g. `python`).

## Variables
- `g:jupyterkernel#default_kernel`: Default kernel. Defaults to `python`.

## Working with remote machines
Say you have a powerful machine called `remote-machine`, and you want to calculate on it using jupyterkernel.vim.  
You may do following steps:
1. Login to `remote-machine` and execute `jupyter kernelgateway`
    - Requires `jupyter_kernel_gateway` installed.
    - You may need to specify `--port` and `--ip`.
2. At your local machine, launch vim and execute `JupyterKernelConnect remote-machine:8888`

## How it works

```
+-----+
| Vim |
+--+--+
   | TCP
+--+-----------------------------------------------+
| jupyterkernel_client.py (on machine vim running) |
+--+-----------------------------------------------+
   | Websocket
+--+-----------------------------------+
| Jupyter Kernel Gateway (on any host) |
+--------------------------------------+
```

## Debugging
- Run `jupyterkernel_client.py` manually.
    - Can be interrupted by `Ctrl-C`.
```bash
python autoload/jupyterkernel/jupyterkernel_client.py --vim_port 55555
```
- Launch Vim
- Set `g:jupyterkernel#_client_port` to the port
    - e.g. `let g:jupyterkernel#_client_port = 55555`
- Execute command `JupyterKernelConnect`.
- Run some code.
- Log should show in the terminal which runs `jupyterkernel_client.py`.

## TODOs
- Save to, and load from `.ipynb`
- Notify disconnect
- Explicit quitting, other than closing buffer
    - Closing buffer is only a way to close session (i.e. kill kernel), so far.
