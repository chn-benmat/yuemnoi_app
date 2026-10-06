"""Startup diagnostics must distinguish occupied ports from access restrictions."""

import errno
import logging
from pathlib import Path
import socket
import subprocess
import sys
from unittest.mock import MagicMock

import pytest

from app.infrastructure.server import BindErrorFilter, run_server


def test_occupied_port_reports_conflict_and_exits_without_stopping_listener():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        if sys.platform == "win32":
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        port = listener.getsockname()[1]
        result = subprocess.run(
            [
                sys.executable, "-c",
                "import sys; from app.infrastructure.server import run_server; "
                "run_server('unused:app', host='127.0.0.1', port=int(sys.argv[1]), "
                "reload=True, log_level='info')",
                str(port),
            ],
            cwd=Path(__file__).resolve().parents[1],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode != 0
        assert f"Port {port} is already in use (port conflict)" in result.stderr
        assert "Original error:" in result.stderr
        assert "Traceback" not in result.stderr
        with socket.create_connection(listener.getsockname(), timeout=1):
            pass


def test_access_denied_without_conflict_does_not_claim_port_is_in_use(monkeypatch):
    error = OSError(errno.EACCES, "Access denied")
    error.winerror = 10013
    probe = MagicMock()
    probe.__enter__.return_value.bind.side_effect = error
    monkeypatch.setattr("app.infrastructure.server.socket.socket", lambda *args: probe)
    record = logging.LogRecord("uvicorn.error", logging.ERROR, __file__, 0, error, (), None)

    assert BindErrorFilter("127.0.0.1", 8000).filter(record)
    assert "127.0.0.1:8000: access denied" in record.getMessage()
    assert "reserved" in record.getMessage()
    assert "port conflict" not in record.getMessage()
    probe.__exit__.assert_called_once()


def test_unrelated_os_error_is_preserved():
    error = OSError(errno.EIO, "Unrelated I/O failure")
    record = logging.LogRecord("uvicorn.error", logging.ERROR, __file__, 0, error, (), None)

    assert BindErrorFilter("127.0.0.1", 8000).filter(record)
    assert record.msg is error


def test_uvicorn_exit_code_is_preserved_and_filter_is_removed(monkeypatch):
    error_logger = logging.getLogger("uvicorn.error")
    original_filters = list(error_logger.filters)

    def fail(*args, **kwargs):
        assert any(isinstance(item, BindErrorFilter) for item in error_logger.filters)
        raise SystemExit(1)

    monkeypatch.setattr("app.infrastructure.server.uvicorn.run", fail)
    with pytest.raises(SystemExit) as failure:
        run_server("unused:app", host="127.0.0.1", port=8000, reload=True, log_level="info")

    assert failure.value.code == 1
    assert error_logger.filters == original_filters
