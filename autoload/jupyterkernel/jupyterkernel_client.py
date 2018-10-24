import os
from tornado import gen
from tornado.escape import json_encode, json_decode, url_escape
from tornado.websocket import websocket_connect
from tornado.ioloop import IOLoop
from tornado.httpclient import HTTPClient, AsyncHTTPClient, HTTPRequest
from tornado.simple_httpclient import HTTPTimeoutError
from tornado.tcpserver import TCPServer
from tornado.iostream import StreamClosedError
from uuid import uuid4

import tornado.netutil

import sys
import argparse
import logging
import subprocess
import threading
from pprint import pprint
import psutil
from time import sleep

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)


class JupyterKernelGatewayHandler(threading.Thread):
    def __init__(self, args):
        threading.Thread.__init__(
            self, name='JupyterKernelGatewayHandler'
        )
        self._args = args
        self.vim_messenger = None
        self.kernel_threads = []
        self.kill = threading.Event()

    def run(self):
        # Start Jupyter if the port is not specified
        if (self._args.jupyter_port is None
                and self._args.jupyter_address in ['localhost', '127.0.0.1']):
            for s in tornado.netutil.bind_sockets(0):
                if self._args.jupyter_port is None:
                    self._args.jupyter_port = s.getsockname()[1]
                s.close()
            logger.debug('Port {} found for Jupyter'.format(self._args.jupyter_port))
            logger.debug('Launch Jupyter kernel gateway')
            self.jkg_p = subprocess.Popen(
                ['jupyter',
                 'kernelgateway',
                 '--port',
                 '{}'.format(self._args.jupyter_port),
                 ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        self.jupyter_port = self._args.jupyter_port

        # URLs
        self.base_url = 'http://' + self._args.jupyter_address + ':' + str(self.jupyter_port)
        self.base_ws_url = 'ws://' + self._args.jupyter_address + ':' + str(self.jupyter_port)

        # Wait until being killed
        self.kill.wait()

        # Stop all kernel threads
        for thread in self.kernel_threads:
            if thread.is_alive():
                thread.ioloop.add_callback(lambda: thread.ws.close())

        # Wait for kernel process to terminate, if SIGINT is sent.
        sleep(5)
        if self.jkg_p.poll() is None:
            # Terminate Jupyter kernel gateway if it is launched within this script
            if hasattr(self, 'jkg_p'):
                if os.name == 'nt':
                    # On Windows, child processes may not be terminated properly
                    # by killing parent
                    parent = psutil.Process(self.jkg_p.pid)
                    children = parent.children(recursive=True)
                    for child in children:
                        child.kill()
                    parent.kill()
                else:
                    self.jkg_p.terminate()
                logger.debug('Terminted Jupyter kernel gateway')
        else:
            logger.debug('Confirmed termination of Jupyter kernel gateway')

    def find_kernel_thread_by_id(self, kernel_id):
        for thread in self.kernel_threads:
            if kernel_id == thread.kernel_id:
                return thread
        raise KeyError(kernel_id)


class KernelHandler(threading.Thread):
    def __init__(self, base_url, base_ws_url, bufnr, vim_messenger, kernel_id=None, lang='python'):
        threading.Thread.__init__(
            self, name='KernelHandler'
        )
        self.kernel_id = kernel_id
        self.base_url = base_url
        self.base_ws_url = base_ws_url
        self.bufnr = bufnr
        self.lang = lang
        self.vim_messenger = vim_messenger
        self._write_completed = threading.Event()

    def run(self):
        # Get kernel
        if self.kernel_id is None:
            client = HTTPClient()
            response = client.fetch(
                '{}/api/kernels'.format(self.base_url),
                method='POST',
                auth_username='fakeuser',
                auth_password='fakepass',
                body=json_encode({'name': self.lang})
            )
            kernel = json_decode(response.body)
            self.kernel_id = kernel['id']
            logger.debug('Created kernel {0}'.format(self.kernel_id))
        logger.debug('Using kernel {0}'.format(self.kernel_id))
        # Teach kernel id to vim
        self.vim_messenger.ioloop.add_callback(
            lambda: self.vim_messenger.tcp_server.stream.write(
                (json_encode({'msg_type': 'kernel_id',
                              'kernel_id': self.kernel_id,
                              'bufnr': self.bufnr}) + '@@@').encode('utf-8')
            )
        )

        self.ioloop = IOLoop()
        self.ioloop.make_current()
        self.ioloop.run_sync(lambda: self.websocket_handler())

        # Kill kernel
        client = HTTPClient()
        response = client.fetch(
            '{}/api/kernels/{}'.format(self.base_url, self.kernel_id),
            method='DELETE',
            auth_username='fakeuser',
            auth_password='fakepass',
        )
        logger.debug('Killed kernel {0}'.format(self.kernel_id))

    @gen.coroutine
    def websocket_handler(self):
        # Connect websocket
        while 1:
            try:
                ws_req = HTTPRequest(
                    url='{}/api/kernels/{}/channels'.format(
                        self.base_ws_url,
                        url_escape(self.kernel_id)
                    ),
                    auth_username='fakeuser',
                    auth_password='fakepass',
                    request_timeout=5,
                )
                self.ws = yield websocket_connect(ws_req)
                break
            except HTTPTimeoutError:
                pass
        logger.debug('Connected to kernel {} websocket'.format(self.kernel_id))
        # Notify vim that kernel is ready
        msg = {
            'kernel_id': self.kernel_id,
            'bufnr': self.bufnr,
            'msg_type': 'status',
            'content': {'execution_state': 'idle'}
        }
        self.vim_messenger.ioloop.add_callback(
            lambda: self.vim_messenger.tcp_server.stream.write(
                (json_encode(msg) + '@@@').encode('utf-8')
            )
        )

        # Look for stream output for the print in the execute
        while 1:
            msg = yield self.ws.read_message()
            if msg is None:
                break
            msg = json_decode(msg)
            msg['kernel_id'] = self.kernel_id
            msg['bufnr'] = self.bufnr
            KernelHandler.split_by_nl(msg)
            msg_type = msg['msg_type']
            print('Received message type:', msg_type)
            pprint(msg)
            msg = (json_encode(msg) + '@@@').encode('utf-8')
            # Send result to vim
            self.vim_messenger.ioloop.add_callback(
                lambda: self.vim_messenger.tcp_server.stream.write(
                    msg,
                    lambda: self._write_completed.set()
                )
            )
            self._write_completed.wait()
            self._write_completed.clear()

        self.ws.close()
        logger.debug('Closed kernel {} websocket'.format(self.kernel_id))

    def split_by_nl(msg_dict):
        for k in msg_dict.keys():
            if type(msg_dict[k]) is str:
                split_str = msg_dict[k].splitlines()
                if len(split_str) == 1:
                    split_str = split_str[0]
                msg_dict[k] = split_str
            elif type(msg_dict[k]) is dict:
                KernelHandler.split_by_nl(msg_dict[k])


class VimMessenger(threading.Thread):
    class Server(TCPServer):
        async def handle_stream(self, stream, address):
            while 1:
                try:
                    # Save stream
                    self.stream = stream
                    # Recieve data
                    data = await stream.read_until(b'@@@')
                    data = data[:-3].decode('utf-8')
                    data = json_decode(data)

                    if data['type'] == 'start':
                        # Start kernel
                        logger.debug(data)
                        kernel_thread = KernelHandler(
                            base_url=self.jkg_handler.base_url,
                            base_ws_url=self.jkg_handler.base_ws_url,
                            bufnr=data['bufnr'],
                            vim_messenger=self.jkg_handler.vim_messenger,
                            kernel_id=None if 'kernel_id' not in data.keys() else data['kernel_id'],
                            lang=None if 'lang' not in data.keys() else data['lang'],
                        )
                        self.jkg_handler.kernel_threads.append(kernel_thread)
                        kernel_thread.start()
                    elif data['type'] == 'kill':
                        # Kill kernel
                        thread = self.jkg_handler.find_kernel_thread_by_id(data['kernel_id'])
                        thread.ioloop.add_callback(lambda: thread.ws.close())
                    elif data['type'] == 'execute':
                        # Execute on kernel
                        kernel_thread = self.jkg_handler.find_kernel_thread_by_id(data['kernel_id'])
                        kernel_thread.ioloop.add_callback(
                            lambda: kernel_thread.ws.write_message(json_encode({
                                'header': {
                                    'username': '',
                                    'version': '5.0',
                                    'session': '',
                                    'msg_id': data['msg_id'],
                                    'msg_type': 'execute_request'
                                },
                                'parent_header': {},
                                'channel': 'shell',
                                'content': {
                                    'code': data['code'],
                                    'silent': False,
                                    'store_history': True,
                                    'user_expressions': {},
                                    'allow_stdin': False
                                },
                                'metadata': {},
                                'buffers': {}
                            }))
                        )
                except StreamClosedError:
                    break


    def __init__(self, args):
        threading.Thread.__init__(
            self, name='VimMessenger'
        )
        self._args = args
        self.jkg_handler = None

    def run(self):
        self.ioloop = IOLoop()
        self.ioloop.make_current()
        self.tcp_server = VimMessenger.Server()
        self.tcp_server.jkg_handler = self.jkg_handler
        # while not hasattr(self.jkg_handler, 'ws'):
        #     sleep(0.1)
        self.tcp_server.listen(self._args.vim_port)
        logger.debug('Start VimMessenger')
        self.ioloop.start()
        logger.debug('Stopped VimMessenger')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--jupyter_port', default=None, type=int,
        help=('Port of Jupyter. If not specified, Jupyter kernel gateway '
              'will be launched with a random port.')
    )
    parser.add_argument(
        '--jupyter_address', default='localhost', type=str,
        help=('Address for jupyter. Defaults to localhost.')
    )
    parser.add_argument(
        '--vim_port', type=int, required=True,
        help='Port of vim. Message to vim will be sent via this port.'
    )
    parser.add_argument(
        '--kernel-id', default=None,
        help=('The id of an existing kernel for connecting and executing '
              'code. If not specified, a new kernel will be created.')
    )
    args = parser.parse_args()

    # Setup threads
    jkg_handle_thread = JupyterKernelGatewayHandler(args)
    vim_messenger_thread = VimMessenger(args)

    # Share thread information each other
    jkg_handle_thread.vim_messenger = vim_messenger_thread
    vim_messenger_thread.jkg_handler = jkg_handle_thread

    # Start threads
    jkg_handle_thread.start()
    vim_messenger_thread.start()

    # Wait for SIGINT
    while 1:
        try:
            sleep(100)
        except KeyboardInterrupt:
            # Stop threads
            jkg_handle_thread.kill.set()

            vim_messenger_thread.ioloop.add_callback(
                lambda: vim_messenger_thread.tcp_server.stop()
            )
            vim_messenger_thread.ioloop.add_callback(
                lambda: vim_messenger_thread.ioloop.stop()
            )
            break


if __name__ == '__main__':
    main()
