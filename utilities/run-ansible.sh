#!/usr/bin/env bash
# Reset file descriptors to blocking mode, then exec ansible-playbook.
# Solves Claude Code's non-blocking IO detection in Ansible.
python3 -c "
import os, fcntl
for fd in (0, 1, 2):
    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, flags & ~os.O_NONBLOCK)
" 2>/dev/null
exec ansible-playbook "$@"
