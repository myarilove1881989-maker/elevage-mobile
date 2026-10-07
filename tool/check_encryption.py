"""Verify the synthetic Drift fixture with Python's ordinary SQLite library."""
import sqlite3
from pathlib import Path

fixture = Path('.dart_tool/encryption-proof/fixture.db')
assert fixture.is_file(), 'Missing encryption fixture'
assert fixture.read_bytes()[:16] != b'SQLite format 3\x00', 'Plaintext SQLite header'
connection = sqlite3.connect(fixture.absolute().as_uri() + '?mode=ro', uri=True)
try:
    connection.execute('SELECT name FROM sqlite_master').fetchall()
except sqlite3.DatabaseError:
    print('PASS: ordinary SQLite cannot read the encrypted Drift fixture')
else:
    raise RuntimeError('FAIL: database is readable without the encryption key')
finally:
    connection.close()
