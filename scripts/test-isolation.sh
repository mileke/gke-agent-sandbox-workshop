#!/usr/bin/env bash
set -euo pipefail
kubectl exec -i deploy/data-agent -- python3 - <<'EOF'
from k8s_agent_sandbox import SandboxClient

checks = [
    ("Kernel", "uname -r"),
    ("Host /etc/shadow", "cat /etc/shadow"),
    ("Metadata server", "python3 -c \"import urllib.request as u; print(u.urlopen(u.Request('http://metadata.google.internal/computeMetadata/v1/project/project-id', headers={'Metadata-Flavor': 'Google'}), timeout=5).read().decode())\""),
    ("Public internet", "python3 -c \"import urllib.request as u; print(u.urlopen('https://pypi.org/simple/pip/', timeout=10).status)\""),
]
with SandboxClient(template_name="python-runtime-template", namespace="default") as sandbox:
    for name, command in checks:
        result = sandbox.run(command)
        output = (result.stdout or result.stderr).strip().splitlines()
        print(f"{name:18} {output[-1][:120] if output else '(no output)'}")
EOF
