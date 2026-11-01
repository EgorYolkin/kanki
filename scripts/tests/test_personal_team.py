import argparse
import datetime as dt
import json
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts import personal_team as signing

TEAM = "ABCDEFGHIJ"
DEVICE = "00008132-001969D1027A801C"
BUNDLE = "app.example.kanki"


class PersonalTeamTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.state = Path(self.directory.name) / "state"
        patcher = mock.patch.object(signing, "STATE", self.state)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.args = argparse.Namespace(team=TEAM, device=DEVICE, bundle=BUNDLE, force=False)
        self.calls = []
        self.fail_build = False
        self.wrong_team = False

    def fake_run(self, *args, capture=False):
        self.calls.append(args)
        if args[:4] == ("xcrun", "devicectl", "list", "devices"):
            return json.dumps({"result": {"devices": [{
                "hardwareProperties": {"udid": DEVICE, "platform": "iOS"},
                "properties": {"connection": {"state": "connected"}},
            }]}})
        if args[0] == "xcodebuild":
            if self.fail_build:
                raise subprocess.CalledProcessError(1, args)
            app = self.state / "DerivedData/Build/Products/Debug-iphoneos/Kanki.app"
            app.mkdir(parents=True)
            (app / "embedded.mobileprovision").write_bytes(b"profile")
        return ""

    def fake_security(self, *args, **kwargs):
        return mock.Mock(stdout=plistlib.dumps({
            "TeamIdentifier": ["OTHERTEAM1" if self.wrong_team else TEAM],
            "ProvisionedDevices": [DEVICE],
            "Entitlements": {"application-identifier": f"{TEAM}.{BUNDLE}"},
            "ExpirationDate": dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=7),
        }))

    def test_success_skips_until_due_and_failure_does_not_advance_stamp(self):
        with mock.patch.object(signing, "run", side_effect=self.fake_run), mock.patch.object(
            signing.subprocess, "run", side_effect=self.fake_security
        ):
            signing.refresh(self.args)
            stamp = signing.last_success(TEAM, DEVICE, BUNDLE)
            installed_at = json.loads(stamp.read_text())["installed_at"]
            self.assertEqual(sum(call[:4] == ("xcrun", "devicectl", "device", "install") for call in self.calls), 1)
            signing.refresh(self.args)
            self.assertEqual(sum(call[0] == "xcodebuild" for call in self.calls), 1)
            self.args.force = True
            self.fail_build = True
            with self.assertRaises(subprocess.CalledProcessError):
                signing.refresh(self.args)
            self.assertEqual(json.loads(stamp.read_text())["installed_at"], installed_at)
            self.assertEqual(sum(call[:4] == ("xcrun", "devicectl", "device", "install") for call in self.calls), 1)

    def test_mismatched_profile_never_installs_or_records_success(self):
        self.wrong_team = True
        with mock.patch.object(signing, "run", side_effect=self.fake_run), mock.patch.object(
            signing.subprocess, "run", side_effect=self.fake_security
        ):
            with self.assertRaisesRegex(ValueError, "другой команде"):
                signing.refresh(self.args)
        self.assertFalse(signing.last_success(TEAM, DEVICE, BUNDLE).exists())
        self.assertFalse(any(call[:4] == ("xcrun", "devicectl", "device", "install") for call in self.calls))

    def test_agent_install_and_uninstall(self):
        agent = Path(self.directory.name) / "agents" / "refresh.plist"
        logs = Path(self.directory.name) / "logs"
        with mock.patch.object(signing, "AGENT", agent), mock.patch.object(signing, "LOGS", logs), mock.patch.object(
            signing, "run", side_effect=self.fake_run
        ):
            signing.install_agent(self.args)
            config = plistlib.loads(agent.read_bytes())
            self.assertEqual(config["Label"], signing.LABEL)
            self.assertEqual(config["Umask"], 0o077)
            self.assertEqual(config["StartCalendarInterval"], {"Hour": 9, "Minute": 0})
            self.assertTrue(logs.is_dir())
            self.assertEqual(self.calls[-1][:2], ("launchctl", "bootstrap"))
            signing.uninstall_agent()
            self.assertFalse(agent.exists())
            self.assertEqual(self.calls[-1][:2], ("launchctl", "bootout"))


if __name__ == "__main__":
    unittest.main()
