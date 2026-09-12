import tempfile
import unittest
from pathlib import Path
from prepare_windows_x64_firmware import patch_quickemu, install


class WindowsFirmwareTests(unittest.TestCase):
    def test_preserves_original_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'quickemu'
            original = b'#!/bin/bash\n    DISPLAY_RENDER=""\n    EFI_CODE=""\n    EFI_VARS=""\n'
            target.write_bytes(original)
            target.chmod(0o755)
            patch_quickemu(target)
            self.assertIn(b'EFI_CODE="${EFI_CODE:-}"', target.read_bytes())
            self.assertEqual(next(Path(directory).glob('*.before-*')).read_bytes(), original)
            self.assertEqual(target.stat().st_mode & 0o777, 0o755)
            patched = target.read_bytes()
            patch_quickemu(target)
            self.assertEqual(target.read_bytes(), patched)

    def test_unknown_backend_is_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'quickemu'
            target.write_text('different implementation')
            with self.assertRaises(ValueError):
                patch_quickemu(target)
            self.assertEqual(target.read_text(), 'different implementation')

    def test_corrupt_package_rejected_before_installation(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / 'ovmf.deb'
            package.write_bytes(b'not a Debian package')
            destination = Path(directory) / 'firmware'
            with self.assertRaises(ValueError):
                install(package, destination)
            self.assertFalse(destination.exists())


if __name__ == '__main__':
    unittest.main()
