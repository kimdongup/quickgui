import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import prepare_windows_arm_firmware as firmware


class FirmwareSafetyTests(unittest.TestCase):
    def test_corrupt_download_rejected_before_unpacking(self):
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            firmware.unpack('edk2-aarch64-secure-code.fd.bz2', b'corrupted download')

    def test_modified_existing_template_is_rejected_without_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            image = folder / 'uefi-vars.fd'
            image.write_bytes(b'original')
            with patch.dict(firmware.HASHES, {'uefi-vars.fd': hashlib.sha256(b'original').hexdigest()}, clear=True):
                firmware.verify(folder)
                image.write_bytes(b'changed')
                with self.assertRaises(ValueError):
                    firmware.verify(folder)
                self.assertEqual(image.read_bytes(), b'changed')

    def test_symbolic_template_is_refused_even_if_bytes_match(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            original = folder / 'original'
            original.write_bytes(b'original')
            (folder / 'uefi-vars.fd').symlink_to(original)
            with patch.dict(firmware.HASHES, {'uefi-vars.fd': hashlib.sha256(b'original').hexdigest()}, clear=True):
                with self.assertRaises(ValueError):
                    firmware.verify(folder)
            self.assertEqual(original.read_bytes(), b'original')


if __name__ == '__main__':
    unittest.main()
