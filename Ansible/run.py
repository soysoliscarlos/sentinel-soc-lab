"""Ejecuta Ansible en WSL sin persistir secretos dentro del workspace."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def inventory(config, key_path, known_hosts):
    return {
        "all": {
            "vars": {
                "ansible_user": config["admin_username"],
                "ansible_connection": "ssh",
                "ansible_ssh_private_key_file": str(key_path),
                "ansible_ssh_common_args": (
                    f"-o UserKnownHostsFile={known_hosts} "
                    "-o StrictHostKeyChecking=yes -o IdentitiesOnly=yes"
                ),
                "lab_domain_name": config["domain_name"],
                "lab_domain_netbios": config["domain_netbios"],
            },
            "children": {
                "linux": {
                    "hosts": {"lab_linux": {"ansible_host": config["linux_ip"]}}
                },
                "windows": {
                    "vars": {"ansible_shell_type": "powershell"},
                    "hosts": {"lab_windows": {"ansible_host": config["windows_ip"]}},
                },
            },
        }
    }


def main():
    request = json.loads(sys.stdin.buffer.read().decode("utf-8-sig"))
    root = Path(__file__).resolve().parent
    executable = Path(sys.executable).parent / "ansible-playbook"
    environment = os.environ.copy()
    environment["SOC_DSRM_PASSWORD"] = request["dsrm"]
    environment["ANSIBLE_HOST_KEY_CHECKING"] = "True"
    # Los temporales quedan en el filesystem Linux, no en OneDrive ni /mnt/c.
    with tempfile.TemporaryDirectory(prefix="soc-ansible-", dir="/tmp") as directory:
        work = Path(directory)
        key = work / "id_rsa"
        key.write_text(request["private_key"], encoding="ascii")
        key.chmod(0o600)
        known_hosts = work / "known_hosts"
        config = request["config"]
        known_hosts.write_text(
            f'{config["linux_ip"]} {request["linux_key"]}\n'
            f'{config["windows_ip"]} {request["windows_key"]}\n',
            encoding="ascii",
        )
        hosts = work / "inventory.json"
        hosts.write_text(json.dumps(inventory(config, key, known_hosts)), encoding="utf-8")
        environment["ANSIBLE_LOCAL_TEMP"] = str(work / "ansible-local")
        return subprocess.run(
            [str(executable), "-i", str(hosts), str(root / "site.yml")],
            env=environment,
            cwd=directory,
            check=False,
        ).returncode


if __name__ == "__main__":
    sys.exit(main())
