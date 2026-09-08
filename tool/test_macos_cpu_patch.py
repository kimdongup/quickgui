"""Opt-in regression checks for the separately applied Quickemu CPU patch."""
import os
from pathlib import Path
import re
import subprocess
import unittest


@unittest.skipUnless(os.environ.get("QUICKGUI_PATCHED_QUICKEMU"), "Set QUICKGUI_PATCHED_QUICKEMU to the patched backend")
class MacCpuPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = Path(os.environ["QUICKGUI_PATCHED_QUICKEMU"]).read_text()
        cls.functions = "\n".join(
            re.search(r"^function " + name + r"\(\) \{\n.*?^\}", source, re.M | re.S).group()
            for name in ("get_cpu_info", "check_cpu_flag")
        )

    def run_bash(self, command, features="SSE4.2 AVX1.0 VMX", leaf="AVX2 BMI1", missing=False):
        mock = '''
OS_KERNEL=Darwin
ARCH_HOST=x86_64
function sysctl() {
    [ "$MISSING" = 0 ] || return 1
    shift
    for key in "$@"; do
        case "$key" in
            machdep.cpu.vendor) echo GenuineIntel;;
            machdep.cpu.features) echo "$FEATURES";;
            machdep.cpu.leaf7_features) echo "$LEAF";;
            *) return 1;;
        esac
    done
}
'''
        return subprocess.run(
            [os.environ.get("QUICKGUI_BASH", "bash"), "-c", mock + self.functions + "\n" + command],
            capture_output=True, text=True,
            env={**os.environ, "FEATURES": features, "LEAF": leaf, "MISSING": str(int(missing))},
        )

    def test_both_vendor_names(self):
        for key in ("Vendor", "^Vendor ID"):
            result = self.run_bash(f"get_cpu_info '{key}'")
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout.strip(), "GenuineIntel")

    def test_features_from_both_sysctl_keys(self):
        for feature in ("sse4_2", "avx", "avx2", "vmx"):
            self.assertEqual(self.run_bash(f"check_cpu_flag {feature}").returncode, 0, feature)

    def test_missing_and_substring_features_are_rejected(self):
        self.assertNotEqual(self.run_bash("check_cpu_flag avx2", leaf="AVX2OTHER").returncode, 0)
        self.assertNotEqual(self.run_bash("check_cpu_flag sse4_2", features="SSE4x2").returncode, 0)
        self.assertNotEqual(self.run_bash("check_cpu_flag avx2", missing=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
