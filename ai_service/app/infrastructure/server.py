"""Explain socket binding failures without changing Uvicorn's startup lifecycle."""

import errno
import logging
import socket

import uvicorn


def _address_in_use(error: OSError) -> bool:
    return error.errno in (errno.EADDRINUSE, 10048) or getattr(error, "winerror", None) == 10048


def _access_denied(error: OSError) -> bool:
    return error.errno in (errno.EACCES, errno.EPERM, 10013) or getattr(error, "winerror", None) == 10013


class BindErrorFilter(logging.Filter):
    def __init__(self, host: str, port: int):
        super().__init__()
        self.host = host
        self.port = port

    def filter(self, record: logging.LogRecord) -> bool:
        error = record.msg
        if record.levelno < logging.ERROR or not isinstance(error, OSError):
            return True

        occupied = _address_in_use(error)
        denied = _access_denied(error)
        if not occupied and not denied:
            return True

        if denied:
            # Windows can report WSAEACCES for Uvicorn's SO_REUSEADDR bind
            # when another listener owns the address. Retry without reuse to
            # distinguish that case from a reserved port or a permissions issue.
            family = socket.AF_INET6 if ":" in self.host else socket.AF_INET
            try:
                with socket.socket(family, socket.SOCK_STREAM) as probe:
                    probe.bind((self.host, self.port))
            except OSError as probe_error:
                occupied = _address_in_use(probe_error)

        if occupied:
            explanation = (
                f"Port {self.port} is already in use (port conflict) at {self.host}:{self.port}. "
                "Stop the program using this port or launch Uvicorn with a different --port."
            )
        else:
            explanation = (
                f"Cannot bind to {self.host}:{self.port}: access denied. "
                "The port may be reserved by the operating system or blocked by a security policy. "
                "Check port reservations and permissions, or choose a different --port."
            )
        record.msg = f"{explanation} Original error: {error}"
        record.args = ()
        return True


def run_server(app: str, *, host: str, port: int, reload: bool, log_level: str) -> None:
    error_logger = logging.getLogger("uvicorn.error")
    error_filter = BindErrorFilter(host, port)
    error_logger.addFilter(error_filter)
    try:
        uvicorn.run(app, host=host, port=port, reload=reload, log_level=log_level)
    finally:
        error_logger.removeFilter(error_filter)
