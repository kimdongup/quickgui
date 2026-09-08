import unittest
from fork_release import checked_tag, release_tag


class ReleaseTest(unittest.TestCase):
    def test_version_mapping(self):
        self.assertEqual(release_tag('1.2.10+1'), 'fork-v1.2.10.1')
        self.assertEqual(checked_tag('1.2.10+1', 'fork-v1.2.10.1'), 'fork-v1.2.10.1')

    def test_wrong_tags_cannot_publish_another_version(self):
        for tag in ['v1.2.10', 'fork-v1.2.10.2', 'refs/tags/fork-v1.2.10.1', '$(echo bad)', '../main']:
            with self.assertRaises(ValueError):
                checked_tag('1.2.10+1', tag)

    def test_missing_build_number_is_rejected(self):
        with self.assertRaises(ValueError):
            release_tag('1.2.10')


if __name__ == '__main__':
    unittest.main()
