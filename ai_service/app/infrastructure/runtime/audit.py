"""Whitelisted effective configuration; credential values are never serialized."""

import os
from pathlib import Path

from dotenv import dotenv_values

from app.infrastructure.runtime.settings_source import setting_values


def effective_settings(configuration, runtime):
    env = {name.upper(): value for name, value in os.environ.items()}
    dotenv_path = configuration._loaded_env_file
    dotenv = {}
    paths = dotenv_path if isinstance(dotenv_path, (tuple, list)) else [dotenv_path]
    for path in paths:
        if isinstance(path, (str, Path)):
            dotenv.update({name.upper(): value for name, value in dotenv_values(path).items()})
    secret_dirs = configuration._loaded_secrets_dir
    secret_dirs = secret_dirs if isinstance(secret_dirs, (tuple, list)) else [secret_dirs]
    values = setting_values(runtime)
    result = {}
    for name in values:
        source = "explicit_settings" if name in configuration._explicit_overrides else (
            "environment" if name in env else "dotenv" if name in dotenv else (
                "file_secret_settings" if any(isinstance(folder, (str, Path)) and (Path(folder) / name).is_file() for folder in secret_dirs) else "runtime_json"))
        value = getattr(configuration, name)
        result[name] = {"value": str(value) if isinstance(value, Path) else value, "source": source}
    return result
