from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]


class LoggingConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plays = yaml.safe_load((ROOT / "site.yml").read_text(encoding="utf-8"))
        cls.tasks = yaml.safe_load((ROOT / "linux-logging.yml").read_text(encoding="utf-8"))

    def test_logging_runs_after_service_installation_and_domain_promotion(self):
        linux = self.plays[0]["tasks"]
        self.assertEqual(linux[-1]["ansible.builtin.import_tasks"], "linux-logging.yml")
        windows = self.plays[1]["tasks"]
        promotion = next(i for i, task in enumerate(windows) if "microsoft.ad.domain" in task)
        logging = next(
            i for i, task in enumerate(windows)
            if "Configure-ServiceLogging.ps1" in str(task)
        )
        self.assertGreater(logging, promotion)
        self.assertIn(
            "Web-Http-Logging",
            next(task for task in windows if "ansible.windows.win_feature" in task)[
                "ansible.windows.win_feature"
            ]["name"],
        )

    def test_postgresql_records_all_statements_and_connections_to_local5(self):
        block = next(task["ansible.builtin.blockinfile"]["block"] for task in self.tasks
                     if "ansible.builtin.blockinfile" in task)
        settings = dict(
            (key.strip(), value.strip().strip("'"))
            for key, value in (line.split("=", 1) for line in block.splitlines())
        )
        self.assertEqual(settings["log_statement"], "all")
        self.assertEqual(settings["syslog_facility"], "LOCAL5")
        self.assertEqual(settings["syslog_ident"], "postgres-soc")
        self.assertIn("syslog", settings["log_destination"].split(","))
        self.assertEqual(settings["log_connections"], "on")
        self.assertEqual(settings["log_disconnections"], "on")
        self.assertEqual(settings["log_min_error_statement"], "error")
        self.assertEqual(settings["syslog_split_messages"], "on")

    def test_configurations_are_validated_before_handler_flush(self):
        flush = next(i for i, task in enumerate(self.tasks)
                     if task.get("ansible.builtin.meta") == "flush_handlers")
        commands = [task.get("ansible.builtin.command") for task in self.tasks[:flush]]
        self.assertIn("apache2ctl configtest", commands)
        self.assertIn("rsyslogd -N1", commands)
        self.assertTrue(any("pg_file_settings" in str(command) for command in commands))
        active = [task for task in self.tasks[flush + 1:] if "pg_logging" == task.get("register")]
        self.assertEqual(len(active), 1)
        self.assertIn("log_statement", str(active[0]))
        self.assertIn("failed_when", active[0])

    def test_apache_reader_does_not_ingest_generic_syslog_or_postgresql_twice(self):
        config = (ROOT / "files" / "30-soc-apache.conf").read_text(encoding="utf-8")
        self.assertEqual(config.count('type="imfile"'), 2)
        self.assertEqual(config.count('Facility="local6"'), 2)
        self.assertIn('File="/var/log/apache2/access.log"', config)
        self.assertIn('File="/var/log/apache2/error.log"', config)
        self.assertIn('Tag="apache-access:"', config)
        self.assertIn('Tag="apache-error:"', config)
        self.assertNotIn("/var/log/syslog", config)
        self.assertNotIn("/var/log/postgresql", config)

    @unittest.skipUnless(shutil.which("rsyslogd"), "rsyslogd no esta instalado en el controlador")
    def test_rsyslog_accepts_the_actual_reader_configuration(self):
        reader = ROOT / "files" / "30-soc-apache.conf"
        with tempfile.TemporaryDirectory(prefix="soc-rsyslog-", dir="/tmp") as directory:
            work = Path(directory)
            config = work / "rsyslog.conf"
            config.write_text(
                f'global(workDirectory="{work}")\n'
                f'include(file="{reader}")\n'
                f'action(type="omfile" file="{work / "test.log"}")\n',
                encoding="utf-8",
            )
            result = subprocess.run(
                ["rsyslogd", "-N1", "-f", str(config)],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
