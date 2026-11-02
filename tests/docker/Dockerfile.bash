# =============================================================================
# Development-host emulation: Debian with bash, dash and GNU userland.
# fio-check runs under the shell named in FIO_SHELL (bash or dash).
# =============================================================================
FROM debian:trixie-slim
WORKDIR /src
CMD ["bash", "./test_fio_check.sh"]
