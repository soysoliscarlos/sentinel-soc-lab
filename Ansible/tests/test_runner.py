import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "runner", Path(__file__).resolve().parents[1] / "run.py"
)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.request = {
            "config": {
                "admin_username": "socadmin",
                "linux_ip": "203.0.113.10",
                "windows_ip": "203.0.113.11",
                "domain_name": "lab.example.test",
                "domain_netbios": "LAB",
            },
            "private_key": "TEST-PRIVATE-KEY\n",
            "dsrm": "TEST-DSRM",
            "linux_key": "ssh-ed25519 AAAALINUX",
            "windows_key": "ssh-ed25519 AAAAWINDOWS",
        }

    def execute(self, exit_code, prefix=b""):
        temporary_paths = []

        def run_command(arguments, *, env, cwd, check):
            work = Path(cwd)
            temporary_paths.append(work)
            key = work / "id_rsa"
            self.assertEqual(stat.S_IMODE(key.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(work.stat().st_mode), 0o700)
            self.assertEqual(key.read_text(), self.request["private_key"])
            self.assertEqual(env["SOC_DSRM_PASSWORD"], self.request["dsrm"])
            self.assertEqual(env["ANSIBLE_HOST_KEY_CHECKING"], "True")
            hosts_text = (work / "inventory.json").read_text()
            self.assertNotIn(self.request["dsrm"], hosts_text)
            self.assertNotIn(self.request["private_key"], hosts_text)
            hosts = json.loads(hosts_text)["all"]
            self.assertIn("StrictHostKeyChecking=yes", hosts["vars"]["ansible_ssh_common_args"])
            self.assertEqual(hosts["children"]["windows"]["vars"]["ansible_shell_type"], "powershell")
            self.assertEqual(
                (work / "known_hosts").read_text().splitlines(),
                ["203.0.113.10 ssh-ed25519 AAAALINUX", "203.0.113.11 ssh-ed25519 AAAAWINDOWS"],
            )
            self.assertEqual(arguments[1:3], ["-i", str(work / "inventory.json")])
            self.assertNotIn(self.request["dsrm"], " ".join(arguments))
            self.assertFalse(check)
            return type("Result", (), {"returncode": exit_code})()

        with patch("sys.stdin", io.TextIOWrapper(io.BytesIO(prefix + json.dumps(self.request).encode()))):
            with patch.object(runner.subprocess, "run", side_effect=run_command):
                self.assertEqual(runner.main(), exit_code)
        self.assertEqual(len(temporary_paths), 1)
        self.assertFalse(temporary_paths[0].exists())
        self.assertNotEqual(os.environ.get("SOC_DSRM_PASSWORD"), self.request["dsrm"])

    def test_success_cleans_secrets(self):
        self.execute(0)

    def test_failure_is_propagated_and_cleans_secrets(self):
        self.execute(2)

    def test_utf8_bom_from_windows_powershell_is_accepted(self):
        self.execute(0, b"\xef\xbb\xbf")

    def test_missing_configuration_fails_before_execution(self):
        with patch("sys.stdin", io.TextIOWrapper(io.BytesIO(b"{}"))):
            with patch.object(runner.subprocess, "run") as command:
                with self.assertRaises(KeyError):
                    runner.main()
                command.assert_not_called()


if __name__ == "__main__":
    unittest.main()
