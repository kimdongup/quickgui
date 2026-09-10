import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import prepare_windows_arm_network as network


class NetworkMediaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.image = self.folder / 'network-drivers.iso'
        self.image.write_bytes(b'fixture')
        self.manifest = {'schema': 1, 'sourceSHA256': network.SOURCE_HASH,
                         'files': network.FILES, 'imageSHA256': hashlib.sha256(b'fixture').hexdigest()}
        self.save_manifest()

    def save_manifest(self):
        (self.folder / 'network.json').write_text(json.dumps(self.manifest))

    def test_existing_media_is_preserved(self):
        network.prepare(destination=self.folder)
        self.assertEqual(self.image.read_bytes(), b'fixture')

    def test_changed_media_is_refused(self):
        self.image.write_bytes(b'changed')
        with self.assertRaises(ValueError):
            network.prepare(destination=self.folder)
        self.assertEqual(self.image.read_bytes(), b'changed')

    def test_other_source_or_driver_set_is_refused(self):
        self.manifest['sourceSHA256'] = 'other'
        self.save_manifest()
        with self.assertRaises(ValueError):
            network.verify(self.folder)
        self.manifest['sourceSHA256'] = network.SOURCE_HASH
        self.manifest['files'] = {}
        self.save_manifest()
        with self.assertRaises(ValueError):
            network.verify(self.folder)

    def test_symlink_is_refused(self):
        target = self.folder / 'other.iso'
        self.image.rename(target)
        self.image.symlink_to(target)
        with self.assertRaises(ValueError):
            network.verify(self.folder)

    def test_bad_source_leaves_destination_absent(self):
        target = self.folder / 'new'
        with self.assertRaisesRegex(ValueError, 'checksum'):
            network.prepare(source_iso=self.image, destination=target)
        self.assertFalse(target.exists())


if __name__ == '__main__':
    unittest.main()
